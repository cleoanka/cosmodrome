import AppKit

/// Finds every launchable .app bundle in the places Launchpad used to look.
public enum AppScanner {
    /// Safari lives in the cryptex on modern macOS, not /Applications.
    public static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
        ]
    }

    /// Maximum folder depth below each root that is searched for bundles,
    /// e.g. /Applications/Utilities/X.app (depth 2) is found, deeper nesting is not.
    private static let maxDepth = 3

    public static func scan(
        roots: [URL] = defaultRoots,
        excludingBundleIDs excluded: Set<String> = []
    ) -> [AppItem] {
        let fm = FileManager.default
        // Duplicates: earlier roots always win; within a root the shallowest
        // copy wins (the enumerator's readdir order is nondeterministic, so
        // "first hit" could otherwise let Old Versions/Foo.app shadow Foo.app).
        var best: [String: (root: Int, level: Int, index: Int)] = [:]
        var items: [AppItem] = []

        for (rootIndex, root) in roots.enumerated() {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else {
                    if enumerator.level >= maxDepth { enumerator.skipDescendants() }
                    continue
                }
                enumerator.skipDescendants()
                let level = enumerator.level

                // Apps installed as symlinks still count; a plain file named
                // Something.app does not.
                let resolved = url.resolvingSymlinksInPath()
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                let bundle = Bundle(url: resolved)
                let bundleID = bundle?.bundleIdentifier
                if let bundleID, excluded.contains(bundleID) { continue }
                let category = bundle?.infoDictionary?["LSApplicationCategoryType"] as? String

                let dedupeKey = bundleID ?? url.lastPathComponent.lowercased()
                let item = AppItem(
                    url: url,
                    name: fm.displayName(atPath: url.path),
                    bundleID: bundleID,
                    category: category
                )

                if let previous = best[dedupeKey] {
                    if previous.root == rootIndex && level < previous.level {
                        items[previous.index] = item
                        best[dedupeKey] = (rootIndex, level, previous.index)
                    }
                } else {
                    best[dedupeKey] = (rootIndex, level, items.count)
                    items.append(item)
                }
            }
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
