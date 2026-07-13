import SwiftUI
import CosmodromeCore

/// Horizontally paged grid. Pages track the fingers 1:1 (mouse drag AND
/// trackpad scroll), recede in depth as they leave center, rubber-band past
/// the ends and spring-snap on release — v0.2's interactive hand-feel.
struct PagerView: View {
    @ObservedObject var state: GridState
    @ObservedObject var drive: PagerDrive
    @ObservedObject var drag: DragCoordinator

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let pages = state.grid.paginate(state.displayCells)
            let progress = rubberedProgress(width: width, pageCount: pages.count)

            HStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    PageGridView(
                        state: state,
                        drag: drag,
                        cells: pages[index],
                        pageIndex: index,
                        size: geo.size
                    )
                    .frame(width: width, height: geo.size.height)
                    .scaleEffect(depthScale(index, progress: progress))
                    .opacity(depthOpacity(index, progress: progress))
                }
            }
            .offset(x: -progress * width)
            .contentShape(Rectangle())
            .simultaneousGesture(backgroundDrag)
            .onAppear { report(geo) }
            .onChange(of: geo.size) { _, _ in report(geo) }
        }
    }

    // MARK: - Live progress

    /// Fractional page position, fingers included, softened past the ends.
    private func rubberedProgress(width: CGFloat, pageCount: Int) -> CGFloat {
        let raw = CGFloat(state.currentPage) - drive.liveOffset / width
        let maxProgress = CGFloat(max(pageCount - 1, 0))
        if raw < 0 { return raw / 3 }
        if raw > maxProgress { return maxProgress + (raw - maxProgress) / 3 }
        return raw
    }

    private func depthScale(_ index: Int, progress: CGFloat) -> CGFloat {
        1 - min(abs(CGFloat(index) - progress), 1) * 0.08
    }

    private func depthOpacity(_ index: Int, progress: CGFloat) -> Double {
        1 - min(abs(CGFloat(index) - progress), 1) * 0.35
    }

    // MARK: - Mouse background drag

    private var backgroundDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard drag.session == nil else { return }
                state.isPageDragging = true
                drive.gestureActive = true
                drive.liveOffset = value.translation.width
            }
            .onEnded { value in
                guard drag.session == nil else { return }
                state.settlePager(predictedTravel: value.predictedEndTranslation.width)
                // The same mouse-up also fires the button it started on, and
                // the button action runs after onEnded — clear asynchronously.
                DispatchQueue.main.async { state.isPageDragging = false }
            }
    }

    // MARK: - Geometry for scroll snapping and drag hit-testing

    private func report(_ geo: GeometryProxy) {
        drive.pageWidth = geo.size.width
        drag.pagerFrame = geo.frame(in: .named("overlay"))
        drag.pagerMetrics = PagerMetrics(
            columns: state.grid.columns,
            rows: state.grid.rows,
            pageWidth: geo.size.width,
            pageHeight: geo.size.height,
            horizontalInset: geo.size.width * 0.11
        )
    }
}

/// One page: a fixed 7×5 lattice of evenly spaced cells (apps, folders, and
/// the drag gap).
struct PageGridView: View {
    @ObservedObject var state: GridState
    @ObservedObject var drag: DragCoordinator
    let cells: [DisplayCell]
    let pageIndex: Int
    let size: CGSize

    var body: some View {
        let columns = state.grid.columns
        let rows = state.grid.rows
        let horizontalInset = size.width * 0.11
        let contentWidth = size.width - horizontalInset * 2
        let cellWidth = contentWidth / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)
        let iconSize = min(max(min(cellWidth, cellHeight) * 0.55, 48), 116)
        let pageStart = pageIndex * state.grid.perPage

        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: columns),
            spacing: 0
        ) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { position, cell in
                cellView(
                    cell,
                    globalIndex: pageStart + position,
                    position: position,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    iconSize: iconSize,
                    horizontalInset: horizontalInset
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { state.requestHide() }
    }

    @ViewBuilder
    private func cellView(
        _ cell: DisplayCell,
        globalIndex: Int,
        position: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        iconSize: CGFloat,
        horizontalInset: CGFloat
    ) -> some View {
        switch cell {
        case .gap:
            Color.clear.frame(width: cellWidth, height: cellHeight)

        case .node(let node):
            switch node {
            case .app(let appID):
                if let item = state.appsByID[appID] {
                    AppIconCell(
                        item: item,
                        iconSize: iconSize,
                        width: cellWidth,
                        height: cellHeight,
                        isSelected: state.selection == globalIndex,
                        isCombineTarget: drag.combineTargetID == appID,
                        interactive: !drag.isActive,
                        action: {
                            if !state.isPageDragging { state.launch(item) }
                        },
                        reveal: { state.reveal(item) }
                    )
                    .modifier(NodeDragModifier(
                        drag: drag,
                        node: node,
                        source: .grid,
                        iconSize: iconSize,
                        enabled: state.query.isEmpty
                    ))
                }

            case .folder(let folder):
                FolderIconCell(
                    folder: folder,
                    previewApps: folder.appIDs.prefix(9).compactMap { state.appsByID[$0] },
                    iconSize: iconSize,
                    width: cellWidth,
                    height: cellHeight,
                    isSelected: state.selection == globalIndex,
                    isDropTarget: drag.intoFolderID == folder.id,
                    interactive: !drag.isActive,
                    action: {
                        guard !state.isPageDragging else { return }
                        state.openFolder(folder.id, anchor: cellCenter(
                            position: position, cellWidth: cellWidth,
                            cellHeight: cellHeight, horizontalInset: horizontalInset
                        ))
                    },
                    onRename: {
                        state.openFolder(folder.id, anchor: cellCenter(
                            position: position, cellWidth: cellWidth,
                            cellHeight: cellHeight, horizontalInset: horizontalInset
                        ))
                        state.beginRename()
                    },
                    onUngroup: { state.ungroup(folder.id) }
                )
                .modifier(NodeDragModifier(
                    drag: drag,
                    node: node,
                    source: .grid,
                    iconSize: iconSize,
                    enabled: state.query.isEmpty
                ))
            }
        }
    }

    /// Cell center in overlay coordinates, computed from grid math — the
    /// zoom anchor for the opening folder panel.
    private func cellCenter(position: Int, cellWidth: CGFloat, cellHeight: CGFloat, horizontalInset: CGFloat) -> CGPoint {
        let column = position % state.grid.columns
        let row = position / state.grid.columns
        let frame = drag.pagerFrame
        return CGPoint(
            x: frame.minX + horizontalInset + (CGFloat(column) + 0.5) * cellWidth,
            y: frame.minY + (CGFloat(row) + 0.5) * cellHeight
        )
    }
}
