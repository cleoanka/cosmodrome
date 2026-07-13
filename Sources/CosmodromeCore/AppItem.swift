import Foundation

/// One launchable application found on disk.
public struct AppItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    /// Raw LSApplicationCategoryType (e.g. "public.app-category.games").
    public let category: String?

    public var id: String { url.path }

    public init(url: URL, name: String, bundleID: String?, category: String? = nil) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.category = category
    }
}
