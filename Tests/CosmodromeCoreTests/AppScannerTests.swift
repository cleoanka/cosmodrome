import XCTest
@testable import CosmodromeCore

final class AppScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CosmodromeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeApp(_ relativePath: String, root: String = "root") throws {
        let url = tempRoot
            .appendingPathComponent(root, isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func root(_ name: String = "root") -> URL {
        tempRoot.appendingPathComponent(name, isDirectory: true)
    }

    func testFindsAppsAndSortsByName() throws {
        try makeApp("Zebra.app")
        try makeApp("Alpha.app")
        let items = AppScanner.scan(roots: [root()])
        XCTAssertEqual(items.map(\.name), ["Alpha", "Zebra"])
    }

    func testFindsAppsInSubfolders() throws {
        try makeApp("Utilities/Terminal.app")
        let items = AppScanner.scan(roots: [root()])
        XCTAssertEqual(items.map(\.name), ["Terminal"])
    }

    func testDoesNotDescendIntoAppBundles() throws {
        try makeApp("Outer.app/Contents/Helpers/Inner.app")
        let items = AppScanner.scan(roots: [root()])
        XCTAssertEqual(items.map(\.name), ["Outer"])
    }

    func testDeduplicatesAcrossRoots() throws {
        try makeApp("Safari.app", root: "a")
        try makeApp("Safari.app", root: "b")
        let items = AppScanner.scan(roots: [root("a"), root("b")])
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].url.path.contains("/a/"))
    }

    func testSkipsHiddenAndNonAppEntries() throws {
        try makeApp(".Hidden.app")
        try makeApp("NotAnApp")
        try makeApp("Real.app")
        let items = AppScanner.scan(roots: [root()])
        XCTAssertEqual(items.map(\.name), ["Real"])
    }

    func testMissingRootIsIgnored() {
        let items = AppScanner.scan(roots: [tempRoot.appendingPathComponent("nope")])
        XCTAssertTrue(items.isEmpty)
    }

    func testTopLevelCopyBeatsSubfolderCopyWithinRoot() throws {
        // readdir order is nondeterministic; the shallow (canonical) copy must
        // win regardless of which one the enumerator yields first.
        try makeApp("Old Versions/Chrome.app")
        try makeApp("Chrome.app")
        let items = AppScanner.scan(roots: [root()])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url.deletingLastPathComponent().lastPathComponent, "root")
    }

    func testFindsSymlinkedApps() throws {
        try makeApp("Real.app", root: "elsewhere")
        try FileManager.default.createDirectory(at: root(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root().appendingPathComponent("Linked.app"),
            withDestinationURL: root("elsewhere").appendingPathComponent("Real.app")
        )
        let items = AppScanner.scan(roots: [root()])
        XCTAssertEqual(items.map(\.name), ["Linked"])
    }

    func testIgnoresPlainFileNamedDotApp() throws {
        try FileManager.default.createDirectory(at: root(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root().appendingPathComponent("Fake.app").path, contents: Data())
        let items = AppScanner.scan(roots: [root()])
        XCTAssertTrue(items.isEmpty)
    }
}
