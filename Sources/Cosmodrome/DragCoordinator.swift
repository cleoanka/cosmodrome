import AppKit
import SwiftUI
import CosmodromeCore

/// The cursor-following ghost. High-frequency position updates live here so
/// only the ghost layer re-renders per pointer event.
@MainActor
final class DragGhost: ObservableObject {
    @Published var location: CGPoint = .zero
}

/// Orchestrates pick-up / hover / drop for icon dragging: proposals (gap,
/// combine, into-folder), edge page-flipping, and the final layout commit.
/// All geometry comes in overlay coordinates; the pure math is DropMath.
@MainActor
final class DragCoordinator: ObservableObject {
    struct Session {
        let node: LayoutNode
        let source: LayoutEngine.DragSource
        let iconSize: CGFloat
    }

    enum Proposal: Hashable {
        case insertGrid(Int)          // reduced top-level index
        case combine(String)          // target loose-app id
        case intoFolder(UUID)
        case insertFolder(UUID, Int)  // reduced index inside the folder
    }

    @Published private(set) var session: Session?
    @Published private(set) var proposal: Proposal?
    let ghost = DragGhost()

    // Reported by the views' geometry readers (overlay coordinate space).
    var pagerFrame: CGRect = .zero
    var pagerMetrics: PagerMetrics?
    var folderPanelFrame: CGRect = .zero
    var folderGridFrame: CGRect = .zero
    var folderMetrics: PagerMetrics?

    private unowned let state: GridState
    private var edgeFlipTask: Task<Void, Never>?
    private var edgeDirection = 0
    private var lastPoint: CGPoint = .zero

    init(state: GridState) {
        self.state = state
    }

    var isActive: Bool { session != nil }

    /// Where the visual gap sits in the grid's displayed cells.
    var gapIndex: Int? {
        if case .insertGrid(let index)? = proposal { return index }
        return nil
    }

    /// Where the visual gap sits inside the open folder's displayed cells.
    var folderGapIndex: Int? {
        if case .insertFolder(_, let index)? = proposal { return index }
        return nil
    }

    var combineTargetID: String? {
        if case .combine(let id)? = proposal { return id }
        return nil
    }

    var intoFolderID: UUID? {
        if case .intoFolder(let id)? = proposal { return id }
        return nil
    }

    // MARK: - Session lifecycle

    func begin(node: LayoutNode, source: LayoutEngine.DragSource, iconSize: CGFloat, at point: CGPoint) {
        guard session == nil, state.query.isEmpty else { return }
        state.selection = nil
        state.folderSelection = nil
        ghost.location = point
        NSLog("COSMO-DRAG begin node=%@", node.id)
        withAnimation(Anim.reflow) {
            session = Session(node: node, source: source, iconSize: iconSize)
        }
        update(to: point)
    }

    func update(to point: CGPoint) {
        guard session != nil else { return }
        ghost.location = point
        lastPoint = point
        propose(at: point)
    }

    func end(at point: CGPoint) {
        guard let session else { return }
        cancelEdgeFlip()
        let landing = proposal
        NSLog("COSMO-DRAG end proposal=%@", String(describing: landing))

        var layout = state.layout
        switch landing {
        case .insertFolder(let folderID, let index) where session.source == .folder(folderID):
            if let appID = session.node.appID {
                layout = LayoutEngine.reorderingInFolder(folderID, appID: appID, to: index, in: layout)
            }
        case .insertGrid(let index):
            layout = LayoutEngine.removing(session.node, source: session.source, from: layout)
            layout = LayoutEngine.inserting(session.node, at: index, in: layout)
        case .combine(let targetID):
            if let appID = session.node.appID {
                let name = LayoutEngine.suggestedFolderName(
                    target: state.appsByID[targetID],
                    dragged: state.appsByID[appID]
                )
                layout = LayoutEngine.removing(session.node, source: session.source, from: layout)
                layout = LayoutEngine.combining(appID: appID, ontoAppID: targetID, name: name, in: layout)
            }
        case .intoFolder(let folderID):
            if let appID = session.node.appID {
                layout = LayoutEngine.removing(session.node, source: session.source, from: layout)
                layout = LayoutEngine.adding(appID: appID, toFolder: folderID, in: layout)
            }
        case .insertFolder, nil:
            break // snap back, nothing changes
        }

        withAnimation(Anim.reflow) {
            self.session = nil
            self.proposal = nil
            state.applyLayout(layout)
        }
    }

