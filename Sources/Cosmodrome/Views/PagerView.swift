import SwiftUI
import CosmodromeCore

/// Horizontally paged grid with live drag, rubber-banding at the ends and a
/// spring snap — the hand-feel of the original.
struct PagerView: View {
    @ObservedObject var state: GridState

    /// Local so per-pointer-event updates invalidate only this view, not
    /// every GridState observer.
    @State private var dragX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let pages = state.pages

            HStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    PageGridView(state: state, items: page, pageIndex: index, size: geo.size)
                        .frame(width: width, height: geo.size.height)
                }
            }
            .offset(x: -CGFloat(state.currentPage) * width + rubberBanded(dragX, width: width))
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(width: width))
        }
    }

    private func rubberBanded(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let overscrollingStart = state.currentPage == 0 && x > 0
        let overscrollingEnd = state.currentPage == state.pageCount - 1 && x < 0
        return (overscrollingStart || overscrollingEnd) ? x / 3 : x
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                state.isPageDragging = true
                dragX = value.translation.width
            }
            .onEnded { value in
                let travelled = value.translation.width
                let predicted = value.predictedEndTranslation.width
                var target = state.currentPage
                if travelled < -width * 0.12 || predicted < -width * 0.4 {
                    target += 1
                } else if travelled > width * 0.12 || predicted > width * 0.4 {
                    target -= 1
                }
                target = min(max(target, 0), state.pageCount - 1)
                if target != state.currentPage { state.selection = nil }
                withAnimation(Anim.page) {
                    state.currentPage = target
                    dragX = 0
                }
                // The same mouse-up that ends the drag also fires the button
                // it started on — and the button action runs after onEnded,
                // so the flag must clear asynchronously.
                DispatchQueue.main.async { state.isPageDragging = false }
            }
    }
}

/// One page: a fixed 7×5 lattice of evenly spaced cells.
struct PageGridView: View {
    @ObservedObject var state: GridState
    let items: [AppItem]
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
            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                AppIconCell(
                    item: item,
                    iconSize: iconSize,
                    width: cellWidth,
                    height: cellHeight,
                    isSelected: state.selection == pageStart + position,
                    action: {
                        if !state.isPageDragging { state.launch(item) }
                    },
                    reveal: { state.reveal(item) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { state.requestHide() }
    }
}
