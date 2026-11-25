import Foundation

/// Reads the persisted layout without ever destroying the user's file.
public enum LayoutFile {
    public enum LoadResult: Equatable {
        /// No file yet (first launch).
        case missing
        case loaded(AppLayout)
        /// The file existed but could not be read or decoded (hand edit, a
        /// newer version's format); it was moved to this URL untouched.
        case movedAside(URL)
    }

    /// Load `url`. An unreadable file is moved aside to
    /// `<name>.corrupt-<UTC timestamp>` before returning, so the fresh layout
    /// saved next can't overwrite the user's arrangement. Throws only when
    /// that move fails — the caller must then not save over the file.
    public static func load(from url: URL, now: Date = Date()) throws -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        if let data = try? Data(contentsOf: url),
           let layout = try? JSONDecoder().decode(AppLayout.self, from: data) {
            return .loaded(layout)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(formatter.string(from: now))")
        try fileManager.moveItem(at: url, to: backup)
        return .movedAside(backup)
    }
}
