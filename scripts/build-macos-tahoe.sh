#!/usr/bin/env bash
# Build the native macOS Tahoe SwiftUI shell and embed the RustTop helper.

set -euo pipefail

APP_NAME="RustTopTahoe"
BINARY="RustTopTahoe"
HELPER="rust_top"
BUNDLE_ID="io.github.sudoshi.RustTopTahoe"
MIN_MACOS="26.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO/macos/RustTopTahoe"
PACKAGING_DIR="$PACKAGE_DIR/Packaging"
APP="$REPO/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ENTITLEMENTS="${RUSTTOP_TAHOE_ENTITLEMENTS:-$PACKAGING_DIR/RustTopTahoe.entitlements}"
SIGN_IDENTITY="${RUSTTOP_TAHOE_SIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
SIGN_KEYCHAIN="${RUSTTOP_TAHOE_SIGN_KEYCHAIN:-}"
ARCHS_REQUEST="${RUSTTOP_TAHOE_ARCHS:-}"

VERSION="$(awk -F '"' '/^version =/ { print $2; exit }' "$REPO/Cargo.toml")"
DIST_DIR="${RUSTTOP_TAHOE_DIST_DIR:-$REPO/dist}"
PACKAGE_BASENAME="${RUSTTOP_TAHOE_PACKAGE_BASENAME:-$APP_NAME-$VERSION-macos}"
PACKAGE_ZIP="${RUSTTOP_TAHOE_PACKAGE_ZIP:-0}"
PACKAGE_DMG="${RUSTTOP_TAHOE_PACKAGE_DMG:-0}"
NOTARIZE="${RUSTTOP_TAHOE_NOTARIZE:-0}"
STAPLE="${RUSTTOP_TAHOE_STAPLE:-0}"
NOTARY_PROFILE="${RUSTTOP_TAHOE_NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${RUSTTOP_TAHOE_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
NOTARY_TEAM_ID="${RUSTTOP_TAHOE_NOTARY_TEAM_ID:-${APPLE_TEAM_ID:-}}"
NOTARY_PASSWORD="${RUSTTOP_TAHOE_NOTARY_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"

PACKAGED_ARTIFACTS=()
ARCHS=()
ARCH_MODE="local"
RUST_HELPER_BINARY=""
RUST_HELPER_SLICE=""
SWIFT_BINARY=""
SWIFT_SLICE_BINARY=""

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "required command '$1' was not found"
    fi
}

require_file() {
    if [[ ! -f "$1" ]]; then
        die "required file '$1' was not found"
    fi
}

host_arch() {
    local machine

    machine="$(uname -m)"
    case "$machine" in
        arm64 | aarch64)
            printf '%s\n' "arm64"
            ;;
        x86_64 | amd64)
            printf '%s\n' "x86_64"
            ;;
        *)
            die "unsupported host architecture '$machine'; set RUSTTOP_TAHOE_ARCHS to x86_64, arm64, or universal"
            ;;
    esac
}

append_arch() {
    local arch="$1"
    local existing

    if ((${#ARCHS[@]} > 0)); then
        for existing in "${ARCHS[@]}"; do
            if [[ "$existing" == "$arch" ]]; then
                return 0
            fi
        done
    fi

    ARCHS+=("$arch")
}

normalize_arch_token() {
    local token

    token="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$token" in
        x86_64 | x64 | amd64 | intel)
            printf '%s\n' "x86_64"
            ;;
        arm64 | aarch64 | apple-silicon | apple_silicon | applesilicon | silicon)
            printf '%s\n' "arm64"
            ;;
        *)
            return 1
            ;;
    esac
}

configure_archs() {
    local normalized
    local token
    local token_count=0
    local tokens=()
    local arch

    normalized="$(printf '%s' "$ARCHS_REQUEST" | tr '[:upper:]' '[:lower:]' | tr ',;' '  ')"

    for token in $normalized; do
        tokens+=("$token")
        token_count=$((token_count + 1))
    done

    if ((token_count == 0)); then
        ARCHS=("$(host_arch)")
        ARCH_MODE="local"
        return 0
    fi

    if ((token_count == 1)); then
        case "${tokens[0]}" in
            default | local | native | host)
                ARCHS=("$(host_arch)")
                ARCH_MODE="local"
                return 0
                ;;
            universal | all | both)
                ARCH_MODE="targeted"
                append_arch "x86_64"
                append_arch "arm64"
                return 0
                ;;
        esac
    fi

    ARCH_MODE="targeted"
    for token in "${tokens[@]}"; do
        case "$token" in
            default | local | native | host)
                append_arch "$(host_arch)"
                ;;
            universal | all | both)
                append_arch "x86_64"
                append_arch "arm64"
                ;;
            *)
                arch="$(normalize_arch_token "$token")" || die "unsupported RUSTTOP_TAHOE_ARCHS token '$token'; use x86_64, arm64, or universal"
                append_arch "$arch"
                ;;
        esac
    done
}

