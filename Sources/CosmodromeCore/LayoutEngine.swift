import Foundation

/// Pure transformations of AppLayout. Every mutation the UI performs goes
/// through here, so the invariants live in one tested place:
///  - a folder always holds ≥ 2 apps (1 dissolves in place, 0 disappears)
///  - an app id appears at most once across the whole layout
///  - reconcile() keeps the layout in sync with what's on disk
public enum LayoutEngine {
    // MARK: - Construction & reconciliation

    public static func initialLayout(from apps: [AppItem]) -> AppLayout {
        AppLayout(nodes: sortedByName(apps).map { .app($0.id) })
    }

    /// Sync a stored layout with a fresh scan: drop vanished apps, dissolve
    /// starved folders, append newly installed apps (alphabetically) at the
    /// end — where Launchpad put them.
    public static func reconcile(_ layout: AppLayout, with apps: [AppItem]) -> AppLayout {
        let valid = Set(apps.map(\.id))
        var known = Set<String>()
        var nodes: [LayoutNode] = []

        for node in layout.nodes {
            switch node {
            case .app(let appID):
                guard valid.contains(appID), !known.contains(appID) else { continue }
                known.insert(appID)
                nodes.append(node)
            case .folder(var folder):
                folder.appIDs = folder.appIDs.filter { valid.contains($0) && !known.contains($0) }
                folder.appIDs.forEach { known.insert($0) }
                if let survivor = dissolved(folder) {
                    nodes.append(survivor)
                }
            }
        }

        let newcomers = sortedByName(apps.filter { !known.contains($0.id) })
        nodes.append(contentsOf: newcomers.map { .app($0.id) })
        return AppLayout(nodes: nodes)
    }

    // MARK: - Arranging

    /// Flatten everything back to a plain alphabetical grid.
    public static func sortedAlphabetically(apps: [AppItem]) -> AppLayout {
        initialLayout(from: apps)
    }

    /// iOS App Library-style auto folders: one folder per category with ≥ 2
    /// apps, alphabetical folders first, then the uncategorized strays.
    public static func groupedByCategory(apps: [AppItem]) -> AppLayout {
        var byCategory: [String: [AppItem]] = [:]
        var strays: [AppItem] = []
        for app in apps {
            if let category = CategoryNames.displayName(for: app.category) {
                byCategory[category, default: []].append(app)
            } else {
                strays.append(app)
            }
        }

        var nodes: [LayoutNode] = []
        for category in byCategory.keys.sorted() {
            let members = sortedByName(byCategory[category]!)
            if members.count >= 2 {
                nodes.append(.folder(AppFolder(name: category, appIDs: members.map(\.id))))
            } else {
                strays.append(contentsOf: members)
            }
        }
        nodes.append(contentsOf: sortedByName(strays).map { .app($0.id) })
        return AppLayout(nodes: nodes)
    }

    // MARK: - Drag & drop mutations

    /// Where a drag started.
    public enum DragSource: Hashable, Sendable {
        case grid
        case folder(UUID)
    }

    /// Pull the dragged node out of the layout (start of a drop commit).
    /// Folder-sourced apps leave their folder, which may dissolve in place.
    public static func removing(_ node: LayoutNode, source: DragSource, from layout: AppLayout) -> AppLayout {
        var layout = layout
        switch source {
        case .grid:
            layout.nodes.removeAll { $0.id == node.id }
        case .folder(let folderID):
            guard let appID = node.appID,
                  let index = layout.indexOfFolder(folderID),
                  var folder = layout.nodes[index].folder else { return layout }
            folder.appIDs.removeAll { $0 == appID }
            if let survivor = dissolved(folder) {
                layout.nodes[index] = survivor
            } else {
                layout.nodes.remove(at: index)
            }
        }
        return layout
    }

    /// Insert into the top-level grid at `index` (an index into the layout
    /// as it stands, i.e. after `removing` the dragged node).
    public static func inserting(_ node: LayoutNode, at index: Int, in layout: AppLayout) -> AppLayout {
        var layout = layout
        layout.nodes.insert(node, at: min(max(index, 0), layout.nodes.count))
        return layout
    }

    /// Drop an app onto another loose app: both fuse into a new folder that
    /// takes the target's slot.
    public static func combining(appID: String, ontoAppID targetID: String, name: String, in layout: AppLayout) -> AppLayout {
        var layout = layout
        guard appID != targetID,
              let targetIndex = layout.nodes.firstIndex(where: { $0.appID == targetID }) else { return layout }
        layout.nodes[targetIndex] = .folder(AppFolder(name: name, appIDs: [targetID, appID]))
        return layout
    }

    /// Drop an app onto a folder: appended at the end of the folder.
    public static func adding(appID: String, toFolder folderID: UUID, in layout: AppLayout) -> AppLayout {
        var layout = layout
        guard let index = layout.indexOfFolder(folderID),
              var folder = layout.nodes[index].folder,
              !folder.appIDs.contains(appID) else { return layout }
        folder.appIDs.append(appID)
        layout.nodes[index] = .folder(folder)
        return layout
    }

    /// Reorder inside a folder; `to` indexes the folder as it stands after
    /// removing the moved app.
    public static func reorderingInFolder(_ folderID: UUID, appID: String, to: Int, in layout: AppLayout) -> AppLayout {
        var layout = layout
        guard let index = layout.indexOfFolder(folderID),
              var folder = layout.nodes[index].folder,
              folder.appIDs.contains(appID) else { return layout }
        folder.appIDs.removeAll { $0 == appID }
        folder.appIDs.insert(appID, at: min(max(to, 0), folder.appIDs.count))
        layout.nodes[index] = .folder(folder)
        return layout
    }

    // MARK: - Folder management

    public static func renaming(folder folderID: UUID, to name: String, in layout: AppLayout) -> AppLayout {
        var layout = layout
        guard let index = layout.indexOfFolder(folderID),
              var folder = layout.nodes[index].folder else { return layout }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.name = trimmed.isEmpty ? folder.name : trimmed
        layout.nodes[index] = .folder(folder)
        return layout
    }

    /// Splice a folder's apps back into the grid at the folder's position.
    public static func ungrouping(folder folderID: UUID, in layout: AppLayout) -> AppLayout {
        var layout = layout
        guard let index = layout.indexOfFolder(folderID),
              let folder = layout.nodes[index].folder else { return layout }
        layout.nodes.replaceSubrange(index...index, with: folder.appIDs.map { LayoutNode.app($0) })
        return layout
    }

    /// Suggested name for a folder born from dropping `dragged` onto `target`
    /// — the target's category, like Launchpad.
    public static func suggestedFolderName(target: AppItem?, dragged: AppItem?) -> String {
        CategoryNames.displayName(for: target?.category)
            ?? CategoryNames.displayName(for: dragged?.category)
            ?? "New Folder"
    }

    // MARK: - Helpers

    /// nil = folder is empty and should vanish; .app = single survivor takes
    /// the folder's slot; .folder = still a real folder.
    private static func dissolved(_ folder: AppFolder) -> LayoutNode? {
        switch folder.appIDs.count {
        case 0: return nil
        case 1: return .app(folder.appIDs[0])
        default: return .folder(folder)
        }
    }

    private static func sortedByName(_ apps: [AppItem]) -> [AppItem] {
        apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
