import SwiftUI

/// Clickable page indicator dots, hidden while a single page fits everything.
struct PageDotsView: View {
    @ObservedObject var state: GridState

    var body: some View {
        HStack(spacing: 10) {
            if state.pageCount > 1 {
                ForEach(0..<state.pageCount, id: \.self) { page in
                    DotView(isActive: page == state.currentPage) {
                        state.goToPage(page)
                    }
                }
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.2), value: state.currentPage)
    }
}

private struct DotView: View {
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Circle()
            .fill(.white.opacity(isActive ? 0.95 : 0.4))
            .frame(width: 6, height: 6)
            .scaleEffect(hovering ? 1.35 : 1)
            .contentShape(Circle().inset(by: -8))
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}
