import XCTest
@testable import CosmodromeCore

final class SearchEngineTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func items(_ names: [String]) -> [AppItem] {
        names.map { AppItem(url: URL(fileURLWithPath: "/Applications/\($0).app"), name: $0, bundleID: nil) }
    }

    private func names(_ items: [AppItem]) -> [String] { items.map(\.name) }

    func testEmptyQueryReturnsEverything() {
        let apps = items(["Safari", "Notes"])
        XCTAssertEqual(SearchEngine.filter(apps, query: "", locale: locale).count, 2)
        XCTAssertEqual(SearchEngine.filter(apps, query: "   ", locale: locale).count, 2)
    }

    func testPrefixBeatsWordPrefixBeatsSubstring() {
        let apps = items(["System Settings", "Sablier", "Assassin", "Safari"])
        let result = names(SearchEngine.filter(apps, query: "sa", locale: locale))
        // Name-prefix matches first (shorter name wins ties), then substring.
        XCTAssertEqual(result.first, "Safari")
        XCTAssertEqual(result[1], "Sablier")
        XCTAssertTrue(result.contains("Assassin"))
        XCTAssertLessThan(
            result.firstIndex(of: "Sablier")!,
            result.firstIndex(of: "Assassin")!
        )
    }

    func testWordPrefixMatch() {
        let apps = items(["System Settings", "Notes"])
        let result = names(SearchEngine.filter(apps, query: "set", locale: locale))
        XCTAssertEqual(result, ["System Settings"])
    }

    func testSubsequenceFallback() {
        let apps = items(["Final Cut Pro", "Finder"])
        let result = names(SearchEngine.filter(apps, query: "fcp", locale: locale))
        XCTAssertEqual(result, ["Final Cut Pro"])
    }

    func testCaseAndDiacriticInsensitive() {
        let apps = items(["Müzik", "Mail"])
        XCTAssertEqual(names(SearchEngine.filter(apps, query: "muzik", locale: locale)), ["Müzik"])
        XCTAssertEqual(names(SearchEngine.filter(apps, query: "MAIL", locale: locale)), ["Mail"])
    }

    func testNoMatchReturnsEmpty() {
        let apps = items(["Safari"])
        XCTAssertTrue(SearchEngine.filter(apps, query: "zzz", locale: locale).isEmpty)
    }

    func testDefaultLocaleIsImmuneToTurkishCasing() {
        // With the default (fixed) fold locale, names containing I/İ must stay
        // findable no matter what Locale.current is — the tr_TR regression.
        let apps = items(["IINA", "İstanbul", "MIDI Monitor"])
        XCTAssertEqual(names(SearchEngine.filter(apps, query: "iina")), ["IINA"])
        XCTAssertEqual(names(SearchEngine.filter(apps, query: "istanbul")), ["İstanbul"])
        XCTAssertEqual(names(SearchEngine.filter(apps, query: "midi")), ["MIDI Monitor"])
        XCTAssertEqual(names(SearchEngine.filter(apps, query: "IINA")), ["IINA"])
    }

    func testTopHitIsStableForEqualScores() {
        // Alphabetical input order must survive equal scores (Return opens [0]).
        let apps = items(["Calculator", "Calendar"])
        let result = names(SearchEngine.filter(apps, query: "cal", locale: locale))
        XCTAssertEqual(result.first, "Calendar") // shorter name ranks first
    }
}
