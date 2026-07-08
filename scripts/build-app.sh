#!/usr/bin/env bash
# build-app.sh — build, bundle, sign and zip Cosmodrome (SwiftPM macOS app).
# Usage: scripts/build-app.sh      (lives in scripts/, package root is its parent)
# Overridable: APP_NAME, BUNDLE_ID, VERSION, UNIVERSAL=0 to force native-only build.
set -euo pipefail

APP_NAME="${APP_NAME:-Cosmodrome}"
BUNDLE_ID="${BUNDLE_ID:-io.github.cleoanka.Cosmodrome}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Version: VERSION file wins, else env/default.
if [[ -f "$ROOT/VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
else
  VERSION="${VERSION:-0.1.0}"
fi

# Toolchain: the bare CommandLineTools SwiftPM can fail to link Package.swift
# (undefined PackageDescription symbols). Prefer full Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> Building $APP_NAME $VERSION ($BUNDLE_ID)"

# Keep the build reproducible and free of local paths in the binary.
PREFIX_MAP_FLAGS=(-Xswiftc -file-prefix-map -Xswiftc "$ROOT=/cosmodrome"
                  -Xswiftc -file-prefix-map -Xswiftc "$HOME=/build")

# Universal if the toolchain supports it, else native (arm64 on Apple Silicon).
UNIVERSAL="${UNIVERSAL:-1}"
BIN=""
if [[ "$UNIVERSAL" == "1" ]] && \
   swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 "${PREFIX_MAP_FLAGS[@]}"; then
  BIN="$ROOT/.build/apple/Products/Release/$APP_NAME"
  echo "==> Universal build OK"
else
  echo "==> Universal build unavailable; falling back to native build"
  swift build --package-path "$ROOT" -c release "${PREFIX_MAP_FLAGS[@]}"
  BIN="$ROOT/.build/release/$APP_NAME"
fi
[[ -x "$BIN" ]] || { echo "ERROR: binary not found at $BIN" >&2; exit 1; }
lipo -info "$BIN" || true

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# Info.plist from template. plutil treats values literally and XML-escapes,
# so names like "Launch & Go" can't corrupt the plist the way sed would.
PLIST="$APP/Contents/Info.plist"
cp "$SCRIPT_DIR/Info.plist.template" "$PLIST"
plutil -replace CFBundleIdentifier         -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleName               -string "$APP_NAME"  "$PLIST"
plutil -replace CFBundleDisplayName        -string "$APP_NAME"  "$PLIST"
plutil -replace CFBundleExecutable         -string "$APP_NAME"  "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION"   "$PLIST"
plutil -replace CFBundleVersion            -string "$VERSION"   "$PLIST"
plutil -lint "$PLIST"

# Icon (optional; scripts/make-icon.py regenerates it).
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  echo "==> Embedded AppIcon.icns"
else
  echo "==> No Resources/AppIcon.icns found; skipping icon"
fi

echo "==> Checking for leaked local paths"
if strings "$APP/Contents/MacOS/$APP_NAME" | grep -F "$HOME" | head -3; then
  echo "WARNING: binary still contains local paths" >&2
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

# --norsrc --noextattr: xattrs (com.apple.provenance) would otherwise become
# AppleDouble ._* entries that break codesign verification after CLI unzip.
ZIP="$DIST/$APP_NAME-$VERSION.zip"
echo "==> Zipping to $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"

echo "==> Done"
ls -la "$DIST"
