import XCTest
@testable import CosmodromeCore

final class LayoutFileTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("layout.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFile() throws {
        XCTAssertEqual(try LayoutFile.load(from: file), .missing)
    }

    func testLoadsValidLayout() throws {
        let layout = AppLayout(nodes: [
            .app("/Applications/A.app"),
            .folder(AppFolder(name: "F", appIDs: ["/Applications/B.app", "/Applications/C.app"])),
        ])
        try JSONEncoder().encode(layout).write(to: file)
        XCTAssertEqual(try LayoutFile.load(from: file), .loaded(layout))
    }

    func testSyntaxErrorIsMovedAside() throws {
        // Hand edit with a missing comma between nodes.
        try Data(#"{"nodes": [{"app": {"_0": "/A.app"}} {"app": {"_0": "/B.app"}}]}"#.utf8).write(to: file)
        guard case .movedAside(let backup) = try LayoutFile.load(from: file) else {
            return XCTFail("broken JSON must be moved aside")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testUndecodableFileIsMovedAsideUntouched() throws {
        // Rolled back from a version with a node type this build doesn't know.
        let original = Data(#"{"nodes": [{"app": {"_0": "/Applications/A.app"}}, {"widget": {"_0": "w"}}]}"#.utf8)
        try original.write(to: file)
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00:00 UTC

        let result = try LayoutFile.load(from: file, now: now)

        let backup = directory.appendingPathComponent("layout.json.corrupt-20270115-080000")
        XCTAssertEqual(result, .movedAside(backup))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: backup), original)
        // Next launch sees no file and starts fresh; the backup stays put.
        XCTAssertEqual(try LayoutFile.load(from: file), .missing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testThrowsWhenBackupCannotBeMade() throws {
        try Data("garbage".utf8).write(to: file)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Occupy the backup name so the move fails: the caller must be told.
        let backup = directory.appendingPathComponent("layout.json.corrupt-20270115-080000")
        try Data("older backup".utf8).write(to: backup)

        XCTAssertThrowsError(try LayoutFile.load(from: file, now: now))
        XCTAssertEqual(try Data(contentsOf: file), Data("garbage".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("older backup".utf8))
    }
}
