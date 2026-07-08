import AppKit
import CoreImage

/// CIContext is expensive to create and thread-safe to use; one for the app.
private let wallpaperRenderContext = CIContext(options: [.useSoftwareRenderer: false])

/// Renders the user's wallpaper the way Launchpad showed it: blurred,
/// slightly richer in color, ready to be dimmed by the overlay.
///
/// Decoding a 6K HEIC and blurring it takes a few hundred ms, so the miss
/// path runs off the main thread: `cached` is an instant lookup for show(),
/// `prepare` fills the cache asynchronously (pre-warmed at launch).
@MainActor
enum WallpaperProvider {
    private static var cache: [String: NSImage] = [:]

    static func cached(for screen: NSScreen) -> NSImage? {
        guard let key = resolvedKey(for: screen) else { return nil }
        return cache[key]
    }

    static func prepare(for screen: NSScreen, completion: (@MainActor (NSImage?) -> Void)? = nil) {
        guard let key = resolvedKey(for: screen) else {
            NSLog("Cosmodrome wallpaper: no usable desktopImageURL")
            completion?(nil)
            return
        }
        if let hit = cache[key] {
            completion?(hit)
            return
        }
        let imageURL = URL(fileURLWithPath: key)
        Task.detached(priority: .userInitiated) {
            let rendered = renderBlur(from: imageURL)
            await MainActor.run {
                var image: NSImage?
                if let rendered {
                    image = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
                    if cache.count > 8 { cache.removeAll() }
                    cache[key] = image
                }
                completion?(image)
            }
        }
    }

    private static func resolvedKey(for screen: NSScreen) -> String? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return resolveImageURL(url)?.path
    }

    /// Dynamic wallpapers can hand back a folder; pick any frame from it —
    /// after a 42pt gaussian nobody can tell dawn from dusk.
    private static func resolveImageURL(_ url: URL) -> URL? {
        guard url.hasDirectoryPath else { return url }
        let imageExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tiff", "tif"]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private nonisolated static func renderBlur(from url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSLog("Cosmodrome wallpaper: image load failed for %@", url.path)
            return nil
        }
        var ci = CIImage(cgImage: cg)

        // Blur radius scales with resolution, so downsample first: same look,
        // fraction of the work, and the result is stretched fullscreen anyway.
        let targetWidth: CGFloat = 1600
        let scale = min(1, targetWidth / max(ci.extent.width, 1))
        if scale < 1 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let extent = ci.extent

        ci = ci.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 42])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.35,
                kCIInputBrightnessKey: -0.02,
            ])
            .cropped(to: extent)

        let rendered = wallpaperRenderContext.createCGImage(ci, from: extent)
        if rendered == nil {
            NSLog("Cosmodrome wallpaper: blur render failed for %@", url.path)
        }
        return rendered
    }
}
