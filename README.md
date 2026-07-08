# Cosmodrome

**The full-screen app grid macOS lost.**

macOS Tahoe removed Launchpad and replaced it with a Spotlight list. If you loved
the old way — every app on a wallpaper-blurred canvas, a keystroke away — Cosmodrome
brings it back, rebuilt natively in Swift.

![Cosmodrome demo](docs/demo.gif)

## What it does

- **The grid you remember** — a paged 7×5 full-screen grid of every app on your Mac,
  over your own wallpaper, blurred and dimmed exactly like Launchpad did it.
- **Summon from anywhere** — a global hotkey (default **⌥ Space**, recordable to
  anything) pops the grid over any app, even full-screen ones. No Accessibility
  permission needed.
- **Type to search** — no field to click; just start typing. Ranked live results,
  best match pre-selected, **Return** launches it.
- **Made for hands** — trackpad swipes and mouse drags flip pages with rubber-band
  physics; arrow keys walk the grid across page boundaries; clickable page dots.
- **Launchpad's soul** — the zoom-and-materialize entrance, the dive-in launch
  animation, press-to-dim icons, the translucent search pill.
- **Everything indexed** — `/Applications` (with subfolders), `~/Applications`,
  `/System/Applications`, and Safari's cryptex; symlinked apps included;
  deduplicated by bundle ID; alphabetical, always tidy.
- **Quiet resident** — a menu-bar item and ~30 MB of memory. Optional start at
  login. No network, no analytics, no nonsense.

| Grid | Search |
| --- | --- |
| ![Grid](docs/screenshot-grid.png) | ![Search](docs/screenshot-search.png) |

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
| ← → ↑ ↓ | Walk the grid (crosses pages) |
| Return | Launch selection / best match |
| Esc | Clear search, then close |
| Page Up / Down, Home / End | Flip pages |
| two-finger swipe / scroll | Flip pages |

Click an empty spot (or any other window) to dismiss. Right-click an icon for
**Show in Finder**.

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
to lose focus. The wallpaper is read once per screen, Gaussian-blurred and
saturation-boosted with Core Image, then cached. The global hotkey is a Carbon
`RegisterEventHotKey` — still the only permissionless way. Pure logic
(scanning, ranking, grid geometry) lives in `CosmodromeCore`, fully unit-tested.

## Roadmap

- Drag-to-reorder and folders (the full Launchpad experience)
- Per-app hide list
- Multi-display polish

## License

[MIT](LICENSE)