archs_label() {
    local IFS=","
    printf '%s' "$*"
}

rust_target_for_arch() {
    case "$1" in
        x86_64)
            printf '%s\n' "x86_64-apple-darwin"
            ;;
        arm64)
            printf '%s\n' "aarch64-apple-darwin"
            ;;
        *)
            die "unsupported architecture '$1'"
            ;;
    esac
}

swift_triple_for_arch() {
    case "$1" in
        x86_64 | arm64)
            printf '%s-apple-macosx%s\n' "$1" "$MIN_MACOS"
            ;;
        *)
            die "unsupported architecture '$1'"
            ;;
    esac
}

swift_build_dir_for_arch() {
    case "$1" in
        x86_64 | arm64)
            printf '%s-apple-macosx\n' "$1"
            ;;
        *)
            die "unsupported architecture '$1'"
            ;;
    esac
}

find_swift_binary() {
    local host_candidate="$PACKAGE_DIR/.build/$(swift_build_dir_for_arch "${ARCHS[0]}")/release/$BINARY"
    local candidate="$PACKAGE_DIR/.build/release/$BINARY"

    if [[ -x "$host_candidate" ]]; then
        printf '%s\n' "$host_candidate"
        return 0
    fi

    if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    find "$PACKAGE_DIR/.build" \
        -path "*/release/$BINARY" \
        -type f \
        -print \
        -quit
}

find_swift_binary_for_arch() {
    local arch="$1"
    local build_root="$2"
    local build_dir
    local candidate

    build_dir="$(swift_build_dir_for_arch "$arch")"
    candidate="$build_root/$build_dir/release/$BINARY"

    if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    find "$build_root" \
        -path "*/$build_dir/release/$BINARY" \
        -type f \
        -print \
        -quit
}

signing_enabled() {
    [[ -n "$SIGN_IDENTITY" ]]
}

