import XCTest
@testable import CosmodromeCore

final class LayoutEngineTests: XCTestCase {
    private func app(_ name: String, category: String? = nil) -> AppItem {
        AppItem(url: URL(fileURLWithPath: "/Applications/\(name).app"),
                name: name, bundleID: nil, category: category)
    }

    private func id(_ name: String) -> String { "/Applications/\(name).app" }

    // MARK: - Construction & reconcile

    func testInitialLayoutIsAlphabetical() {
        let layout = LayoutEngine.initialLayout(from: [app("Zebra"), app("Alpha")])
        XCTAssertEqual(layout.nodes.map(\.appID), [id("Alpha"), id("Zebra")])
    }

    func testReconcileDropsVanishedAndAppendsNewcomers() {
        let layout = AppLayout(nodes: [.app(id("Gone")), .app(id("Kept"))])
        let result = LayoutEngine.reconcile(layout, with: [app("Kept"), app("New")])
        XCTAssertEqual(result.nodes.map(\.appID), [id("Kept"), id("New")])
    }

    func testReconcileDissolvesStarvedFolders() {
        let folder = AppFolder(name: "F", appIDs: [id("A"), id("Gone")])
        let layout = AppLayout(nodes: [.folder(folder), .app(id("B"))])
        let result = LayoutEngine.reconcile(layout, with: [app("A"), app("B")])
        // Folder shrank to one app → dissolves in place, keeping its slot.
        XCTAssertEqual(result.nodes.map(\.appID), [id("A"), id("B")])
    }

    func testReconcileRemovesEmptyFolders() {
        let folder = AppFolder(name: "F", appIDs: [id("Gone")])
        let layout = AppLayout(nodes: [.folder(folder), .app(id("B"))])
        let result = LayoutEngine.reconcile(layout, with: [app("B")])
        XCTAssertEqual(result.nodes.map(\.appID), [id("B")])
    }

    func testReconcileDeduplicatesAcrossFolderAndGrid() {
        let folder = AppFolder(name: "F", appIDs: [id("A"), id("B")])
        let layout = AppLayout(nodes: [.folder(folder), .app(id("A"))])
        let result = LayoutEngine.reconcile(layout, with: [app("A"), app("B")])
        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.nodes[0].folder?.appIDs, [id("A"), id("B")])
    }

    // MARK: - Auto folders

    func testGroupedByCategoryMakesFoldersAndStrays() {
        let apps = [
            app("Xcode", category: "public.app-category.developer-tools"),
            app("Terminal", category: "public.app-category.developer-tools"),
            app("Chess", category: "public.app-category.board-games"),
            app("Doom", category: "public.app-category.action-games"),
            app("Mystery"),
            app("Solo", category: "public.app-category.weather"),
        ]
        let layout = LayoutEngine.groupedByCategory(apps: apps)
        let folders = layout.nodes.compactMap(\.folder)
        XCTAssertEqual(folders.map(\.name), ["Developer Tools", "Games"])
        XCTAssertEqual(folders[1].appIDs, [id("Chess"), id("Doom")]) // game subgenres merge
        // Single-member category + uncategorized stay loose, alphabetical.
        XCTAssertEqual(layout.nodes.compactMap(\.appID), [id("Mystery"), id("Solo")])
    }

    // MARK: - Drag mutations

    func testRemoveFromGridThenInsert() {
        var layout = AppLayout(nodes: [.app(id("A")), .app(id("B")), .app(id("C"))])
        layout = LayoutEngine.removing(.app(id("A")), source: .grid, from: layout)
        XCTAssertEqual(layout.nodes.map(\.appID), [id("B"), id("C")])
        layout = LayoutEngine.inserting(.app(id("A")), at: 2, in: layout)
        XCTAssertEqual(layout.nodes.map(\.appID), [id("B"), id("C"), id("A")])
    }

    func testRemoveFromFolderDissolvesPair() {
        let folder = AppFolder(name: "F", appIDs: [id("A"), id("B")])
        var layout = AppLayout(nodes: [.app(id("X")), .folder(folder)])
        layout = LayoutEngine.removing(.app(id("A")), source: .folder(folder.id), from: layout)
        // B survives alone → folder dissolves into B at the same slot.
        XCTAssertEqual(layout.nodes.map(\.appID), [id("X"), id("B")])
    }

    func testCombineCreatesFolderInTargetSlot() {
        var layout = AppLayout(nodes: [.app(id("A")), .app(id("B")), .app(id("C"))])
        layout = LayoutEngine.removing(.app(id("C")), source: .grid, from: layout)
        layout = LayoutEngine.combining(appID: id("C"), ontoAppID: id("A"), name: "Pair", in: layout)
        XCTAssertEqual(layout.nodes.count, 2)
        XCTAssertEqual(layout.nodes[0].folder?.appIDs, [id("A"), id("C")])
        XCTAssertEqual(layout.nodes[0].folder?.name, "Pair")
        XCTAssertEqual(layout.nodes[1].appID, id("B"))
    }

    func testAddToFolderIgnoresDuplicates() {
        let folder = AppFolder(name: "F", appIDs: [id("A"), id("B")])
        var layout = AppLayout(nodes: [.folder(folder)])
        layout = LayoutEngine.adding(appID: id("C"), toFolder: folder.id, in: layout)
        layout = LayoutEngine.adding(appID: id("C"), toFolder: folder.id, in: layout)
        XCTAssertEqual(layout.nodes[0].folder?.appIDs, [id("A"), id("B"), id("C")])
    }

    func testReorderInFolder() {
        let folder = AppFolder(name: "F", appIDs: [id("A"), id("B"), id("C")])
        var layout = AppLayout(nodes: [.folder(folder)])
        layout = LayoutEngine.reorderingInFolder(folder.id, appID: id("A"), to: 2, in: layout)
        XCTAssertEqual(layout.nodes[0].folder?.appIDs, [id("B"), id("C"), id("A")])
    }

    // MARK: - Folder management

    func testRenameRejectsEmptyNames() {
        let folder = AppFolder(name: "Original", appIDs: [id("A"), id("B")])
        var layout = AppLayout(nodes: [.folder(folder)])
        layout = LayoutEngine.renaming(folder: folder.id, to: "   ", in: layout)
        XCTAssertEqual(layout.nodes[0].folder?.name, "Original")
        layout = LayoutEngine.renaming(folder: folder.id, to: " Tools ", in: layout)
        XCTAssertEqual(layout.nodes[0].folder?.name, "Tools")
    }

    func testUngroupSplicesInPlace() {
        let folder = AppFolder(name: "F", appIDs: [id("B"), id("C")])
        var layout = AppLayout(nodes: [.app(id("A")), .folder(folder), .app(id("D"))])
        layout = LayoutEngine.ungrouping(folder: folder.id, in: layout)
        XCTAssertEqual(layout.nodes.map(\.appID), [id("A"), id("B"), id("C"), id("D")])
    }

    func testSuggestedFolderName() {
        let dev = app("Xcode", category: "public.app-category.developer-tools")
        let plain = app("Mystery")
        XCTAssertEqual(LayoutEngine.suggestedFolderName(target: dev, dragged: plain), "Developer Tools")
        XCTAssertEqual(LayoutEngine.suggestedFolderName(target: plain, dragged: dev), "Developer Tools")
        XCTAssertEqual(LayoutEngine.suggestedFolderName(target: plain, dragged: plain), "New Folder")
    }
}
