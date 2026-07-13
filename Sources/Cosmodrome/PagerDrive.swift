import SwiftUI

/// The pager's live, finger-following offset. Its own tiny ObservableObject
/// so per-pointer-event updates invalidate only the pager and the page dots,
/// never the whole grid.
@MainActor
final class PagerDrive: ObservableObject {
    /// Pixels of live drag/scroll, same sign as a drag translation
    /// (fingers right → positive → content follows right).
    @Published var liveOffset: CGFloat = 0

    /// Reported by PagerView's geometry.
    var pageWidth: CGFloat = 800
    var gestureActive = false
    /// Last per-event scroll delta, for flick detection.
    var lastDelta: CGFloat = 0
}
