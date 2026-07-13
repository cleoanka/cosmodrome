import AppKit
import SwiftUI
import CosmodromeCore

/// The folder's grid tile: a glass square previewing up to 9 member icons.
struct FolderTileView: View {
    let apps: [AppItem]
    let size: CGFloat
    var highlighted: Bool = false

    var body: some View {
        let padding = size * 0.11
        let gap = size * 0.05
        let mini = (size - padding * 2 - gap * 2) / 3

        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(.white.opacity(highlighted ? 0.30 : 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(.white.opacity(highlighted ? 0.5 : 0.18), lineWidth: 1)
            )
            .overlay(
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { column in
                                miniIcon(at: row * 3 + column)
                                    .frame(width: mini, height: mini)
                            }
                        }
                    }
                }
                .padding(padding)
            )
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private func miniIcon(at index: Int) -> some View {
        if index < apps.count {
            AppIconImage(item: apps[index])
        } else {
            Color.clear
        }
    }
}

/// Folder as a grid cell: tile + label, opens on click, swells when a
/// dragged app hovers over it.
struct FolderIconCell: View {
    let folder: AppFolder
    let previewApps: [AppItem]
    let iconSize: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    var isDropTarget: Bool = false
    var interactive: Bool = true
    let action: () -> Void
    let onRename: () -> Void
    let onUngroup: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                FolderTileView(apps: previewApps, size: iconSize, highlighted: isDropTarget)
                    .scaleEffect(isDropTarget ? 1.12 : 1)
                    .animation(Anim.reflow, value: isDropTarget)

                Text(folder.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: width - 36)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(selectionPlate)
        }
        .buttonStyle(AppIconButtonStyle(hovering: hovering && interactive))
        .frame(width: width, height: height)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { action() }
            Button("Rename") { onRename() }
            Divider()
            Button("Ungroup") { onUngroup() }
        }
    }

    @ViewBuilder
    private var selectionPlate: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

/// Hosts the dimming backdrop + the expanded folder panel, and knows how to
/// zoom the panel out of the folder's grid cell.
struct FolderLayer: View {
    @ObservedObject var state: GridState
    @ObservedObject var drag: DragCoordinator

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let folder = state.openFolder {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { state.closeFolder() }
                        .transition(.opacity)

                    FolderPanelView(state: state, drag: drag, folder: folder, container: geo.size)
                        .transition(zoomTransition(container: geo.size))
                }
            }
        }
    }

    private func zoomTransition(container: CGSize) -> AnyTransition {
        let center = CGPoint(x: container.width / 2, y: container.height * 0.46)
        let anchor = state.folderAnchorPoint ?? center
        let offset = CGSize(width: anchor.x - center.x, height: anchor.y - center.y)
        return .modifier(
            active: FolderZoomModifier(scale: 0.12, offset: offset, opacity: 0),
            identity: FolderZoomModifier(scale: 1, offset: .zero, opacity: 1)
        )
    }
}

private struct FolderZoomModifier: ViewModifier {
    let scale: CGFloat
    let offset: CGSize
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
    }
}

/// The expanded folder: name (click to rename — keystrokes are routed here
/// by the controller, no focusable field), paged 5×3 app grid, page dots.
struct FolderPanelView: View {
    @ObservedObject var state: GridState
    @ObservedObject var drag: DragCoordinator
    let folder: AppFolder
    let container: CGSize

    @State private var caretVisible = true
    @State private var hoveringName = false

    private var panelWidth: CGFloat { min(container.width * 0.58, 800) }
    private var contentWidth: CGFloat { panelWidth - 64 }
    private var cellWidth: CGFloat { contentWidth / CGFloat(state.folderGrid.columns) }
    private var cellHeight: CGFloat { 118 }
    private var gridHeight: CGFloat { cellHeight * CGFloat(state.folderGrid.rows) }

