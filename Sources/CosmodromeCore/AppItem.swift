import Foundation

/// One launchable application found on disk.
public struct AppItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String?

    public var id: String { url.path }

    public init(url: URL, name: String, bundleID: String?) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
    }
}