env_enabled() {
    case "${1:-}" in
        1 | true | TRUE | yes | YES | on | ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

zip_packaging_enabled() {
    env_enabled "$PACKAGE_ZIP"
}

dmg_packaging_enabled() {
    env_enabled "$PACKAGE_DMG"
}

packaging_enabled() {
    zip_packaging_enabled || dmg_packaging_enabled
}

notarization_enabled() {
    env_enabled "$NOTARIZE"
}

stapling_enabled() {
    env_enabled "$STAPLE"
}

run_codesign() {
    local path="$1"
    shift

    local args=(--force --options runtime --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        args+=(--timestamp)
    fi
    if [[ -n "$SIGN_KEYCHAIN" ]]; then
        args+=(--keychain "$SIGN_KEYCHAIN")
    fi

    codesign "${args[@]}" "$@" "$path"
}

require_notary_credentials() {
    if [[ -n "$NOTARY_PROFILE" ]]; then
        return 0
    fi

    if [[ -z "$NOTARY_APPLE_ID" || -z "$NOTARY_TEAM_ID" || -z "$NOTARY_PASSWORD" ]]; then
        echo "error: notarization requires RUSTTOP_TAHOE_NOTARY_PROFILE or all of:" >&2
        echo "       RUSTTOP_TAHOE_NOTARY_APPLE_ID, RUSTTOP_TAHOE_NOTARY_TEAM_ID, RUSTTOP_TAHOE_NOTARY_PASSWORD" >&2
        echo "       APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD are also accepted." >&2
        exit 1
    fi
}

notarize_artifact() {
    local artifact="$1"
    local args=(notarytool submit "$artifact" --wait)

    if [[ -n "$NOTARY_PROFILE" ]]; then
        args+=(--keychain-profile "$NOTARY_PROFILE")
    else
        args+=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
    fi

    echo "Submitting for notarization: $artifact"
    xcrun "${args[@]}"
}

staple_artifact() {
    local artifact="$1"

    echo "Stapling notarization ticket: $artifact"
    xcrun stapler staple "$artifact"
    xcrun stapler validate "$artifact"
}

require_swift_triple_support() {
    if ! swift build --help 2>/dev/null | grep -q -- "--triple"; then
        die "SwiftPM does not advertise --triple support; install a Swift toolchain that can target macOS slices"
    fi
}

validate_rust_target() {
    local arch="$1"
    local target
    local target_libdir

    target="$(rust_target_for_arch "$arch")"

    if ! rustc --print target-list | grep -qx "$target"; then
        die "rustc does not support target '$target'"
    fi

    if command -v rustup >/dev/null 2>&1; then
        if ! rustup target list --installed | grep -qx "$target"; then
            die "Rust target '$target' is not installed; run: rustup target add $target"
        fi
    else
        target_libdir="$(rustc --print target-libdir --target "$target" 2>/dev/null)" || {
            die "Rust standard library for '$target' is not available in this toolchain"
        }
        if [[ ! -d "$target_libdir" ]]; then
            die "Rust standard library for '$target' is not available at $target_libdir"
        fi
    fi
}

validate_requested_archs() {
    local arch

    require_swift_triple_support

    if [[ "$ARCH_MODE" == "targeted" ]]; then
        for arch in "${ARCHS[@]}"; do
            validate_rust_target "$arch"
        done
    fi
}

verify_architectures() {
    local path="$1"
    shift

    local expected_arch
    local actual_arch
    local actual_archs
    local found
    local expected_count=$#
    local actual_count=0

    require_file "$path"
    actual_archs="$(lipo -archs "$path")" || die "could not inspect architectures for '$path'"

    for expected_arch in "$@"; do
        found=0
        for actual_arch in $actual_archs; do
            if [[ "$actual_arch" == "$expected_arch" ]]; then
                found=1
                break
            fi
        done

        if ((found == 0)); then
            die "expected '$path' to contain architecture '$expected_arch' but found: $actual_archs"
        fi
    done

    for actual_arch in $actual_archs; do
        actual_count=$((actual_count + 1))
        found=0
        for expected_arch in "$@"; do
            if [[ "$actual_arch" == "$expected_arch" ]]; then
                found=1
                break
            fi
        done

        if ((found == 0)); then
            die "unexpected architecture '$actual_arch' in '$path'; expected: $(archs_label "$@")"
        fi
    done

    if ((actual_count != expected_count)); then
        die "architecture count mismatch for '$path'; expected $(archs_label "$@") but found: $actual_archs"
    fi

    echo "Verified architectures for $(basename "$path"): $actual_archs"
}

append_locked_cargo_arg() {
    if [[ "${RUSTTOP_LOCKED:-0}" == "1" ]]; then
        cargo_args+=(--locked)
    fi
}

build_rust_helper_local() {
    local cargo_args

    echo "Building RustTop helper..."
    cargo_args=(build --release --manifest-path "$REPO/Cargo.toml")
    append_locked_cargo_arg
    cargo "${cargo_args[@]}"

    RUST_HELPER_BINARY="$REPO/target/release/$HELPER"
    verify_architectures "$RUST_HELPER_BINARY" "${ARCHS[@]}"
}

build_rust_helper_for_arch() {
    local arch="$1"
    local target
    local cargo_args

    target="$(rust_target_for_arch "$arch")"

    echo "Building RustTop helper ($arch / $target)..."
    cargo_args=(build --release --manifest-path "$REPO/Cargo.toml" --target "$target")
    append_locked_cargo_arg
    cargo "${cargo_args[@]}"

    RUST_HELPER_SLICE="$REPO/target/$target/release/$HELPER"
    verify_architectures "$RUST_HELPER_SLICE" "$arch"
}

build_rust_helper() {
    local arch
    local helper_slices=()
    local output

    if [[ "$ARCH_MODE" == "local" ]]; then
        build_rust_helper_local
        return 0
    fi

    for arch in "${ARCHS[@]}"; do
        build_rust_helper_for_arch "$arch"
        helper_slices+=("$RUST_HELPER_SLICE")
    done

    if ((${#helper_slices[@]} == 1)); then
        RUST_HELPER_BINARY="${helper_slices[0]}"
        return 0
    fi

    output="$TMP_DIR/universal/$HELPER"
    mkdir -p "$(dirname "$output")"

    echo "Creating universal RustTop helper ($(archs_label "${ARCHS[@]}"))..."
    lipo -create "${helper_slices[@]}" -output "$output"
    chmod +x "$output"
    RUST_HELPER_BINARY="$output"
    verify_architectures "$RUST_HELPER_BINARY" "${ARCHS[@]}"
}

build_swift_shell_local() {
    local arch="${ARCHS[0]}"

    echo "Building native Tahoe shell..."
    swift build -c release --package-path "$PACKAGE_DIR" --triple "$(swift_triple_for_arch "$arch")"

    SWIFT_BINARY="$(find_swift_binary)"
    if [[ -z "$SWIFT_BINARY" ]]; then
        die "could not find built Swift binary '$BINARY' under $PACKAGE_DIR/.build"
    fi

    verify_architectures "$SWIFT_BINARY" "${ARCHS[@]}"
}

build_swift_shell_for_arch() {
    local arch="$1"
    local scratch="$TMP_DIR/swift-$arch"

    echo "Building native Tahoe shell ($arch)..."
    swift build -c release \
        --package-path "$PACKAGE_DIR" \
        --scratch-path "$scratch" \
        --triple "$(swift_triple_for_arch "$arch")"

    SWIFT_SLICE_BINARY="$(find_swift_binary_for_arch "$arch" "$scratch")"
    if [[ -z "$SWIFT_SLICE_BINARY" ]]; then
        die "could not find built Swift binary '$BINARY' for architecture '$arch' under $scratch"
    fi

    verify_architectures "$SWIFT_SLICE_BINARY" "$arch"
}

build_swift_shell() {
    local arch
    local swift_slices=()
    local output

    if [[ "$ARCH_MODE" == "local" ]]; then
        build_swift_shell_local
        return 0
    fi

    for arch in "${ARCHS[@]}"; do
        build_swift_shell_for_arch "$arch"
        swift_slices+=("$SWIFT_SLICE_BINARY")
    done

    if ((${#swift_slices[@]} == 1)); then
        SWIFT_BINARY="${swift_slices[0]}"
        return 0
    fi

    output="$TMP_DIR/universal/$BINARY"
    mkdir -p "$(dirname "$output")"

    echo "Creating universal native Tahoe shell ($(archs_label "${ARCHS[@]}"))..."
    lipo -create "${swift_slices[@]}" -output "$output"
    chmod +x "$output"
    SWIFT_BINARY="$output"
    verify_architectures "$SWIFT_BINARY" "${ARCHS[@]}"
}

notarize_app_bundle() {
    local notary_zip="$TMP_DIR/$PACKAGE_BASENAME-notary.zip"

    echo "Creating temporary notarization archive..."
    ditto -c -k --keepParent "$APP" "$notary_zip"
    notarize_artifact "$notary_zip"
}

package_zip() {
    local zip_path="$DIST_DIR/$PACKAGE_BASENAME.zip"

    echo "Creating release zip: $zip_path"
    rm -f "$zip_path" "$zip_path.sha256"
    ditto -c -k --keepParent "$APP" "$zip_path"
    PACKAGED_ARTIFACTS+=("$zip_path")
}

package_dmg() {
    local dmg_path="$DIST_DIR/$PACKAGE_BASENAME.dmg"
    local dmg_root="$TMP_DIR/dmg-root"
    local staged_app="$dmg_root/$(basename "$APP")"

    echo "Creating release DMG: $dmg_path"
    rm -rf "$dmg_root"
    rm -f "$dmg_path" "$dmg_path.sha256"
    mkdir -p "$dmg_root"
    ditto "$APP" "$staged_app"
    ln -s /Applications "$dmg_root/Applications"
    hdiutil create \
        -volname "RustTop Tahoe $VERSION" \
        -fs HFS+ \
        -srcfolder "$dmg_root" \
        -format UDZO \
        -ov \
        "$dmg_path"
    PACKAGED_ARTIFACTS+=("$dmg_path")
}

write_checksum() {
    local artifact="$1"
    local artifact_dir
    local artifact_name

    artifact_dir="$(cd "$(dirname "$artifact")" && pwd)"
    artifact_name="$(basename "$artifact")"

    echo "Writing checksum: $artifact.sha256"
    (
        cd "$artifact_dir"
        shasum -a 256 "$artifact_name" > "$artifact_name.sha256"
    )
}

write_package_checksums() {
    local artifact

    for artifact in "${PACKAGED_ARTIFACTS[@]}"; do
        write_checksum "$artifact"
    done
}

configure_archs

require_command cargo
require_command rustc
require_command swift
require_command lipo
require_command sips
require_command iconutil
require_file "$REPO/Cargo.toml"
require_file "$REPO/assets/icons/rust_top_1024.png"

if packaging_enabled; then
    require_command shasum
    mkdir -p "$DIST_DIR"
fi

if zip_packaging_enabled || dmg_packaging_enabled || notarization_enabled; then
    require_command ditto
fi

if dmg_packaging_enabled; then
    require_command hdiutil
fi

if signing_enabled; then
    require_command codesign
    require_command plutil
    require_file "$ENTITLEMENTS"
    plutil -lint "$ENTITLEMENTS" >/dev/null
fi

if notarization_enabled || stapling_enabled; then
    require_command xcrun

    if ! signing_enabled; then
        echo "error: notarization/stapling requires RUSTTOP_TAHOE_SIGN_IDENTITY or DEVELOPER_ID_APPLICATION." >&2
        exit 1
    fi
fi

if notarization_enabled; then
    require_notary_credentials
fi

validate_requested_archs

echo "Tahoe build architectures: $(archs_label "${ARCHS[@]}")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

build_rust_helper
build_swift_shell

echo "Assembling $APP_NAME.app..."
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES"

cp "$SWIFT_BINARY" "$MACOS_DIR/$BINARY"
cp "$RUST_HELPER_BINARY" "$RESOURCES/$HELPER"
verify_architectures "$MACOS_DIR/$BINARY" "${ARCHS[@]}"
verify_architectures "$RESOURCES/$HELPER" "${ARCHS[@]}"

echo "Building icon..."
ICONSET="$TMP_DIR/$HELPER.iconset"
mkdir -p "$ICONSET"
SRC="$REPO/assets/icons/rust_top_1024.png"

sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" --output "$RESOURCES/$HELPER.icns"

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
    <string>RustTop Tahoe</string>
    <key>CFBundleExecutable</key>
    <string>${BINARY}</string>
    <key>CFBundleIconFile</key>
    <string>${HELPER}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 RustTop Contributors. MIT License.</string>
</dict>
</plist>
PLIST

if signing_enabled; then
    echo "Signing embedded helper and app with hardened runtime..."
    run_codesign "$RESOURCES/$HELPER" --identifier "$BUNDLE_ID.helper"
    run_codesign "$APP"

    codesign --verify --strict --verbose=2 "$RESOURCES/$HELPER"
    codesign --verify --deep --strict --verbose=2 "$APP"
else
    echo "Skipping codesign; set RUSTTOP_TAHOE_SIGN_IDENTITY or DEVELOPER_ID_APPLICATION to sign."
fi

if notarization_enabled; then
    notarize_app_bundle
else
    echo "Skipping notarization; set RUSTTOP_TAHOE_NOTARIZE=1 with notary credentials to submit."
fi

if stapling_enabled; then
    staple_artifact "$APP"
else
    echo "Skipping stapling; set RUSTTOP_TAHOE_STAPLE=1 after notarization to staple."
fi

if packaging_enabled; then
    if zip_packaging_enabled; then
        package_zip
    fi

    if dmg_packaging_enabled; then
        package_dmg

        if notarization_enabled; then
            dmg_artifact="$DIST_DIR/$PACKAGE_BASENAME.dmg"
            notarize_artifact "$dmg_artifact"

            if stapling_enabled; then
                staple_artifact "$dmg_artifact"
            fi
        fi
    fi

    write_package_checksums
else
    echo "Skipping release packaging; set RUSTTOP_TAHOE_PACKAGE_ZIP=1 or RUSTTOP_TAHOE_PACKAGE_DMG=1."
fi

echo "Built: $APP"
if ((${#PACKAGED_ARTIFACTS[@]} > 0)); then
    echo "Packaged artifacts:"
    for artifact in "${PACKAGED_ARTIFACTS[@]}"; do
        echo "  $artifact"
        echo "  $artifact.sha256"
    done
fi
echo "Run: open \"$APP\""
