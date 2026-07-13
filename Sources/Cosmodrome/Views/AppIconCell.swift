import AppKit
import SwiftUI
import CosmodromeCore

/// Async-loading app icon image, shared by grid cells, folder tiles and the
/// drag ghost.
struct AppIconImage: View {
    let item: AppItem
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: item.id) {
            icon = IconCache.shared.cached(for: item)
            if icon == nil {
                IconCache.shared.load(for: item) { loaded in
                    withAnimation(.easeOut(duration: 0.18)) { icon = loaded }
                }
            }
        }
    }
}

/// One icon + label. Hover lifts it a touch, pressing dims it like the Dock,
/// keyboard selection gets Launchpad's snug glass plate around icon + label.
/// When a dragged app hovers its center, it swells: "drop to make a folder".
struct AppIconCell: View {
    let item: AppItem
    let iconSize: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    var isCombineTarget: Bool = false
    var interactive: Bool = true
    var labelSize: CGFloat = 13
    let action: () -> Void
    let reveal: () -> Void
    var onRemoveFromFolder: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                AppIconImage(item: item)
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(isCombineTarget ? 1.18 : 1)
                    .animation(Anim.reflow, value: isCombineTarget)

                Text(item.name)
                    .font(.system(size: labelSize))
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
            Button("Show in Finder") { reveal() }
            if let onRemoveFromFolder {
                Divider()
                Button("Remove from Folder") { onRemoveFromFolder() }
            }
        }
    }

    @ViewBuilder
    private var selectionPlate: some View {
        if isSelected || isCombineTarget {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(isCombineTarget ? 0.20 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

struct AppIconButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : (hovering ? 1.05 : 1))
            .brightness(configuration.isPressed ? -0.18 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
    }
}

/// Picks up grid nodes: a 5pt drag lifts the icon into the drag layer.
/// Taps still reach the button underneath (the gesture fails without motion).
struct NodeDragModifier: ViewModifier {
    let drag: DragCoordinator
    let node: LayoutNode
    let source: LayoutEngine.DragSource
    let iconSize: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        content.highPriorityGesture(gesture, including: enabled ? .all : .subviews)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("overlay"))
            .onChanged { value in
                if drag.session == nil {
                    drag.begin(node: node, source: source, iconSize: iconSize, at: value.location)
                } else {
                    drag.update(to: value.location)
                }
            }
            .onEnded { value in
                drag.end(at: value.location)
            }
    }
}
