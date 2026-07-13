import Foundation

/// A user-arranged folder of apps.
public struct AppFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// AppItem.ids (bundle paths), in user order.
    public var appIDs: [String]

    public init(id: UUID = UUID(), name: String, appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

/// One slot on the grid: a loose app or a folder.
public enum LayoutNode: Codable, Hashable, Identifiable, Sendable {
    case app(String)
    case folder(AppFolder)

    public var id: String {
        switch self {
        case .app(let appID): return "app:\(appID)"
        case .folder(let folder): return "folder:\(folder.id.uuidString)"
        }
    }

    public var appID: String? {
        if case .app(let appID) = self { return appID }
        return nil
    }

    public var folder: AppFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

/// The persisted arrangement of the whole grid, in user order.
public struct AppLayout: Codable, Hashable, Sendable {
    public var nodes: [LayoutNode]

    public init(nodes: [LayoutNode] = []) {
        self.nodes = nodes
    }

    /// Every app the layout knows about, loose or foldered.
    public var allAppIDs: Set<String> {
        var ids = Set<String>()
        for node in nodes {
            switch node {
            case .app(let appID): ids.insert(appID)
            case .folder(let folder): ids.formUnion(folder.appIDs)
            }
        }
        return ids
    }

    public func indexOfFolder(_ folderID: UUID) -> Int? {
        nodes.firstIndex { $0.folder?.id == folderID }
    }
}
