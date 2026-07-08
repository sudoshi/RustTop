#!/usr/bin/env bash
# Static source audit for RustTop Tahoe visual and accessibility readiness.
#
# This complements, but does not replace, GUI screenshot review, Accessibility
# Inspector, Instruments, notarization, or clean-machine install validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${RUSTTOP_TAHOE_STATIC_AUDIT_OUT_DIR:-$REPO/dist/tahoe-static-audit/$TIMESTAMP}"

usage() {
    cat <<'EOF'
Usage: scripts/audit-macos-tahoe-static.sh [options]

Runs a source-level audit for Tahoe visual/accessibility guardrails that can be
validated without a desktop GUI session.

Options:
  --out PATH   Evidence output directory.
  -h, --help   Show this help.
EOF
}

while (($# > 0)); do
    case "$1" in
        --out)
            shift || {
                echo "error: --out requires a path" >&2
                exit 1
            }
            OUT_DIR="$1"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            exit 1
            ;;
    esac
    shift
done

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

CHECKS="$OUT_DIR/checks.tsv"
SUMMARY="$OUT_DIR/summary.md"
METRICS="$OUT_DIR/metrics.tsv"
SOURCE_ROOT="$REPO/macos/RustTopTahoe/Sources/RustTopTahoe"
DASHBOARD="$SOURCE_ROOT/Views/DashboardView.swift"
SETTINGS="$SOURCE_ROOT/Views/SettingsView.swift"
MENU_BAR="$SOURCE_ROOT/Views/MenuBarMonitorView.swift"
GLASS="$SOURCE_ROOT/Design/GlassPanel.swift"
APP="$SOURCE_ROOT/RustTopTahoeApp.swift"
APP_SETTINGS="$SOURCE_ROOT/AppState/RustTopSettings.swift"
QA_SCRIPT="$REPO/scripts/qa-macos-tahoe.sh"

PASS_COUNT=0
FAIL_COUNT=0

printf 'check\tstatus\tevidence\tnote\n' >"$CHECKS"
printf 'metric\tvalue\tnote\n' >"$METRICS"

record_check() {
    local name="$1"
    local status="$2"
    local evidence="$3"
    local note="$4"

    printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$evidence" "$note" >>"$CHECKS"

    case "$status" in
        pass)
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        fail)
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
    esac
}

record_metric() {
    local name="$1"
    local value="$2"
    local note="$3"

    printf '%s\t%s\t%s\n' "$name" "$value" "$note" >>"$METRICS"
}

count_fixed() {
    local file="$1"
    local pattern="$2"

    grep -F -c "$pattern" "$file" 2>/dev/null || true
}

contains_fixed() {
    local file="$1"
    local pattern="$2"

    grep -F -q "$pattern" "$file" 2>/dev/null
}

require_file() {
    local name="$1"
    local file="$2"
    local note="$3"

    if [[ -f "$file" ]]; then
        record_check "$name" "pass" "${file#$REPO/}" "$note"
    else
        record_check "$name" "fail" "${file#$REPO/}" "missing file"
    fi
}

require_contains() {
    local name="$1"
    local file="$2"
    local pattern="$3"
    local note="$4"

    if contains_fixed "$file" "$pattern"; then
        record_check "$name" "pass" "${file#$REPO/}" "$note"
    else
        record_check "$name" "fail" "${file#$REPO/}" "missing pattern: $pattern"
    fi
}

require_min_count() {
    local name="$1"
    local file="$2"
    local pattern="$3"
    local minimum="$4"
    local note="$5"
    local count

    count="$(count_fixed "$file" "$pattern")"
    record_metric "$name.count" "$count" "$pattern in ${file#$REPO/}"

    if ((count >= minimum)); then
        record_check "$name" "pass" "${file#$REPO/}:$count" "$note"
    else
        record_check "$name" "fail" "${file#$REPO/}:$count" "expected at least $minimum matches for $pattern"
    fi
}

if [[ -d "$SOURCE_ROOT" ]]; then
    record_check "swift-source-root" "pass" "${SOURCE_ROOT#$REPO/}" "Tahoe Swift source root exists"
else
    record_check "swift-source-root" "fail" "${SOURCE_ROOT#$REPO/}" "Tahoe Swift source root is missing"
fi

