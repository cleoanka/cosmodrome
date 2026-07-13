import SwiftUI
import CosmodromeCore

/// The lifted icon riding the cursor. Position updates flow through the
/// separate DragGhost object so only this small layer re-renders per event.
struct DragGhostView: View {
    let state: GridState // plain reference — only for icon lookups
    @ObservedObject var drag: DragCoordinator

    var body: some View {
        ZStack {
            if let session = drag.session {
                GhostBody(session: session, state: state, ghost: drag.ghost)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GhostBody: View {
    let session: DragCoordinator.Session
    let state: GridState
    @ObservedObject var ghost: DragGhost

    var body: some View {
        content
            .frame(width: session.iconSize, height: session.iconSize)
            .scaleEffect(1.15)
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            .position(ghost.location)
    }

    @ViewBuilder
    private var content: some View {
        switch session.node {
        case .app(let appID):
            if let item = state.appsByID[appID] {
                AppIconImage(item: item)
            }
        case .folder(let folder):
            FolderTileView(
                apps: folder.appIDs.prefix(9).compactMap { state.appsByID[$0] },
                size: session.iconSize
            )
        }
    }
}
