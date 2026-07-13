import SwiftUI

/// Full-screen root: blurred wallpaper behind; search, paged grid and dots in
/// front; folder panel and drag ghost on top. The phase drives Launchpad's
/// signature zoom-and-materialize.
struct OverlayRootView: View {
    @ObservedObject var state: GridState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BackgroundView(wallpaper: state.wallpaper, dim: state.dimAmount)
                    .opacity(state.phase == .shown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if state.openFolderID != nil { state.closeFolder() } else { state.requestHide() }
                    }

                ZStack {
                    content(in: geo.size)
                        .blur(radius: state.openFolderID != nil ? 14 : 0)
                        .scaleEffect(state.openFolderID != nil ? 0.98 : 1)

                    FolderLayer(state: state, drag: state.drag)

                    DragGhostView(state: state, drag: state.drag)
                }
                .scaleEffect(contentScale)
                .blur(radius: contentBlur)
                .opacity(state.phase == .shown ? 1 : 0)
            }
            .coordinateSpace(name: "overlay")
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
                PagerView(state: state, drive: state.pagerDrive, drag: state.drag)
                    .padding(.top, 12)
            }

            PageDotsView(state: state, drive: state.pagerDrive)
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
