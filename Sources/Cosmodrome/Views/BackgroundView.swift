import AppKit
import SwiftUI

/// The wallpaper, pre-blurred by WallpaperProvider, with a dimming veil.
/// Falls back to an opaque deep gradient when the wallpaper can't be read
/// (video wallpapers, odd configurations) — never a see-through pane.
struct BackgroundView: View {
    let wallpaper: NSImage?
    let dim: Double

    var body: some View {
        ZStack {
            if let wallpaper {
                GeometryReader { geo in
                    Image(nsImage: wallpaper)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.15, blue: 0.24),
                        Color(red: 0.05, green: 0.05, blue: 0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            Color.black.opacity(dim)
        }
    }
}
