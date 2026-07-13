# Contributing to Cosmodrome

Thanks for your interest in Cosmodrome. This is a small, focused native macOS
app; contributions that keep it fast, quiet, and Launchpad-faithful are welcome.

## Requirements

- **macOS 14 (Sonoma) or newer.**
- **Full Xcode** (not just the Command Line Tools). The bare CommandLineTools
  SwiftPM can fail to link `Package.swift` with undefined `PackageDescription`
  symbols, so point SwiftPM at Xcode:

  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```

  The build script sets this for you automatically when Xcode is present.

## Build & test

```bash
git clone https://github.com/cleoanka/cosmodrome
cd cosmodrome

swift build          # debug build
swift test           # 48 unit tests: scanner, search ranking, grid + drop geometry, layout
./scripts/build-app.sh   # → dist/Cosmodrome.app (universal, ad-hoc signed) + dist/Cosmodrome-<version>.zip
```

CI runs `swift build` and `swift test` on every push and pull request
(`.github/workflows/ci.yml`). Please make sure both stay green before opening a PR.

## Architecture

Pure, deterministic logic lives in the **`CosmodromeCore`** target and is fully
unit-tested — scanning, search ranking, grid geometry, layout, and drop math.
AppKit/SwiftUI glue (panels, event monitors, drag coordination, persistence)
lives in the **`Cosmodrome`** executable target. When adding behaviour, prefer
pushing the testable logic down into `CosmodromeCore` and covering it with a test.

Layout invariants are owned by `LayoutEngine`: folders never nest, never hold a
single app, and an app never appears twice. New layout mutations should funnel
through it.

## Code style

- Swift, 4-space indentation, ~100-column soft limit (see `.editorconfig`).
- Keep the app dependency-free and offline: no network, no analytics.
- Match the surrounding code; keep diffs focused.

## Commits & pull requests

- Write clear, imperative commit subjects (e.g. `layout: fix reflow after ungroup`).
- Keep pull requests small and scoped; describe the user-visible change.
- If you change behaviour covered by tests, update the tests in the same PR.

## Releases

Releases are cut from a version tag. The distributable is built with
`./scripts/build-app.sh` (which reads the version from the `VERSION` file) and
attached to the matching GitHub Release.
