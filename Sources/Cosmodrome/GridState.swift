import AppKit
import SwiftUI
import CosmodromeCore

enum Anim {
    static let page = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let appear = Animation.spring(response: 0.38, dampingFraction: 0.92)
    static let disappear = Animation.easeIn(duration: 0.16)
    static let launch = Animation.easeIn(duration: 0.22)
    static let folder = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let reflow = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

/// What one grid slot shows: a node, or the moving gap while dragging.
enum DisplayCell: Identifiable, Hashable {
    case node(LayoutNode)
    case gap

    var id: String {
        switch self {
        case .node(let node): return node.id
        case .gap: return "gap"
        }
    }

    var node: LayoutNode? {
        if case .node(let node) = self { return node }
        return nil
    }
}

/// Everything the overlay renders, plus the little state machine that drives
/// the show/launch/hide transitions. The OverlayController is the only writer
/// of `phase`; views react.
@MainActor
final class GridState: ObservableObject {
    enum Phase {
        case hidden, shown, launching
    }

    @Published var allApps: [AppItem] = [] {
        didSet {
            filterCache = nil
            appsByID = Dictionary(allApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    private(set) var appsByID: [String: AppItem] = [:]

    /// The user's arrangement — order and folders. All mutations flow through
    /// applyLayout so persistence can't be forgotten.
    @Published private(set) var layout = AppLayout()

    @Published private(set) var query: String = ""
    @Published var currentPage: Int = 0
    @Published var selection: Int? = nil
    @Published var phase: Phase = .hidden
    @Published var wallpaper: NSImage? = nil
    @Published var dimAmount: Double = UserDefaults.standard.object(forKey: "dimAmount") as? Double ?? 0.32 {
        didSet { UserDefaults.standard.set(dimAmount, forKey: "dimAmount") }
    }

    // MARK: Folders

    @Published var openFolderID: UUID? = nil
    @Published var folderPage: Int = 0
    @Published var folderSelection: Int? = nil
    @Published var renamingFolder = false
    @Published var renameBuffer = ""
    /// Overlay-space anchor the panel zooms out of (the clicked folder's cell).
    var folderAnchorPoint: CGPoint? = nil

    /// True while a page-swipe drag is in flight; the mouse-up that ends a
    /// swipe also fires the icon button it started on, so cells consult this
    /// before launching. Deliberately not @Published (set per pointer event).
    var isPageDragging = false

    /// --demo runs on a throwaway layout; never write it to disk.
    var persistenceEnabled = true

    private var filterCache: (query: String, apps: [AppItem])?

    let grid = GridMath(columns: 7, rows: 5)
    let folderGrid = GridMath(columns: 5, rows: 3)
    let pagerDrive = PagerDrive()
    private(set) lazy var drag = DragCoordinator(state: self)

    /// Wired up by OverlayController.
    var onHideRequest: () -> Void = {}
    var onLaunchRequest: (AppItem) -> Void = { _ in }
    var onRevealRequest: (AppItem) -> Void = { _ in }

    // MARK: - What's on the grid

    /// Memoized: the filter folds every app name, and views read this several
    /// times per body pass — recomputing per access would burn a millisecond
    /// of string folding on every drag frame.
    var visibleApps: [AppItem] {
        if query.isEmpty { return allApps }
        if let cache = filterCache, cache.query == query { return cache.apps }
        let filtered = SearchEngine.filter(allApps, query: query)
        filterCache = (query, filtered)
        return filtered
    }

    /// Searching flattens folders away: results are plain apps.
    var visibleNodes: [LayoutNode] {
        query.isEmpty ? layout.nodes : visibleApps.map { .app($0.id) }
    }

    /// What the pager actually renders — during a grid drag, the dragged node
    /// is lifted out and a gap slot marks the current drop position.
    var displayCells: [DisplayCell] {
        if !query.isEmpty { return visibleNodes.map { .node($0) } }
        guard let session = drag.session else { return layout.nodes.map { .node($0) } }
        var cells = layout.nodes
            .filter { $0.id != session.node.id }
            .map { DisplayCell.node($0) }
        if let gap = drag.gapIndex {
            cells.insert(.gap, at: min(max(gap, 0), cells.count))
        }
        return cells
    }

    var pageCount: Int { grid.pageCount(for: displayCells.count) }

    var openFolder: AppFolder? {
        guard let id = openFolderID, let index = layout.indexOfFolder(id) else { return nil }
        return layout.nodes[index].folder
    }

    /// The open folder's slots, gap included while dragging within it.
    var folderDisplayCells: [DisplayCell] {
        guard let folder = openFolder else { return [] }
        var ids = folder.appIDs
        if let session = drag.session, let appID = session.node.appID {
            ids.removeAll { $0 == appID }
        }
        var cells = ids.map { DisplayCell.node(.app($0)) }
        if let gap = drag.folderGapIndex {
            cells.insert(.gap, at: min(max(gap, 0), cells.count))
        }
        return cells
    }

    var folderPageCount: Int { folderGrid.pageCount(for: folderDisplayCells.count) }

    // MARK: - Query editing (all keyboard input is routed here by the controller)

    func setQuery(_ newValue: String) {
        guard newValue != query else { return }
        query = newValue
        currentPage = 0
        selection = (newValue.isEmpty || visibleApps.isEmpty) ? nil : 0
    }

    func appendToQuery(_ s: String) { setQuery(query + s) }

    func backspace() {
        guard !query.isEmpty else { return }
        setQuery(String(query.dropLast()))
    }

    // MARK: - Selection & paging

    func moveSelection(_ direction: GridMath.Direction) {
        let total = visibleNodes.count
        guard total > 0 else { return }
        let target: Int
        if let current = selection {
            target = grid.move(from: current, direction: direction, total: total)
        } else {
            target = grid.firstIndex(onPage: currentPage, total: total)
        }
        selection = target
        let page = grid.page(of: target)
        if page != currentPage {
            withAnimation(Anim.page) { currentPage = page }
        }
    }

    var selectedNode: LayoutNode? {
        guard let selection, visibleNodes.indices.contains(selection) else { return nil }
        return visibleNodes[selection]
    }

    func flipPage(_ delta: Int) {
        goToPage(currentPage + delta)
    }

    func goToPage(_ page: Int) {
        let target = min(max(page, 0), pageCount - 1)
        guard target != currentPage else { return }
        selection = nil
        withAnimation(Anim.page) {
            currentPage = target
        }
    }

    /// Snap after a live drag/scroll: nearest page, with a flick nudge.
    func settlePager(predictedTravel: CGFloat? = nil) {
        let drive = pagerDrive
        let width = max(drive.pageWidth, 1)
        var raw = CGFloat(currentPage) - drive.liveOffset / width
        if let predicted = predictedTravel {
            let predictedRaw = CGFloat(currentPage) - predicted / width
            if abs(predictedRaw - CGFloat(currentPage)) > 0.45 { raw = predictedRaw }
        } else if Int(raw.rounded()) == currentPage {
            if drive.liveOffset < -width * 0.08, drive.lastDelta < -4 { raw = CGFloat(currentPage) + 1 }
            else if drive.liveOffset > width * 0.08, drive.lastDelta > 4 { raw = CGFloat(currentPage) - 1 }
        }
        let target = min(max(Int(raw.rounded()), 0), pageCount - 1)
        if target != currentPage { selection = nil }
        drive.gestureActive = false
        withAnimation(Anim.page) {
            currentPage = target
            drive.liveOffset = 0
        }
    }

    // MARK: - Folders

    func openFolder(_ id: UUID, anchor: CGPoint? = nil) {
        folderAnchorPoint = anchor
        folderPage = 0
        folderSelection = nil
        renamingFolder = false
        withAnimation(Anim.folder) { openFolderID = id }
    }

    func closeFolder() {
        guard openFolderID != nil else { return }
        if renamingFolder { commitRename() }
        folderSelection = nil
        withAnimation(Anim.folder) { openFolderID = nil }
    }

    func folderFlip(_ delta: Int) {
        let target = min(max(folderPage + delta, 0), folderPageCount - 1)
        guard target != folderPage else { return }
        folderSelection = nil
        withAnimation(Anim.page) { folderPage = target }
    }

    func moveFolderSelection(_ direction: GridMath.Direction) {
        let total = folderDisplayCells.count
        guard total > 0 else { return }
        let target: Int
        if let current = folderSelection {
            target = folderGrid.move(from: current, direction: direction, total: total)
        } else {
            target = folderGrid.firstIndex(onPage: folderPage, total: total)
        }
        folderSelection = target
        let page = folderGrid.page(of: target)
        if page != folderPage {
            withAnimation(Anim.page) { folderPage = page }
        }
    }

    var selectedFolderApp: AppItem? {
        guard let folderSelection,
              folderDisplayCells.indices.contains(folderSelection),
              let appID = folderDisplayCells[folderSelection].node?.appID else { return nil }
        return appsByID[appID]
    }

    func ungroup(_ id: UUID) {
        if openFolderID == id { closeFolder() }
        applyLayout(LayoutEngine.ungrouping(folder: id, in: layout))
    }

    func removeFromOpenFolder(_ appID: String) {
        guard let id = openFolderID else { return }
        var updated = LayoutEngine.removing(.app(appID), source: .folder(id), from: layout)
        updated = LayoutEngine.inserting(.app(appID), at: updated.nodes.count, in: updated)
        if updated.indexOfFolder(id) == nil { closeFolder() }
        applyLayout(updated)
    }

    // MARK: - Renaming (headless, keystrokes routed by the controller)

    func beginRename() {
        guard let folder = openFolder else { return }
        renameBuffer = folder.name
        renamingFolder = true
    }

    func renameAppend(_ s: String) { renameBuffer += s }

    func renameBackspace() {
        guard !renameBuffer.isEmpty else { return }
        renameBuffer.removeLast()
    }

    func commitRename() {
        guard renamingFolder else { return }
        renamingFolder = false
        guard let id = openFolderID else { return }
        applyLayout(LayoutEngine.renaming(folder: id, to: renameBuffer, in: layout), animated: false)
    }

    func cancelRename() {
        renamingFolder = false
    }

    // MARK: - Launching

    /// What Return should open while searching: the arrowed selection, or the top hit.
    func searchItemToLaunch() -> AppItem? {
        guard !query.isEmpty else { return nil }
        let apps = visibleApps
        guard !apps.isEmpty else { return nil }
        if let selection, apps.indices.contains(selection) { return apps[selection] }
        return apps[0]
    }

    func requestHide() { onHideRequest() }
    func launch(_ item: AppItem) { onLaunchRequest(item) }
    func reveal(_ item: AppItem) { onRevealRequest(item) }

    // MARK: - Layout & app list

    func applyLayout(_ new: AppLayout, animated: Bool = true) {
        guard new != layout else { return }
        if animated {
            withAnimation(Anim.reflow) { layout = new }
        } else {
            layout = new
        }
        currentPage = min(currentPage, pageCount - 1)
        if persistenceEnabled { LayoutStore.save(layout) }
    }

    func arrangeAlphabetically() {
        closeFolder()
        applyLayout(LayoutEngine.sortedAlphabetically(apps: allApps))
        goToPage(0)
    }

    func arrangeByCategory() {
        closeFolder()
        applyLayout(LayoutEngine.groupedByCategory(apps: allApps))
        goToPage(0)
    }

    func resetForShow() {
        query = ""
        currentPage = 0
        selection = nil
        isPageDragging = false
        pagerDrive.liveOffset = 0
        openFolderID = nil
        folderSelection = nil
        renamingFolder = false
        drag.cancel()
        phase = .hidden
    }

    nonisolated static let ownBundleID = Bundle.main.bundleIdentifier ?? "io.github.cleoanka.Cosmodrome"

    /// First scan + layout bootstrap, synchronous so the first show is complete.
    func bootstrap() {
        let apps = AppScanner.scan(excludingBundleIDs: [Self.ownBundleID])
        allApps = apps
        let stored = persistenceEnabled ? LayoutStore.load() : nil
        let reconciled = LayoutEngine.reconcile(stored ?? LayoutEngine.initialLayout(from: apps), with: apps)
        layout = reconciled
        if persistenceEnabled, stored != reconciled { LayoutStore.save(reconciled) }
    }

    func refreshApps() {
        Task.detached(priority: .userInitiated) {
            let items = AppScanner.scan(excludingBundleIDs: [Self.ownBundleID])
            await MainActor.run { [weak self] in
                guard let self, items != self.allApps else { return }
                // The list may shift under an existing selection; keep the
                // highlight on the same node, not the same index.
                let selectedID = self.selection.flatMap {
                    self.visibleNodes.indices.contains($0) ? self.visibleNodes[$0].id : nil
                }
                self.allApps = items
                self.applyLayout(LayoutEngine.reconcile(self.layout, with: items), animated: false)
                self.currentPage = min(self.currentPage, self.pageCount - 1)
                self.selection = selectedID.flatMap { id in
                    self.visibleNodes.firstIndex { $0.id == id }
                }
            }
        }
    }
}
