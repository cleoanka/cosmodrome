import SwiftUI

/// Full-screen root: blurred wallpaper behind, search + paged grid + dots in
/// front. The phase drives Launchpad's signature zoom-and-materialize.
struct OverlayRootView: View {
    @ObservedObject var state: GridState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BackgroundView(wallpaper: state.wallpaper, dim: state.dimAmount)
                    .opacity(state.phase == .shown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { state.requestHide() }

                content(in: geo.size)
                    .scaleEffect(contentScale)
                    .blur(radius: contentBlur)
                    .opacity(state.phase == .shown ? 1 : 0)
            }
        }
        .ignoresSafeArea()
    }

    private var contentScale: CGFloat {
        switch state.phase {
        case .hidden: return 1.12
        case .shown: return 1.0
        case .launching: return 1.3
        }
    }

    private var contentBlur: CGFloat {
        state.phase == .shown ? 0 : 14
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            SearchBarView(state: state)
                .padding(.top, 52)

            if state.visibleApps.isEmpty && !state.query.isEmpty {
                Spacer()
                noResults
                Spacer()
                Spacer()
            } else {
                PagerView(state: state)
                    .padding(.top, 12)
            }

            PageDotsView(state: state)
                .padding(.top, 12)
                .padding(.bottom, 40)
        }
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Text("No Results")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("“\(state.query)” didn’t match any app")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}
