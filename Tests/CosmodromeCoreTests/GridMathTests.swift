import XCTest
@testable import CosmodromeCore

final class GridMathTests: XCTestCase {
    let grid = GridMath(columns: 7, rows: 5) // 35 per page

    func testPageCount() {
        XCTAssertEqual(grid.pageCount(for: 0), 1)
        XCTAssertEqual(grid.pageCount(for: 1), 1)
        XCTAssertEqual(grid.pageCount(for: 35), 1)
        XCTAssertEqual(grid.pageCount(for: 36), 2)
        XCTAssertEqual(grid.pageCount(for: 80), 3)
    }

    func testPaginate() {
        let pages = grid.paginate(Array(0..<80))
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].count, 35)
        XCTAssertEqual(pages[2].count, 10)
        XCTAssertEqual(pages[1].first, 35)
        XCTAssertEqual(grid.paginate([Int]()).count, 1)
        XCTAssertTrue(grid.paginate([Int]())[0].isEmpty)
    }

    func testHorizontalMovementCrossesPages() {
        // Index 34 is the last cell of page 0; right lands on page 1.
        XCTAssertEqual(grid.move(from: 34, direction: .right, total: 80), 35)
        XCTAssertEqual(grid.move(from: 35, direction: .left, total: 80), 34)
        // Hard edges stay put.
        XCTAssertEqual(grid.move(from: 0, direction: .left, total: 80), 0)
        XCTAssertEqual(grid.move(from: 79, direction: .right, total: 80), 79)
    }

    func testVerticalMovementWithinPage() {
        XCTAssertEqual(grid.move(from: 3, direction: .down, total: 80), 10)
        XCTAssertEqual(grid.move(from: 10, direction: .up, total: 80), 3)
    }

    func testDownFromBottomRowHopsToNextPageSameColumn() {
        // Index 31 = page 0, bottom row, column 3 → page 1 top row column 3 = 38.
        XCTAssertEqual(grid.move(from: 31, direction: .down, total: 80), 38)
        // And back up again.
        XCTAssertEqual(grid.move(from: 38, direction: .up, total: 80), 31)
    }

    func testDownIntoMissingCellStaysPut() {
        // Total 40: page 1 has indices 35…39 (top row only).
        // From 38 (page 1, row 0, col 3), down would land on an empty cell.
        XCTAssertEqual(grid.move(from: 38, direction: .down, total: 40), 38)
    }

    func testDownFromBottomRowClampsOnPartialNextPage() {
        // Total 37: page 1 holds 35, 36. From 34 (bottom row, col 6),
        // target 35+6=41 doesn't exist → clamp to the last app.
        XCTAssertEqual(grid.move(from: 34, direction: .down, total: 37), 36)
    }

    func testUpFromTopRowOfFirstPageStaysPut() {
        XCTAssertEqual(grid.move(from: 3, direction: .up, total: 80), 3)
    }

    func testFirstIndexOnPage() {
        XCTAssertEqual(grid.firstIndex(onPage: 0, total: 80), 0)
        XCTAssertEqual(grid.firstIndex(onPage: 2, total: 80), 70)
        XCTAssertEqual(grid.firstIndex(onPage: 5, total: 80), 79) // clamped
        XCTAssertEqual(grid.firstIndex(onPage: 0, total: 0), 0)
    }
}
