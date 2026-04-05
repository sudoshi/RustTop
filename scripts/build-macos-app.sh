#!/usr/bin/env bash
# Build a macOS .app bundle for RustTop.
# Usage: ./scripts/build-macos-app.sh [--install]
#   --install  Also copy the .app to /Applications

set -euo pipefail

APP_NAME="RustTop"
BINARY="rust_top"
BUNDLE_ID="io.github.sudoshi.RustTop"
VERSION="0.1.0"
MIN_MACOS="12.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

APP="$REPO/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "▶ Building $APP_NAME (release)..."
cargo build --release --manifest-path "$REPO/Cargo.toml"

# ── 2. Bundle skeleton ────────────────────────────────────────────────────────
echo "▶ Assembling $APP_NAME.app..."
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES"

# Copy binary
cp "$REPO/target/release/$BINARY" "$MACOS_DIR/$BINARY"

# ── 3. Icon (.icns) ───────────────────────────────────────────────────────────
echo "▶ Building icon..."
ICONSET="$(mktemp -d)/$BINARY.iconset"
mkdir -p "$ICONSET"

SRC="$REPO/assets/icons/rust_top_1024.png"  # 1024×1024 master

# macOS iconset requires these exact filenames
sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp            "$SRC"     "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" --output "$RESOURCES/$BINARY.icns"
rm -rf "$(dirname "$ICONSET")"

# ── 4. Info.plist ─────────────────────────────────────────────────────────────
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>

    <key>CFBundleName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleExecutable</key>
    <string>${BINARY}</string>

    <key>CFBundleIconFile</key>
    <string>${BINARY}</string>

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>

    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 RustTop Contributors. MIT License.</string>

    <key>NSSupportsAutomaticTermination</key>
    <false/>

    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# ── 5. Optionally install ─────────────────────────────────────────────────────
echo ""
echo "✓  Built: $APP"
echo "   To run: open \"$APP\""
echo ""

if [[ "${1:-}" == "--install" ]]; then
    INSTALL_PATH="/Applications/$APP_NAME.app"
    echo "▶ Installing to $INSTALL_PATH..."
    rm -rf "$INSTALL_PATH"
    cp -R "$APP" "$INSTALL_PATH"
    echo "✓  Installed. Launch from Finder or: open /Applications/$APP_NAME.app"
else
    read -rp "Copy to /Applications? [y/N] " choice
    if [[ "${choice,,}" == "y" ]]; then
        INSTALL_PATH="/Applications/$APP_NAME.app"
        rm -rf "$INSTALL_PATH"
        cp -R "$APP" "$INSTALL_PATH"
        echo "✓  Installed to $INSTALL_PATH"
    fi
fi
