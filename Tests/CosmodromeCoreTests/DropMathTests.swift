import XCTest
@testable import CosmodromeCore

final class DropMathTests: XCTestCase {
    // 7×5 grid on a 1000×500 pager, 110pt insets → 111.43pt cells, 100pt rows.
    let metrics = PagerMetrics(columns: 7, rows: 5, pageWidth: 1000, pageHeight: 500, horizontalInset: 110)

    func testEdgesFlip() {
        XCTAssertEqual(DropMath.hitTest(CGPoint(x: 10, y: 250), metrics: metrics, currentPage: 0, totalItems: 70), .flipLeft)
        XCTAssertEqual(DropMath.hitTest(CGPoint(x: 990, y: 250), metrics: metrics, currentPage: 0, totalItems: 70), .flipRight)
    }

    func testCenterOfFirstCell() {
        let point = CGPoint(x: 110 + 55, y: 50) // middle of column 0, row 0
        XCTAssertEqual(
            DropMath.hitTest(point, metrics: metrics, currentPage: 0, totalItems: 70),
            .cell(index: 0, zone: .center)
        )
    }

    func testLeadingAndTrailingZones() {
        let cellW = metrics.cellWidth
        let leading = CGPoint(x: 110 + cellW + cellW * 0.1, y: 50)   // col 1, left band
        let trailing = CGPoint(x: 110 + cellW + cellW * 0.9, y: 50)  // col 1, right band
        XCTAssertEqual(DropMath.hitTest(leading, metrics: metrics, currentPage: 0, totalItems: 70), .cell(index: 1, zone: .leading))
        XCTAssertEqual(DropMath.hitTest(trailing, metrics: metrics, currentPage: 0, totalItems: 70), .cell(index: 1, zone: .trailing))
    }

    func testRowAndPageOffsets() {
        let point = CGPoint(x: 110 + metrics.cellWidth * 2.5, y: 150) // col 2, row 1
        XCTAssertEqual(
            DropMath.hitTest(point, metrics: metrics, currentPage: 1, totalItems: 80),
            .cell(index: 35 + 7 + 2, zone: .center)
        )
    }

    func testBeyondLastItemAppends() {
        let point = CGPoint(x: 500, y: 450) // bottom middle, page 0 with 3 items
        XCTAssertEqual(
            DropMath.hitTest(point, metrics: metrics, currentPage: 0, totalItems: 3),
            .cell(index: 3, zone: .leading)
        )
    }

    func testInsertionIndexFromZones() {
        XCTAssertEqual(DropMath.insertionIndex(for: .cell(index: 4, zone: .leading), totalItems: 10), 4)
        XCTAssertEqual(DropMath.insertionIndex(for: .cell(index: 4, zone: .center), totalItems: 10), 4)
        XCTAssertEqual(DropMath.insertionIndex(for: .cell(index: 4, zone: .trailing), totalItems: 10), 5)
        XCTAssertEqual(DropMath.insertionIndex(for: .cell(index: 10, zone: .leading), totalItems: 10), 10)
        XCTAssertNil(DropMath.insertionIndex(for: .flipLeft, totalItems: 10))
    }

    func testReducedIndexMapping() {
        // Displayed [A, GAP, B, C]: gap at 1.
        XCTAssertEqual(DropMath.reducedIndex(fromDisplayed: 0, gapIndex: 1), 0)
        XCTAssertEqual(DropMath.reducedIndex(fromDisplayed: 1, gapIndex: 1), 1)
        XCTAssertEqual(DropMath.reducedIndex(fromDisplayed: 2, gapIndex: 1), 1)
        XCTAssertEqual(DropMath.reducedIndex(fromDisplayed: 3, gapIndex: 1), 2)
        XCTAssertEqual(DropMath.reducedIndex(fromDisplayed: 3, gapIndex: nil), 3)
    }

    func testCategoryNames() {
        XCTAssertEqual(CategoryNames.displayName(for: "public.app-category.developer-tools"), "Developer Tools")
        XCTAssertEqual(CategoryNames.displayName(for: "public.app-category.action-games"), "Games")
        XCTAssertEqual(CategoryNames.displayName(for: "public.app-category.games"), "Games")
        XCTAssertEqual(CategoryNames.displayName(for: "public.app-category.social-networking"), "Social")
        XCTAssertEqual(CategoryNames.displayName(for: "public.app-category.some-new-thing"), "Some New Thing")
        XCTAssertNil(CategoryNames.displayName(for: nil))
        XCTAssertNil(CategoryNames.displayName(for: ""))
    }
}
