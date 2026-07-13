# Changelog

All notable changes to Cosmodrome are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-07-13

The grid became editable.

### Added
- **Drag to rearrange** — pick up any icon; a live ghost follows the cursor,
  neighbours reflow in real time, and a gap opens where the icon will land.
- **Folders** — drop one app onto another to fuse a folder, drop onto a folder
  to file it away, drag out to free it. Folders open in a glass panel with
  paging, click-to-rename, and category-suggested names.
- **Auto-grouping** — one menu action groups the whole grid by App Store
  category (iOS App Library style); one action flattens it back to A–Z.
- **Finger-tracking pager** — the pager now tracks the finger continuously
  instead of snapping page-by-page, with rubber-band physics and a
  flick-aware spring snap; pages recede in depth as they slide.
- **Layout persistence** — every rearrangement is persisted atomically to
  `~/Library/Application Support/Cosmodrome/layout.json`, so a crash mid-drag
  can never corrupt the saved layout.

### Core modules (unit-tested logic)
- `LayoutEngine` — grid/folder model + reflow, ungroup, move operations,
  owning the invariants (folders never nest, never hold one app, an app never
  appears twice).
- `DropMath` — pure drop-target and insertion-index geometry.
- `AppLayout` — persisted layout schema (pages, folders, order).
- `CategoryNames` — category-based auto-grouping seed.

### AppKit modules
- `DragCoordinator` — finger-tracking drag/drop session driver.
- `PagerDrive` — continuous, finger-tracking pager physics.
- `LayoutStore` — atomic layout persistence.
- `FolderViews` / `DragGhostView` — folder and live drag-ghost UI.

### Tests
- +22 tests (`LayoutEngineTests`, `DropMathTests`) — **48 total, all green.**

## [0.1.0] — 2026-07-08

The first release: the full-screen app grid macOS lost.

### Added
- Paged 7×5 full-screen grid over the blurred, saturation-boosted wallpaper,
  rendered off the main thread and cached per screen.
- Global hotkey (default **⌥ Space**, recordable) via a non-activating
  `NSPanel` one level above the menu bar — no Accessibility permission needed.
- Type-to-search with ranked live results and best-match pre-selection.
- Keyboard navigation across pages, trackpad paging with rubber-band physics.
- Menu-bar residency, optional start at login, recordable shortcut.
- App indexing across `/Applications` (with subfolders), `~/Applications`,
  `/System/Applications`, and Safari's cryptex; deduplicated by bundle ID.

### Quality
- Adversarially reviewed by a 24-agent workflow plus a Codex second opinion;
  all 11 confirmed findings fixed (Turkish-locale search folding, swipe
  mis-launch, ghost shortcut recorder, AppleDouble zip corruption, async
  wallpaper blur, deterministic scanner dedupe, and more).
- 26 unit tests.

[0.2.0]: https://github.com/cleoanka/cosmodrome/releases/tag/v0.2.0
[0.1.0]: https://github.com/cleoanka/cosmodrome/releases/tag/v0.1.0
