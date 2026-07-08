import AppKit
import SwiftUI
import CosmodromeCore

/// One icon + label. Hover lifts it a touch, pressing dims it like the Dock,
/// keyboard selection gets Launchpad's snug glass plate around icon + label.
struct AppIconCell: View {
    let item: AppItem
    let iconSize: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let action: () -> Void
    let reveal: () -> Void

    @State private var icon: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                iconView
                    .frame(width: iconSize, height: iconSize)

                Text(item.name)
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
        .buttonStyle(AppIconButtonStyle(hovering: hovering))
        .frame(width: width, height: height)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { action() }
            Button("Show in Finder") { reveal() }
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

    private var iconView: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
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