    func cancel() {
        guard session != nil else { return }
        cancelEdgeFlip()
        withAnimation(Anim.reflow) {
            session = nil
            proposal = nil
        }
    }

    // MARK: - Proposals

    private func propose(at point: CGPoint) {
        guard let session else { return }

        if state.openFolderID != nil {
            if folderPanelFrame.contains(point) {
                proposeInFolder(at: point)
                return
            }
            // Dragged out of the panel: the panel folds away and the drag
            // continues over the grid (this is how apps leave a folder).
            state.closeFolder()
        }

        guard session.node.appID != nil || session.source == .grid else { return }
        proposeInGrid(at: point)
    }

    private func proposeInGrid(at point: CGPoint) {
        guard let metrics = pagerMetrics, let session else { return }
        let local = CGPoint(x: point.x - pagerFrame.minX, y: point.y - pagerFrame.minY)
        let cells = state.displayCells
        let hit = DropMath.hitTest(local, metrics: metrics, currentPage: state.currentPage, totalItems: cells.count)

        switch hit {
        case .flipLeft:
            scheduleEdgeFlip(-1)
            return
        case .flipRight:
            scheduleEdgeFlip(1)
            return
        case .cell(let displayed, let zone):
            cancelEdgeFlip()
            if zone == .center, displayed < cells.count,
               let target = cells[displayed].node {
                switch target {
                case .app(let targetID) where session.node.appID != nil && targetID != session.node.appID:
                    setProposal(.combine(targetID))
                    return
                case .folder(let folder) where session.node.appID != nil:
                    setProposal(.intoFolder(folder.id))
                    return
                default:
                    break // folder-onto-folder never nests; fall through to insert
                }
            }
            guard let displayedInsertion = DropMath.insertionIndex(for: hit, totalItems: cells.count) else { return }
            let currentGap = cells.firstIndex(of: .gap)
            let reduced = DropMath.reducedIndex(fromDisplayed: displayedInsertion, gapIndex: currentGap)
            setProposal(.insertGrid(reduced))
        }
    }

    private func proposeInFolder(at point: CGPoint) {
        guard let metrics = folderMetrics, let folderID = state.openFolderID, let session else { return }
        // Only apps live in folders; a dragged folder hovering the panel parks.
        guard session.node.appID != nil else { return }

        let local = CGPoint(x: point.x - folderGridFrame.minX, y: point.y - folderGridFrame.minY)
        let cells = state.folderDisplayCells
        let hit = DropMath.hitTest(
            local, metrics: metrics, currentPage: state.folderPage,
            totalItems: cells.count, edgeMargin: 24
        )

        switch hit {
        case .flipLeft:
            scheduleEdgeFlip(-1, inFolder: true)
        case .flipRight:
            scheduleEdgeFlip(1, inFolder: true)
        case .cell:
            cancelEdgeFlip()
            guard let displayedInsertion = DropMath.insertionIndex(for: hit, totalItems: cells.count) else { return }
            let currentGap = cells.firstIndex(of: .gap)
            let reduced = DropMath.reducedIndex(fromDisplayed: displayedInsertion, gapIndex: currentGap)
            setProposal(.insertFolder(folderID, reduced))
        }
    }

    private func setProposal(_ new: Proposal?) {
        guard new != proposal else { return }
        withAnimation(Anim.reflow) { proposal = new }
    }

    // MARK: - Edge flipping

    private func scheduleEdgeFlip(_ direction: Int, inFolder: Bool = false) {
        guard edgeDirection != direction else { return }
        cancelEdgeFlip()
        edgeDirection = direction
        edgeFlipTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            while let self, !Task.isCancelled, self.session != nil {
                if inFolder {
                    self.state.folderFlip(direction)
                } else {
                    self.state.flipPage(direction)
                }
                // Re-evaluate under the new page so the gap lands somewhere sane.
                self.propose(at: self.lastPoint)
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
        }
    }

    private func cancelEdgeFlip() {
        edgeFlipTask?.cancel()
        edgeFlipTask = nil
        edgeDirection = 0
    }
}
