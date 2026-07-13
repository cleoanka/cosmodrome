import Foundation

/// Geometry of a paged grid as the drag system sees it.
public struct PagerMetrics: Hashable, Sendable {
    public let columns: Int
    public let rows: Int
    public let pageWidth: CGFloat
    public let pageHeight: CGFloat
    public let horizontalInset: CGFloat

    public init(columns: Int, rows: Int, pageWidth: CGFloat, pageHeight: CGFloat, horizontalInset: CGFloat) {
        self.columns = columns
        self.rows = rows
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.horizontalInset = horizontalInset
    }

    public var perPage: Int { columns * rows }
    public var contentWidth: CGFloat { pageWidth - horizontalInset * 2 }
    public var cellWidth: CGFloat { contentWidth / CGFloat(columns) }
    public var cellHeight: CGFloat { pageHeight / CGFloat(rows) }
}

/// What the cursor is over while dragging, in *displayed* item indices
/// (the list currently on screen, gap included).
public enum DropHit: Hashable, Sendable {
    public enum Zone: Hashable, Sendable {
        case leading, center, trailing
    }

    /// index may equal the item count: "append at the very end".
    case cell(index: Int, zone: Zone)
    case flipLeft
    case flipRight
}

public enum DropMath {
    /// Maps a point (in the pager's local coordinates) to a drop hit.
    /// The center band of an occupied cell means "combine / into folder";
    /// the outer bands mean "insert before / after".
    public static func hitTest(
        _ point: CGPoint,
        metrics: PagerMetrics,
        currentPage: Int,
        totalItems: Int,
        edgeMargin: CGFloat = 36
    ) -> DropHit {
        if point.x < edgeMargin { return .flipLeft }
        if point.x > metrics.pageWidth - edgeMargin { return .flipRight }

        let epsilon: CGFloat = 0.001
        let x = min(max(point.x - metrics.horizontalInset, 0), metrics.contentWidth - epsilon)
        let y = min(max(point.y, 0), metrics.pageHeight - epsilon)
        let column = min(Int(x / metrics.cellWidth), metrics.columns - 1)
        let row = min(Int(y / metrics.cellHeight), metrics.rows - 1)

        let slot = currentPage * metrics.perPage + row * metrics.columns + column
        guard slot < totalItems else {
            return .cell(index: totalItems, zone: .leading)
        }

        let fx = (x - CGFloat(column) * metrics.cellWidth) / metrics.cellWidth
        let zone: DropHit.Zone = fx < 0.28 ? .leading : (fx > 0.72 ? .trailing : .center)
        return .cell(index: slot, zone: zone)
    }

    /// Insertion position implied by a hit, still in displayed indices.
    public static func insertionIndex(for hit: DropHit, totalItems: Int) -> Int? {
        guard case .cell(let index, let zone) = hit else { return nil }
        let raw: Int
        switch zone {
        case .leading, .center: raw = index
        case .trailing: raw = index + 1
        }
        return min(max(raw, 0), totalItems)
    }

    /// Displayed index → index into the same list with the gap removed.
    public static func reducedIndex(fromDisplayed displayed: Int, gapIndex: Int?) -> Int {
        guard let gapIndex else { return displayed }
        return displayed <= gapIndex ? displayed : displayed - 1
    }
}