    var body: some View {
        VStack(spacing: 12) {
            header
            pager
            if state.folderPageCount > 1 {
                FolderPageDots(state: state)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 44, y: 18)
        )
        .frame(width: panelWidth)
        .position(x: container.width / 2, y: container.height * 0.46)
        .background(panelFrameReporter)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if state.renamingFolder {
            HStack(spacing: 2) {
                Text(state.renameBuffer)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(caretVisible ? 0.9 : 0))
                    .frame(width: 2, height: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.10))
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    caretVisible = false
                }
            }
        } else {
            Text(folder.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(hoveringName ? 1 : 0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(hoveringName ? 0.08 : 0))
                )
                .onHover { hoveringName = $0 }
                .onTapGesture { state.beginRename() }
                .help("Click to rename")
        }
    }

    // MARK: - Pager

    private var pager: some View {
        let pages = state.folderGrid.paginate(state.folderDisplayCells)
        return HStack(spacing: 0) {
            ForEach(pages.indices, id: \.self) { pageIndex in
                folderPage(pages[pageIndex], pageIndex: pageIndex)
                    .frame(width: contentWidth, height: gridHeight)
            }
        }
        .offset(x: -CGFloat(state.folderPage) * contentWidth)
        .frame(width: contentWidth, height: gridHeight, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard drag.session == nil else { return }
                    if value.translation.width < -40 { state.folderFlip(1) }
                    else if value.translation.width > 40 { state.folderFlip(-1) }
                }
        )
        .background(gridFrameReporter)
    }

    private func folderPage(_ cells: [DisplayCell], pageIndex: Int) -> some View {
        let pageStart = pageIndex * state.folderGrid.perPage
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: state.folderGrid.columns),
            spacing: 0
        ) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { position, cell in
                folderCell(cell, globalIndex: pageStart + position)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func folderCell(_ cell: DisplayCell, globalIndex: Int) -> some View {
        switch cell {
        case .gap:
            Color.clear.frame(width: cellWidth, height: cellHeight)
        case .node(let node):
            if let appID = node.appID, let item = state.appsByID[appID] {
                AppIconCell(
                    item: item,
                    iconSize: 64,
                    width: cellWidth,
                    height: cellHeight,
                    isSelected: state.folderSelection == globalIndex,
                    interactive: !drag.isActive,
                    action: {
                        if !state.isPageDragging { state.launch(item) }
                    },
                    reveal: { state.reveal(item) },
                    onRemoveFromFolder: { state.removeFromOpenFolder(appID) }
                )
                .modifier(NodeDragModifier(
                    drag: drag,
                    node: .app(appID),
                    source: .folder(folder.id),
                    iconSize: 64,
                    enabled: true
                ))
            }
        }
    }

    // MARK: - Geometry reporting for the drag system

    private var panelFrameReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { drag.folderPanelFrame = geo.frame(in: .named("overlay")) }
                .onChange(of: geo.frame(in: .named("overlay"))) { _, frame in
                    drag.folderPanelFrame = frame
                }
        }
    }

    private var gridFrameReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { reportGrid(geo) }
                .onChange(of: geo.frame(in: .named("overlay"))) { _, _ in reportGrid(geo) }
        }
    }

    private func reportGrid(_ geo: GeometryProxy) {
        drag.folderGridFrame = geo.frame(in: .named("overlay"))
        drag.folderMetrics = PagerMetrics(
            columns: state.folderGrid.columns,
            rows: state.folderGrid.rows,
            pageWidth: contentWidth,
            pageHeight: gridHeight,
            horizontalInset: 0
        )
    }
}

private struct FolderPageDots: View {
    @ObservedObject var state: GridState

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<state.folderPageCount, id: \.self) { page in
                Circle()
                    .fill(.white.opacity(page == state.folderPage ? 0.95 : 0.4))
                    .frame(width: 6, height: 6)
                    .contentShape(Circle().inset(by: -6))
                    .onTapGesture {
                        withAnimation(Anim.page) { state.folderPage = page }
                    }
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.2), value: state.folderPage)
    }
}
