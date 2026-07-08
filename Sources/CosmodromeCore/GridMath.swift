import Foundation

/// Pure geometry of the paged 7×5 grid: pagination and arrow-key movement.
/// Indices are positions in the flat (filtered) app list, row-major per page.
public struct GridMath: Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int = 7, rows: Int = 5) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
    }

    public var perPage: Int { columns * rows }

    public func pageCount(for total: Int) -> Int {
        total <= 0 ? 1 : (total + perPage - 1) / perPage
    }

    public func paginate<T>(_ items: [T]) -> [[T]] {
        guard !items.isEmpty else { return [[]] }
        return stride(from: 0, to: items.count, by: perPage).map {
            Array(items[$0 ..< min($0 + perPage, items.count)])
        }
    }

    public func page(of index: Int) -> Int { max(index, 0) / perPage }

    public func firstIndex(onPage page: Int, total: Int) -> Int {
        min(max(page, 0) * perPage, max(total - 1, 0))
    }

    public enum Direction: Sendable {
        case left, right, up, down
    }

    /// Where an arrow key moves the selection. Never returns an out-of-range
    /// index; at hard edges the selection stays put.
    public func move(from index: Int, direction: Direction, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let i = min(max(index, 0), total - 1)
        let p = page(of: i)
        let offset = i % perPage
        let row = offset / columns
        let col = offset % columns

        switch direction {
        case .left:
            return max(i - 1, 0)
        case .right:
            return min(i + 1, total - 1)
        case .down:
            if row < rows - 1 {
                let candidate = i + columns
                return candidate < min((p + 1) * perPage, total) ? candidate : i
            }
            // Bottom row: hop to the same column on the next page's top row.
            let nextStart = (p + 1) * perPage
            guard nextStart < total else { return i }
            return min(nextStart + col, total - 1)
        case .up:
            if row > 0 { return i - columns }
            // Top row: hop to the same column on the previous page's bottom row.
            guard p > 0 else { return i }
            return (p - 1) * perPage + (rows - 1) * columns + col
        }
    }
}