require_file "dashboard-view" "$DASHBOARD" "main dashboard source exists"
require_file "settings-view" "$SETTINGS" "settings source exists"
require_file "menu-bar-view" "$MENU_BAR" "menu bar source exists"
require_file "glass-panel" "$GLASS" "glass panel source exists"
require_file "qa-harness" "$QA_SCRIPT" "QA harness exists"

require_contains \
    "main-window-minimum-size" \
    "$APP" \
    ".frame(minWidth: 980, minHeight: 680)" \
    "main window protects the explicit small visual QA target"

require_contains \
    "qa-window-size-targets" \
    "$QA_SCRIPT" \
    "980x680 1280x820 1728x1117" \
    "scripted GUI audit includes small, default, and wide sizes"

require_contains \
    "qa-screenshot-capture" \
    "$QA_SCRIPT" \
    "screencapture -x -l" \
    "scripted GUI audit captures target window images when permitted"

require_contains \
    "qa-accessibility-preflight" \
    "$QA_SCRIPT" \
    "accessibility-preflight.txt" \
    "GUI audit records Accessibility permission before launch"

require_contains \
    "qa-accessibility-status" \
    "$QA_SCRIPT" \
    "UI elements enabled" \
    "GUI audit checks System Events Accessibility control"

require_min_count \
    "dashboard-accessibility-labels" \
    "$DASHBOARD" \
    ".accessibilityLabel" \
    20 \
    "dashboard exposes VoiceOver labels across primary surfaces"

require_min_count \
    "dashboard-accessibility-values" \
    "$DASHBOARD" \
    ".accessibilityValue" \
    15 \
    "dashboard exposes dynamic VoiceOver values"

require_min_count \
    "settings-accessibility-labels" \
    "$SETTINGS" \
    ".accessibilityLabel" \
    8 \
    "settings controls expose VoiceOver labels"

require_min_count \
    "menu-bar-accessibility-labels" \
    "$MENU_BAR" \
    ".accessibilityLabel" \
    6 \
    "menu bar monitor exposes VoiceOver labels"

require_contains \
    "metric-card-accessibility" \
    "$DASHBOARD" \
    "\(title) metric" \
    "metric cards include synthesized accessibility labels"

require_contains \
    "process-table-accessibility" \
    "$DASHBOARD" \
    "Process table" \
    "process table has an accessibility container"

require_contains \
    "launchd-accessibility" \
    "$DASHBOARD" \
    "launchd inventory summary" \
    "services view has read-only launchd accessibility summary"

require_contains \
    "reduced-motion-hook" \
    "$DASHBOARD" \
    "accessibilityReduceMotion" \
    "animation respects reduced-motion environment"

require_contains \
    "glass-high-contrast-hook" \
    "$GLASS" \
    "colorSchemeContrast" \
    "glass panels adapt to increased contrast"

require_contains \
    "dashboard-high-contrast-hook" \
    "$DASHBOARD" \
    "colorSchemeContrast" \
    "dashboard graphics adapt to increased contrast"

require_contains \
    "theme-preference-model" \
    "$APP_SETTINGS" \
    "enum DashboardTheme" \
    "settings model supports system, light, and dark themes"

require_contains \
    "theme-applied-to-window" \
    "$APP" \
    ".preferredColorScheme(settings.preferredColorScheme)" \
    "app applies persisted dashboard theme to native surfaces"

{
    echo "# RustTop Tahoe Static Audit"
    echo
    echo "- Timestamp UTC: $TIMESTAMP"
    echo "- Output directory: \`$OUT_DIR\`"
    echo "- Passed checks: $PASS_COUNT"
    echo "- Failed checks: $FAIL_COUNT"
    echo
    echo "Artifacts:"
    echo
    echo "- \`checks.tsv\`"
    echo "- \`metrics.tsv\`"
    echo
    echo "This static audit validates source-level guardrails only. It does not prove"
    echo "manual visual quality, actual screenshot overlap behavior, VoiceOver rotor"
    echo "quality, Accessibility Inspector output, Instruments results, notarization,"
    echo "or clean-machine install behavior."
} >"$SUMMARY"

echo "Wrote static audit summary: $SUMMARY"

if ((FAIL_COUNT > 0)); then
    echo "error: static audit failed; see $CHECKS" >&2
    exit 1
fi
