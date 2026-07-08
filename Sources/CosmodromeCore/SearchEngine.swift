import Foundation

/// Launchpad-style live filtering: case- and diacritic-insensitive,
/// ranked so the best match is always first (Return launches it).
///
/// Folding uses a fixed neutral locale, NOT .current: under Turkish/Azeri
/// casing rules "I" folds to dotless "ı" while a typed "i" stays "i", which
/// would make every app name containing I/İ unfindable on those systems.
public enum SearchEngine {
    public static func filter(
        _ items: [AppItem],
        query: String,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> [AppItem] {
        let q = fold(query, locale: locale)
        guard !q.isEmpty else { return items }

        let scored: [(item: AppItem, score: Int)] = items.compactMap { item in
            guard let score = score(name: fold(item.name, locale: locale), query: q) else { return nil }
            return (item, score)
        }
        // Stable sort: equal scores keep the incoming (alphabetical) order.
        return scored
            .enumerated()
            .sorted { a, b in
                if a.element.score != b.element.score { return a.element.score > b.element.score }
                return a.offset < b.offset
            }
            .map(\.element.item)
    }

    /// Higher is better; nil means "no match".
    static func score(name: String, query: String) -> Int? {
        if name.hasPrefix(query) { return 4000 - name.count }
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." })
        if words.dropFirst().contains(where: { $0.hasPrefix(query) }) { return 3000 - name.count }
        if name.contains(query) { return 2000 - name.count }
        if isSubsequence(query, of: name) { return 1000 - name.count }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.startIndex
        for ch in needle {
            while it < haystack.endIndex, haystack[it] != ch {
                it = haystack.index(after: it)
            }
            guard it < haystack.endIndex else { return false }
            it = haystack.index(after: it)
        }
        return true
    }

    private static func fold(_ s: String, locale: Locale) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
