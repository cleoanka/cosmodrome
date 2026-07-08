import AppKit
import CosmodromeCore

/// Loads app icons off the main thread, once, and keeps them warm.
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "io.github.cleoanka.Cosmodrome.icons",
                                      qos: .userInitiated,
                                      attributes: .concurrent)

    private init() {
        cache.countLimit = 1024
    }

    func cached(for item: AppItem) -> NSImage? {
        cache.object(forKey: item.id as NSString)
    }

    func load(for item: AppItem, completion: @escaping @MainActor (NSImage) -> Void) {
        if let hit = cached(for: item) {
            Task { @MainActor in completion(hit) }
            return
        }
        queue.async { [cache] in
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            icon.size = NSSize(width: 256, height: 256)
            cache.setObject(icon, forKey: item.id as NSString)
            Task { @MainActor in completion(icon) }
        }
    }
}
