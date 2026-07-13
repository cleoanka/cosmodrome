# Cosmodrome

**The full-screen app grid macOS lost.**

[![CI](https://github.com/cleoanka/cosmodrome/actions/workflows/ci.yml/badge.svg)](https://github.com/cleoanka/cosmodrome/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/cleoanka/cosmodrome?sort=semver)](https://github.com/cleoanka/cosmodrome/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#install)

macOS Tahoe removed Launchpad and replaced it with a Spotlight list. If you loved
the old way — every app on a wallpaper-blurred canvas, a keystroke away — Cosmodrome
brings it back, rebuilt natively in Swift.

> **What's new in 0.2.0** — the grid is now editable: drag to rearrange, drop app
> onto app to make **folders**, one-action **auto-grouping** by category, a
> **finger-tracking pager**, and atomic **layout persistence**. See the
> [changelog](CHANGELOG.md).

![Cosmodrome demo](docs/demo.gif)

## What it does

- **The grid you remember** — a paged 7×5 full-screen grid of every app on your Mac,
  over your own wallpaper, blurred and dimmed exactly like Launchpad did it.
- **Your order, your folders** — drag icons to rearrange (a live gap opens where
  they'll land), drop one app onto another to fuse a folder, drop onto a folder
  to file it away, drag out to free it. Folders open in a glass panel with
  paging, click-to-rename, and category-suggested names. Everything persists.
- **Auto folders** — one menu action groups the whole grid by App Store category
  (Developer Tools, Games, Music…), iOS App Library style. One action flattens
  it back to A–Z.
- **Pages that follow your fingers** — trackpad and mouse drags track 1:1 with
  rubber-band physics and a flick-aware spring snap; pages recede in depth as
  they slide; the active page dot glides along live. Icon drags near the screen
  edge flip pages for you.
- **Summon from anywhere** — a global hotkey (default **⌥ Space**, recordable to
  anything) pops the grid over any app, even full-screen ones. No Accessibility
  permission needed.
- **Type to search** — no field to click; just start typing. Ranked live results
  (folders are searched through, too), best match pre-selected, **Return**
  launches it.
- **Launchpad's soul** — the zoom-and-materialize entrance, the dive-in launch
  animation, press-to-dim icons, the translucent search pill.
- **Everything indexed** — `/Applications` (with subfolders), `~/Applications`,
  `/System/Applications`, and Safari's cryptex; symlinked apps included;
  deduplicated by bundle ID; new installs appear at the end, uninstalls vanish.
- **Quiet resident** — a menu-bar item and ~30 MB of memory. Optional start at
  login. No network, no analytics, no nonsense.

| Grid | Search |
| --- | --- |
| ![Grid](docs/screenshot-grid.png) | ![Search](docs/screenshot-search.png) |

> The demo and screenshots above are from 0.1.0; the 0.2.0 drag/folder/pager
> features are not yet captured. Fresh media is on the way.

## Install

Grab `Cosmodrome-x.y.z.zip` from [Releases](https://github.com/cleoanka/cosmodrome/releases),
unzip, drop `Cosmodrome.app` into `/Applications`.

The app is ad-hoc signed (no Apple Developer certificate), so on first run either
right-click → **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Cosmodrome.app
```

Or build it yourself — see below. Requires macOS 14+.

> Tip: keep `Cosmodrome.app` in your Dock. Clicking it opens the grid, exactly
> like the old Launchpad tile. Want it on F4 like the old days? Remap F4 to
> ⌥ Space with Karabiner-Elements, or record a different shortcut in Settings.

## Keys

| Key | Action |
| --- | --- |
| ⌥ Space | Open / close (configurable) |
| any letter | Search |
| ← → ↑ ↓ | Walk the grid (crosses pages, works inside folders) |
| Return | Launch selection / best match; opens a selected folder |
| Esc | Cancel drag → close folder → clear search → close |
| Page Up / Down, Home / End | Flip pages |
| two-finger swipe / scroll | Pages follow your fingers |

| Mouse | Action |
| --- | --- |
| drag an icon | Rearrange (hold at a screen edge to change page) |
| drop app on app | New folder (named after its category) |
| drop app on folder | Add to folder |
| drag out of an open folder | Remove from folder |
| click a folder's name | Rename |
| right-click | Open · Show in Finder · Rename · Ungroup · Remove from Folder |

Click an empty spot (or any other window) to dismiss. The **Arrange** menu in
the menu bar offers *Sort Alphabetically* and *Group by Category*.

## Build from source

```bash
git clone https://github.com/cleoanka/cosmodrome
cd cosmodrome
./scripts/build-app.sh        # → dist/Cosmodrome.app (universal, ad-hoc signed)
```

Needs Xcode (the bare Command Line Tools SwiftPM may fail; the script prefers
`/Applications/Xcode.app` automatically). `swift test` runs the unit tests for
the scanner, search ranking and grid geometry. `scripts/make-icon.py`
(Python + Pillow) regenerates the icon.

## How it works

A borderless, non-activating `NSPanel` one level above the menu bar — the
Spotlight trick — so the grid takes the keyboard without stealing app activation
and gives focus straight back when it closes. All input flows through local
event monitors into an observable `GridState`; there is no focusable text field
to lose focus (even folder renaming is routed keystrokes). The wallpaper is
read once per screen, Gaussian-blurred and saturation-boosted with Core Image
off the main thread, then cached.

Drag & drop is custom-built: a pure hit-testing module (`DropMath`) maps the
cursor to insert/combine/into-folder proposals, a coordinator animates the gap
through the grid, and every layout mutation funnels through one tested engine
(`LayoutEngine`) that owns the invariants — folders never nest, never hold one
app, and an app never appears twice. Your arrangement lives in
`~/Library/Application Support/Cosmodrome/layout.json`; auto folders come from
each app's `LSApplicationCategoryType`. Pure logic (scanning, ranking, grid
geometry, layout, drop math) lives in `CosmodromeCore`, fully unit-tested.

## Roadmap

- Per-app hide list
- Multi-display polish
- Custom folder icons

## Contributing

Bug reports and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the
build/test workflow and architecture notes. Release history lives in
[CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © 2026 cleoanka
