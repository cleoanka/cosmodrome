import Foundation
import CosmodromeCore

/// The user's arrangement, one JSON file in Application Support.
enum LayoutStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Cosmodrome", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    static func load() -> AppLayout? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppLayout.self, from: data)
    }

    static func save(_ layout: AppLayout) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(layout).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Cosmodrome: layout save failed: %@", error.localizedDescription)
        }
    }
}
