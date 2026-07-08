import AppKit
import SwiftUI
import CosmodromeCore

enum Anim {
    static let page = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let appear = Animation.spring(response: 0.38, dampingFraction: 0.92)
    static let disappear = Animation.easeIn(duration: 0.16)
    static let launch = Animation.easeIn(duration: 0.22)
}

/// Everything the overlay renders, plus the little state machine that drives
/// the show/launch/hide transitions. The OverlayController is the only writer
/// of `phase`; views react.
@MainActor
final class GridState: ObservableObject {
    enum Phase {
        case hidden, shown, launching
    }

    @Published var allApps: [AppItem] = [] {
        didSet { filterCache = nil }
    }
    @Published private(set) var query: String = ""
    @Published var currentPage: Int = 0
    @Published var selection: Int? = nil
    @Published var phase: Phase = .hidden
    @Published var wallpaper: NSImage? = nil

    /// True while a page-swipe drag is in flight; the mouse-up that ends a
    /// swipe also fires the icon button it started on, so cells consult this
    /// before launching. Deliberately not @Published (set per pointer event).
    var isPageDragging = false

    private var filterCache: (query: String, apps: [AppItem])?
    @Published var dimAmount: Double = UserDefaults.standard.object(forKey: "dimAmount") as? Double ?? 0.32 {
        didSet { UserDefaults.standard.set(dimAmount, forKey: "dimAmount") }
    }

    let grid = GridMath(columns: 7, rows: 5)

    /// Wired up by OverlayController.
    var onHideRequest: () -> Void = {}
    var onLaunchRequest: (AppItem) -> Void = { _ in }
    var onRevealRequest: (AppItem) -> Void = { _ in }

    /// Memoized: the filter folds every app name, and views read this several
    /// times per body pass — recomputing per access would burn a millisecond
    /// of string folding on every drag frame.
    var visibleApps: [AppItem] {
        if query.isEmpty { return allApps }
        if let cache = filterCache, cache.query == query { return cache.apps }
        let filtered = SearchEngine.filter(allApps, query: query)
        filterCache = (query, filtered)
        return filtered
    }

    var pages: [[AppItem]] { grid.paginate(visibleApps) }
    var pageCount: Int { grid.pageCount(for: visibleApps.count) }

    // MARK: - Query editing (all keyboard input is routed here by the controller)

    func setQuery(_ newValue: String) {
        guard newValue != query else { return }
        query = newValue
        currentPage = 0
        selection = (newValue.isEmpty || visibleApps.isEmpty) ? nil : 0
    }

    func appendToQuery(_ s: String) { setQuery(query + s) }

    func backspace() {
        guard !query.isEmpty else { return }
        setQuery(String(query.dropLast()))
    }

    // MARK: - Selection & paging

    func moveSelection(_ direction: GridMath.Direction) {
        let total = visibleApps.count
        guard total > 0 else { return }
        let target: Int
        if let current = selection {
            target = grid.move(from: current, direction: direction, total: total)
        } else {
            target = grid.firstIndex(onPage: currentPage, total: total)
        }
        selection = target
        let page = grid.page(of: target)
        if page != currentPage {
            withAnimation(Anim.page) { currentPage = page }
        }
    }

    func flipPage(_ delta: Int) {
        goToPage(currentPage + delta)
    }

    func goToPage(_ page: Int) {
        let target = min(max(page, 0), pageCount - 1)
        guard target != currentPage else { return }
        selection = nil
        withAnimation(Anim.page) {
            currentPage = target
        }
    }

    // MARK: - Launching

    /// What Return should open: the arrowed selection, or the top hit while searching.
    func itemToLaunch() -> AppItem? {
        let apps = visibleApps
        guard !apps.isEmpty else { return nil }
        if let selection, apps.indices.contains(selection) { return apps[selection] }
        return query.isEmpty ? nil : apps[0]
    }

    func requestHide() { onHideRequest() }
    func launch(_ item: AppItem) { onLaunchRequest(item) }
    func reveal(_ item: AppItem) { onRevealRequest(item) }

    // MARK: - App list

    func resetForShow() {
        query = ""
        currentPage = 0
        selection = nil
        isPageDragging = false
        phase = .hidden
    }

    nonisolated static let ownBundleID = Bundle.main.bundleIdentifier ?? "io.github.cleoanka.Cosmodrome"

    func scanNow() {
        allApps = AppScanner.scan(excludingBundleIDs: [Self.ownBundleID])
    }

    func refreshApps() {
        Task.detached(priority: .userInitiated) {
            let items = AppScanner.scan(excludingBundleIDs: [Self.ownBundleID])
            await MainActor.run { [weak self] in
                guard let self, items != self.allApps else { return }
                // The list may shift under an existing selection; keep the
                // highlight on the same app, not the same index.
                let selectedID = self.selection.flatMap {
                    self.visibleApps.indices.contains($0) ? self.visibleApps[$0].id : nil
                }
                self.allApps = items
                self.currentPage = min(self.currentPage, self.pageCount - 1)
                self.selection = selectedID.flatMap { id in
                    self.visibleApps.firstIndex { $0.id == id }
                }
            }
        }
    }

}
