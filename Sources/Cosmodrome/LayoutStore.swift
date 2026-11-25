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

    /// nil = nothing usable on disk (a fresh layout may be saved). Throws when
    /// an unreadable file could not be moved aside: don't save over it.
    static func load() throws -> AppLayout? {
        switch try LayoutFile.load(from: fileURL) {
        case .missing:
            return nil
        case .loaded(let layout):
            return layout
        case .movedAside(let backup):
            NSLog("Cosmodrome: unreadable layout moved aside to %@", backup.lastPathComponent)
            return nil
        }
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
