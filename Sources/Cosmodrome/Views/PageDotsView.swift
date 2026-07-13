import SwiftUI

/// Clickable page dots with a live active indicator: the bright dot glides
/// between positions, tracking the fingers mid-swipe.
struct PageDotsView: View {
    @ObservedObject var state: GridState
    @ObservedObject var drive: PagerDrive

    private let dotSize: CGFloat = 6
    private let spacing: CGFloat = 10

    var body: some View {
        let count = state.pageCount
        ZStack {
            HStack(spacing: spacing) {
                if count > 1 {
                    ForEach(0..<count, id: \.self) { page in
                        DotView(isActive: false) {
                            state.goToPage(page)
                        }
                    }
                }
            }
            if count > 1 {
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: dotSize, height: dotSize)
                    .offset(x: activeOffset(count: count))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 16)
    }

    private func activeOffset(count: Int) -> CGFloat {
        let width = max(drive.pageWidth, 1)
        let raw = CGFloat(state.currentPage) - drive.liveOffset / width
        let progress = min(max(raw, 0), CGFloat(count - 1))
        let step = dotSize + spacing
        return (progress - CGFloat(count - 1) / 2) * step
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
