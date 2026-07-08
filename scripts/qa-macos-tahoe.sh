#!/usr/bin/env bash
# Lightweight QA/audit harness for the native macOS Tahoe app.
#
# This collects repeatable evidence for build, helper refresh, screenshots, and
# accessibility inspection. It is intentionally not a substitute for manual QA.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PROCESS="${RUSTTOP_TAHOE_QA_APP_PROCESS:-RustTopTahoe}"
APP="${RUSTTOP_TAHOE_APP:-$REPO/RustTopTahoe.app}"
HELPER="${RUSTTOP_TAHOE_HELPER:-$APP/Contents/Resources/rust_top}"
DMG="${RUSTTOP_TAHOE_DMG:-}"
RUN_BUILD="${RUSTTOP_TAHOE_QA_BUILD:-1}"
RUN_SMOKE="${RUSTTOP_TAHOE_QA_SMOKE:-1}"
RUN_RELEASE_VALIDATION="${RUSTTOP_TAHOE_QA_RELEASE_VALIDATION:-1}"
SKIP_GUI="${RUSTTOP_TAHOE_QA_SKIP_GUI:-0}"
STRICT_GUI="${RUSTTOP_TAHOE_QA_STRICT_GUI:-0}"
STRICT_RELEASE="${RUSTTOP_TAHOE_QA_STRICT_RELEASE:-0}"
QUIT_APP="${RUSTTOP_TAHOE_QA_QUIT_APP:-0}"
FORCE_MAIN_WINDOW="${RUSTTOP_TAHOE_QA_FORCE_MAIN_WINDOW:-1}"
OPEN_FRESH="${RUSTTOP_TAHOE_QA_OPEN_FRESH:-1}"
SMOKE_SECONDS="${RUSTTOP_TAHOE_SMOKE_SECONDS:-60}"
SMOKE_INTERVAL_SECONDS="${RUSTTOP_TAHOE_SMOKE_INTERVAL_SECONDS:-2}"
STREAM_SECONDS="${RUSTTOP_TAHOE_STREAM_SECONDS:-0}"
STREAM_INTERVAL_MS="${RUSTTOP_TAHOE_STREAM_INTERVAL_MS:-1000}"
STREAM_SAMPLE_INTERVAL_SECONDS="${RUSTTOP_TAHOE_STREAM_SAMPLE_INTERVAL_SECONDS:-1}"
LAUNCH_WAIT_SECONDS="${RUSTTOP_TAHOE_QA_LAUNCH_WAIT_SECONDS:-20}"
WINDOW_SIZES="${RUSTTOP_TAHOE_WINDOW_SIZES:-980x680 1280x820 1728x1117}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${RUSTTOP_TAHOE_QA_OUT_DIR:-$REPO/dist/tahoe-qa/$TIMESTAMP}"
SIGN_IDENTITY="${RUSTTOP_TAHOE_SIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
NOTARY_PROFILE="${RUSTTOP_TAHOE_NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${RUSTTOP_TAHOE_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
NOTARY_TEAM_ID="${RUSTTOP_TAHOE_NOTARY_TEAM_ID:-${APPLE_TEAM_ID:-}}"
NOTARY_PASSWORD="${RUSTTOP_TAHOE_NOTARY_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"

LOG=""
SUMMARY=""
TMP_DIR=""
GUI_RESULT="not-run"
SMOKE_RESULT="not-run"
STREAM_RESULT="not-run"
RELEASE_RESULT="not-run"
SCREENSHOT_COUNT=0
ACCESSIBILITY_RESULT="not-run"
APP_WAS_RUNNING=0
RELEASE_DIR=""
RELEASE_CHECKS=0
RELEASE_PASSED=0
RELEASE_NOT_READY=0
RELEASE_SKIPPED=0
RELEASE_FAILED=0
RELEASE_APP_SIGNATURE_READY=0
CLEAN_MACHINE_CHECKLIST=""
BUNDLE_ID=""
GUI_DEFAULTS_BACKUP=""
GUI_DEFAULTS_DOMAIN_EXISTED=0
GUI_DEFAULTS_PREPARED=0
APP_LAUNCHED_BY_QA=0
APP_LAUNCHED_PID=""

usage() {
    cat <<'EOF'
Usage: scripts/qa-macos-tahoe.sh [options]

Builds or reuses RustTopTahoe.app, runs a helper refresh smoke, and captures
GUI evidence when a macOS desktop session allows it.

Options:
  --no-build              Reuse an existing app bundle.
  --no-smoke              Skip the embedded helper refresh smoke.
  --no-release-validation Skip signing, Gatekeeper, stapling, and clean-install evidence.
  --no-gui                Skip launch, window evidence, screenshots, and AX dump.
  --strict-gui            Treat unavailable GUI audit pieces as failures.
  --strict-release        Fail if release validation is not ready or fails.
  --app PATH              App bundle path. Defaults to ./RustTopTahoe.app.
  --helper PATH           Embedded helper path. Defaults to app Resources/rust_top.
  --dmg PATH              Release DMG path for Gatekeeper/stapler checks.
  --out PATH              Evidence output directory.
  --sizes "WxH ..."       Window sizes. Defaults to "980x680 1280x820 1728x1117".
  --smoke-seconds N       Helper smoke duration. Defaults to 60.
  --smoke-interval N      Seconds between helper refreshes. Defaults to 2.
  --stream-seconds N      Persistent helper stream duration. Defaults to 0/skipped.
  --stream-interval-ms N  Milliseconds between streamed helper snapshots. Defaults to 1000.
  --stream-sample-interval N
                          Seconds between stream process resource samples.
  -h, --help              Show this help.

Useful environment:
  RUSTTOP_TAHOE_SMOKE_SECONDS=1800   Run the helper smoke for 30 minutes.
  RUSTTOP_TAHOE_STREAM_SECONDS=1800  Run the persistent helper stream for
                                     30 minutes and sample process resources.
  RUSTTOP_TAHOE_DMG=dist/RustTopTahoe-<version>-macos.dmg
                                     Validate a packaged DMG.
  RUSTTOP_TAHOE_QA_SKIP_GUI=1        Make headless runs explicit.
  RUSTTOP_TAHOE_QA_STRICT_GUI=1      Fail instead of skipping GUI-only checks.
  RUSTTOP_TAHOE_QA_STRICT_RELEASE=1  Fail when signing/notarization checks
                                     are missing, rejected, or not stapled.
  RUSTTOP_TAHOE_QA_FORCE_MAIN_WINDOW=0
                                     Do not temporarily force main-window
                                     launch defaults during GUI QA.
  RUSTTOP_TAHOE_QA_OPEN_FRESH=0      Use plain open instead of open -F.
  RUSTTOP_TAHOE_QA_QUIT_APP=1        Quit the app after the GUI audit if this
                                     script launched it.
EOF
}

is_truthy() {
    case "${1:-}" in
        1 | true | TRUE | yes | YES | on | ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

die() {
    local message="$1"

    printf 'error: %s\n' "$message" >&2
    if [[ -n "${LOG:-}" ]]; then
        printf 'error: %s\n' "$message" >>"$LOG"
    fi
    exit 1
}

log() {
    printf '%s\n' "$*" | tee -a "$LOG"
}

warn() {
    log "warning: $*"
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        die "required command '$command_name' was not found"
    fi
}

validate_positive_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || ((value < 1)); then
        die "$name must be a positive integer; got '$value'"
    fi
}

validate_nonnegative_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        die "$name must be a nonnegative integer; got '$value'"
    fi
}

while (($# > 0)); do
    case "$1" in
        --no-build)
            RUN_BUILD=0
            ;;
        --no-smoke)
            RUN_SMOKE=0
            ;;
        --no-release-validation)
            RUN_RELEASE_VALIDATION=0
            ;;
        --no-gui)
            SKIP_GUI=1
            ;;
        --strict-gui)
            STRICT_GUI=1
            ;;
        --strict-release)
            STRICT_RELEASE=1
            ;;
        --app)
            shift || die "--app requires a path"
            APP="$1"
            HELPER="$APP/Contents/Resources/rust_top"
            ;;
        --helper)
            shift || die "--helper requires a path"
            HELPER="$1"
            ;;
        --dmg)
            shift || die "--dmg requires a path"
            DMG="$1"
            ;;
        --out)
            shift || die "--out requires a path"
            OUT_DIR="$1"
            ;;
        --sizes)
            shift || die "--sizes requires a quoted size list"
            WINDOW_SIZES="$1"
            ;;
        --smoke-seconds)
            shift || die "--smoke-seconds requires a value"
            SMOKE_SECONDS="$1"
            ;;
        --smoke-interval)
            shift || die "--smoke-interval requires a value"
            SMOKE_INTERVAL_SECONDS="$1"
            ;;
        --stream-seconds)
            shift || die "--stream-seconds requires a value"
            STREAM_SECONDS="$1"
            ;;
        --stream-interval-ms)
            shift || die "--stream-interval-ms requires a value"
            STREAM_INTERVAL_MS="$1"
            ;;
        --stream-sample-interval)
            shift || die "--stream-sample-interval requires a value"
            STREAM_SAMPLE_INTERVAL_SECONDS="$1"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown option '$1'"
            ;;
    esac
    shift
done

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
LOG="$OUT_DIR/qa.log"
SUMMARY="$OUT_DIR/summary.md"
TMP_DIR="$(mktemp -d)"
: >"$LOG"

cleanup() {
    local exit_code=$?

    set +e

    if is_truthy "${QUIT_APP:-0}" && ((APP_LAUNCHED_BY_QA == 1)) && [[ -n "${APP_LAUNCHED_PID:-}" ]]; then
        if kill -0 "$APP_LAUNCHED_PID" >/dev/null 2>&1; then
            kill "$APP_LAUNCHED_PID" >/dev/null 2>&1 || true
            for _ in 1 2 3 4 5; do
                kill -0 "$APP_LAUNCHED_PID" >/dev/null 2>&1 || break
                sleep 0.2
            done
            kill -0 "$APP_LAUNCHED_PID" >/dev/null 2>&1 &&
                kill -9 "$APP_LAUNCHED_PID" >/dev/null 2>&1 || true
        fi
    fi

    if ((GUI_DEFAULTS_PREPARED == 1)) && [[ -n "${BUNDLE_ID:-}" ]]; then
        if ((GUI_DEFAULTS_DOMAIN_EXISTED == 1)) && [[ -f "$GUI_DEFAULTS_BACKUP" ]]; then
            defaults import "$BUNDLE_ID" "$GUI_DEFAULTS_BACKUP" >/dev/null 2>&1 || true
        else
            defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
        fi
        defaults synchronize "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi

    rm -rf "$TMP_DIR"
    exit "$exit_code"
}

trap cleanup EXIT

if is_truthy "$RUN_SMOKE"; then
    validate_positive_integer "RUSTTOP_TAHOE_SMOKE_SECONDS" "$SMOKE_SECONDS"
    validate_positive_integer "RUSTTOP_TAHOE_SMOKE_INTERVAL_SECONDS" "$SMOKE_INTERVAL_SECONDS"
fi
validate_nonnegative_integer "RUSTTOP_TAHOE_STREAM_SECONDS" "$STREAM_SECONDS"
if ((STREAM_SECONDS > 0)); then
    validate_positive_integer "RUSTTOP_TAHOE_STREAM_INTERVAL_MS" "$STREAM_INTERVAL_MS"
    validate_positive_integer \
        "RUSTTOP_TAHOE_STREAM_SAMPLE_INTERVAL_SECONDS" \
        "$STREAM_SAMPLE_INTERVAL_SECONDS"
fi
validate_positive_integer "RUSTTOP_TAHOE_QA_LAUNCH_WAIT_SECONDS" "$LAUNCH_WAIT_SECONDS"

skip_gui() {
    local reason="$1"

    GUI_RESULT="skipped: $reason"
    if is_truthy "$STRICT_GUI"; then
        die "GUI audit unavailable: $reason"
    fi

    log "Skipping GUI audit: $reason"
}

run_build() {
    if ! is_truthy "$RUN_BUILD"; then
        log "Skipping build; reusing app bundle: $APP"
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        die "Tahoe app bundle build requires macOS; rerun with --no-build only if an existing bundle is available"
    fi

    log "Building Tahoe app bundle..."
    if "$REPO/scripts/build-macos-tahoe.sh" >"$OUT_DIR/build.log" 2>&1; then
        log "Build succeeded; log: $OUT_DIR/build.log"
    else
        warn "Build failed; last log lines follow."
        tail -n 40 "$OUT_DIR/build.log" | tee -a "$LOG" >&2 || true
        die "scripts/build-macos-tahoe.sh failed"
    fi
}

verify_app_artifacts() {
    if [[ ! -d "$APP" ]]; then
        die "app bundle not found at '$APP'; build first or pass --app PATH"
    fi

    if [[ ! -x "$HELPER" ]]; then
        die "embedded helper not executable at '$HELPER'; build first or pass --helper PATH"
    fi
}

resolve_bundle_id() {
    local plist="$APP/Contents/Info.plist"

    if [[ -n "$BUNDLE_ID" ]]; then
        return 0
    fi

    if [[ -f "$plist" ]] && command -v plutil >/dev/null 2>&1; then
        BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null || true)"
    fi

    if [[ -z "$BUNDLE_ID" ]] && [[ -x /usr/libexec/PlistBuddy ]]; then
        BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
    fi

    if [[ -z "$BUNDLE_ID" ]]; then
        BUNDLE_ID="io.github.sudoshi.RustTopTahoe"
    fi
}

write_gui_environment_evidence() {
    local evidence="$OUT_DIR/gui-environment.txt"
    local accessibility_status="unknown"

    resolve_bundle_id

    if command -v osascript >/dev/null 2>&1; then
        accessibility_status="$(osascript -e 'tell application "System Events" to UI elements enabled' 2>&1 || true)"
    fi

    {
        echo "timestamp_utc=$TIMESTAMP"
        echo "app=$APP"
        echo "process=$APP_PROCESS"
        echo "bundle_id=$BUNDLE_ID"
        echo "force_main_window=$(is_truthy "$FORCE_MAIN_WINDOW" && echo yes || echo no)"
        echo "open_fresh=$(is_truthy "$OPEN_FRESH" && echo yes || echo no)"
        echo "strict_gui=$(is_truthy "$STRICT_GUI" && echo yes || echo no)"
        echo "quit_app=$(is_truthy "$QUIT_APP" && echo yes || echo no)"
        echo "launch_wait_seconds=$LAUNCH_WAIT_SECONDS"
        echo "system_events_ui_elements_enabled=$accessibility_status"
        echo "window_server_running=$(pgrep -x WindowServer >/dev/null 2>&1 && echo yes || echo no)"
        echo
        echo "## running app process"
        if pgrep -x "$APP_PROCESS" >/dev/null 2>&1; then
            ps -o pid,ppid,stat,etime,command -p "$(pgrep -x "$APP_PROCESS" | paste -sd, -)" 2>&1 || true
        else
            echo "not-running"
        fi
        echo
        echo "## app defaults before GUI audit"
        if command -v defaults >/dev/null 2>&1; then
            defaults export "$BUNDLE_ID" - 2>&1 | plutil -p - 2>&1 || true
        else
            echo "defaults command unavailable"
        fi
    } >"$evidence"

    log "Wrote GUI environment evidence: $evidence"
}

gui_accessibility_enabled() {
    local evidence="$OUT_DIR/accessibility-preflight.txt"

    if ! osascript -e 'tell application "System Events" to UI elements enabled' >"$evidence" 2>&1; then
        return 1
    fi

    grep -Eq '^[[:space:]]*true[[:space:]]*$' "$evidence"
}

prepare_gui_defaults() {
    if ! is_truthy "$FORCE_MAIN_WINDOW"; then
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]] || ! command -v defaults >/dev/null 2>&1; then
        return 0
    fi

    resolve_bundle_id
    GUI_DEFAULTS_BACKUP="$OUT_DIR/gui-defaults-before.plist"

    if defaults export "$BUNDLE_ID" "$GUI_DEFAULTS_BACKUP" >/dev/null 2>"$OUT_DIR/gui-defaults-before.stderr"; then
        GUI_DEFAULTS_DOMAIN_EXISTED=1
        rm -f "$OUT_DIR/gui-defaults-before.stderr"
    else
        GUI_DEFAULTS_DOMAIN_EXISTED=0
        rm -f "$GUI_DEFAULTS_BACKUP"
    fi

    GUI_DEFAULTS_PREPARED=1
    defaults write "$BUNDLE_ID" settings.startupBehavior -string openMainWindow
    defaults write "$BUNDLE_ID" settings.lastMainWindowVisible -bool true
    defaults synchronize "$BUNDLE_ID" >/dev/null 2>&1 || true

    defaults export "$BUNDLE_ID" "$OUT_DIR/gui-defaults-forced.plist" >/dev/null 2>&1 || true
    log "Temporarily forced main-window launch defaults for GUI audit; original defaults will be restored on exit."
}

open_app_for_gui_audit() {
    if is_truthy "$OPEN_FRESH"; then
        open -F "$APP"
    else
        open "$APP"
    fi
}

collect_static_evidence() {
    local evidence="$OUT_DIR/app-evidence.txt"

    {
        echo "timestamp_utc=$TIMESTAMP"
        echo "repo=$REPO"
        echo "app=$APP"
        echo "helper=$HELPER"
        echo
        echo "## git"
        git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true
        git -C "$REPO" status --short 2>/dev/null || true
        echo
        echo "## system"
        uname -a
        if command -v sw_vers >/dev/null 2>&1; then
            sw_vers
        fi
        echo
        echo "## bundle"
        if [[ -f "$APP/Contents/Info.plist" ]]; then
            if command -v plutil >/dev/null 2>&1; then
                plutil -p "$APP/Contents/Info.plist" 2>&1 || true
            else
                sed -n '1,120p' "$APP/Contents/Info.plist"
            fi
        fi
        echo
        echo "## codesign"
        if command -v codesign >/dev/null 2>&1; then
            codesign -dv --verbose=4 "$APP" 2>&1 || true
            codesign -dv --verbose=4 "$HELPER" 2>&1 || true
        else
            echo "codesign unavailable"
        fi
        echo
        echo "## helper"
        "$HELPER" --version 2>&1 || true
    } >"$evidence"

    log "Wrote static evidence: $evidence"
}

validate_json_file() {
    local json_file="$1"
    local stderr_file="$2"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$json_file" > /dev/null 2>"$stderr_file" <<'PY'
import json
import sys

with open(sys.argv[1], "rb") as handle:
    json.load(handle)
PY
        return $?
    fi

    if command -v jq >/dev/null 2>&1; then
        jq empty "$json_file" > /dev/null 2>"$stderr_file"
        return $?
    fi

    if command -v osascript >/dev/null 2>&1; then
        local jxa="$TMP_DIR/validate-json.jxa"
        if [[ ! -f "$jxa" ]]; then
            cat >"$jxa" <<'JXA'
function run(argv) {
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    JSON.parse(app.read(Path(argv[0])));
}
JXA
        fi
        osascript -l JavaScript "$jxa" "$json_file" > /dev/null 2>"$stderr_file"
        return $?
    fi

    echo "no JSON parser found; falling back to schema marker check" >"$stderr_file"
    return 2
}

validate_jsonl_file() {
    local jsonl_file="$1"
    local stderr_file="$2"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$jsonl_file" > /dev/null 2>"$stderr_file" <<'PY'
import json
import sys

path = sys.argv[1]
count = 0
with open(path, "r", encoding="utf-8") as handle:
    for lineno, raw_line in enumerate(handle, 1):
        line = raw_line.strip()
        if not line:
            continue
        count += 1
        payload = json.loads(line)
        if payload.get("schema_version") != 1:
            raise SystemExit(f"line {lineno}: schema_version is not 1")

if count == 0:
    raise SystemExit("no JSON objects found")
PY
        return $?
    fi

    if command -v jq >/dev/null 2>&1; then
        jq 'if .schema_version == 1 then empty else error("schema_version is not 1") end' \
            "$jsonl_file" > /dev/null 2>"$stderr_file"
        return $?
    fi

    echo "no JSONL parser found; falling back to schema marker check" >"$stderr_file"
    return 2
}

run_helper_smoke() {
    local smoke_dir="$OUT_DIR/helper-smoke"
    local csv="$smoke_dir/iterations.csv"
    local latest="$smoke_dir/latest.json"
    local first="$smoke_dir/first.json"
    local tmp_snapshot="$smoke_dir/latest.tmp.json"
    local deadline
    local failures=0
    local iteration=0

    if ! is_truthy "$RUN_SMOKE"; then
        SMOKE_RESULT="skipped"
        log "Skipping helper refresh smoke."
        return 0
    fi

    mkdir -p "$smoke_dir"
    printf 'iteration,unix_time,duration_seconds,status,bytes,note\n' >"$csv"

    log "Running helper refresh smoke for ${SMOKE_SECONDS}s at ${SMOKE_INTERVAL_SECONDS}s intervals..."
    deadline=$(($(date +%s) + SMOKE_SECONDS))

    while :; do
        local now
        local started
        local duration
        local bytes
        local status="ok"
        local note="snapshot-valid"
        local stderr_file="$smoke_dir/iteration-$((iteration + 1)).stderr"

        now="$(date +%s)"
        if ((now >= deadline && iteration > 0)); then
            break
        fi

        iteration=$((iteration + 1))
        started="$(date +%s)"

        if "$HELPER" --export-json "$tmp_snapshot" >/dev/null 2>"$stderr_file"; then
            duration=$(($(date +%s) - started))
            bytes="$(wc -c <"$tmp_snapshot" | tr -d '[:space:]')"

            if [[ -z "$bytes" ]] || ((bytes == 0)); then
                status="fail"
                note="empty-json"
            else
                local json_stderr="$smoke_dir/json-parse-$iteration.stderr"
                local json_status=0
                if validate_json_file "$tmp_snapshot" "$json_stderr"; then
                    rm -f "$json_stderr"
                else
                    json_status=$?
                    if ((json_status == 2)); then
                        note="schema-only-no-json-parser"
                    else
                        status="fail"
                        note="json-parse-failed"
                    fi
                fi

                if [[ "$status" == "ok" ]] &&
                    ! grep -Eq '"schema_version"[[:space:]]*:[[:space:]]*1' "$tmp_snapshot"; then
                    status="fail"
                    note="schema-version-missing"
                fi

                if [[ "$status" == "ok" ]]; then
                    cp "$tmp_snapshot" "$latest"
                    if ((iteration == 1)); then
                        cp "$tmp_snapshot" "$first"
                    fi
                    rm -f "$stderr_file"
                fi
            fi
        else
            duration=$(($(date +%s) - started))
            bytes=0
            status="fail"
            note="helper-exit"
        fi

        printf '%s,%s,%s,%s,%s,%s\n' \
            "$iteration" "$(date +%s)" "$duration" "$status" "$bytes" "$note" >>"$csv"

        if [[ "$status" != "ok" ]]; then
            if [[ -f "$tmp_snapshot" ]]; then
                cp "$tmp_snapshot" "$smoke_dir/failed-$iteration.json"
            fi
            failures=$((failures + 1))
            warn "Helper smoke iteration $iteration failed: $note"
            break
        fi

        now="$(date +%s)"
        if ((now >= deadline)); then
            break
        fi

        local remaining=$((deadline - now))
        local sleep_for="$SMOKE_INTERVAL_SECONDS"
        if ((remaining < sleep_for)); then
            sleep_for="$remaining"
        fi
        if ((sleep_for > 0)); then
            sleep "$sleep_for"
        fi
    done

    rm -f "$tmp_snapshot"

    if ((failures > 0)); then
        SMOKE_RESULT="failed after $iteration iteration(s)"
        die "helper refresh smoke failed; see $csv"
    fi

    SMOKE_RESULT="passed: $iteration iteration(s)"
    log "Helper refresh smoke passed: $iteration iteration(s); data: $csv"
}

run_helper_stream_smoke() {
    local stream_dir="$OUT_DIR/helper-stream"
    local jsonl="$stream_dir/snapshots.jsonl"
    local latest="$stream_dir/latest.json"
    local samples="$stream_dir/process-samples.csv"
    local stderr_file="$stream_dir/stderr.log"
    local json_stderr="$stream_dir/jsonl-parse.stderr"
    local line_count
    local process_exited_early=0
    local wait_status=0
    local sample_count=0
    local deadline
    local pid

    if ((STREAM_SECONDS == 0)); then
        STREAM_RESULT="skipped"
        log "Skipping persistent helper stream smoke."
        return 0
    fi

    mkdir -p "$stream_dir"
    : >"$jsonl"
    : >"$stderr_file"
    printf 'unix_time,pid,rss_kb,vsz_kb,cpu_percent,mem_percent,elapsed\n' >"$samples"

    log "Running persistent helper stream for ${STREAM_SECONDS}s at ${STREAM_INTERVAL_MS}ms snapshot intervals..."
    "$HELPER" --stream-json --interval-ms "$STREAM_INTERVAL_MS" >"$jsonl" 2>"$stderr_file" &
    pid=$!
    deadline=$(($(date +%s) + STREAM_SECONDS))

    while :; do
        local now
        local ps_line

        now="$(date +%s)"
        if ! kill -0 "$pid" >/dev/null 2>&1; then
            wait "$pid" >/dev/null 2>&1 || wait_status=$?
            process_exited_early=1
            break
        fi

        ps_line="$(ps -p "$pid" -o rss=,vsz=,%cpu=,%mem=,etime= 2>/dev/null | awk '{$1=$1; print}' || true)"
        if [[ -n "$ps_line" ]]; then
            local rss=""
            local vsz=""
            local cpu=""
            local mem=""
            local elapsed=""

            read -r rss vsz cpu mem elapsed <<<"$ps_line"
            printf '%s,%s,%s,%s,%s,%s,%s\n' \
                "$now" "$pid" "$rss" "$vsz" "$cpu" "$mem" "$elapsed" >>"$samples"
            sample_count=$((sample_count + 1))
        fi

        if ((now >= deadline)); then
            break
        fi

        local remaining=$((deadline - now))
        local sleep_for="$STREAM_SAMPLE_INTERVAL_SECONDS"
        if ((remaining < sleep_for)); then
            sleep_for="$remaining"
        fi
        if ((sleep_for > 0)); then
            sleep "$sleep_for"
        fi
    done

    if ((process_exited_early == 0)); then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    fi

    line_count="$(wc -l <"$jsonl" | tr -d '[:space:]')"

    if ((process_exited_early == 1)); then
        STREAM_RESULT="failed: helper stream exited early with status $wait_status"
        die "persistent helper stream exited early; see $stderr_file"
    fi

    if [[ -z "$line_count" ]] || ((line_count == 0)); then
        STREAM_RESULT="failed: no streamed snapshots"
        die "persistent helper stream produced no snapshots; see $jsonl and $stderr_file"
    fi

    local json_status=0
    if validate_jsonl_file "$jsonl" "$json_stderr"; then
        rm -f "$json_stderr"
    else
        json_status=$?
        if ((json_status == 2)) &&
            grep -Eq '"schema_version"[[:space:]]*:[[:space:]]*1' "$jsonl"; then
            warn "No JSONL parser found; accepted helper stream using schema marker fallback."
        else
            STREAM_RESULT="failed: invalid streamed JSONL"
            die "persistent helper stream JSONL validation failed; see $json_stderr"
        fi
    fi

    tail -n 1 "$jsonl" >"$latest"
    STREAM_RESULT="passed: $line_count snapshot(s), $sample_count resource sample(s)"
    log "Persistent helper stream passed: $line_count snapshot(s), $sample_count resource sample(s); data: $stream_dir"
}

write_window_tool() {
    local tool_path="$1"

    cat >"$tool_path" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: window-tool OWNER list|id\n", stderr)
    exit(64)
}

let owner = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

func field(_ value: Any?) -> String {
    let text = String(describing: value ?? "")
    return text.replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
}

if mode == "list" {
    print("window_id\towner\tlayer\tx\ty\twidth\theight\tname")
}

for window in windows {
    let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
    guard ownerName == owner else {
        continue
    }

    let number = window[kCGWindowNumber as String] as? Int ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let name = window[kCGWindowName as String] as? String ?? ""
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    let width = bounds["Width"] as? Double ?? 0
    let height = bounds["Height"] as? Double ?? 0

    if mode == "id", layer == 0, width > 80, height > 80 {
        print(number)
        exit(0)
    }

    if mode == "list" {
        print("\(number)\t\(field(ownerName))\t\(layer)\t\(Int(x))\t\(Int(y))\t\(Int(width))\t\(Int(height))\t\(field(name))")
    }
}

exit(mode == "list" ? 0 : 1)
SWIFT
}

wait_for_app_process() {
    local process_name="$1"
    local deadline=$((SECONDS + LAUNCH_WAIT_SECONDS))

    while ((SECONDS < deadline)); do
        if pgrep -x "$process_name" >/dev/null 2>&1; then
            pgrep -x "$process_name" | head -n 1
            return 0
        fi
        sleep 1
    done

    return 1
}

set_window_size() {
    local width="$1"
    local height="$2"

    osascript - "$APP_PROCESS" "$width" "$height" <<'APPLESCRIPT'
on run argv
    set appName to item 1 of argv
    set targetWidth to (item 2 of argv) as integer
    set targetHeight to (item 3 of argv) as integer

    tell application "System Events"
        if not (exists process appName) then error "process is not running: " & appName
        tell process appName
            set frontmost to true
            repeat 20 times
                if (count of windows) > 0 then exit repeat
                delay 0.25
            end repeat
            if (count of windows) is 0 then error "process has no windows"
            tell window 1
                set position to {80, 80}
                set size to {targetWidth, targetHeight}
                delay 0.7
                set actualPosition to position
                set actualSize to size
                set windowName to name
            end tell
        end tell
    end tell

    return windowName & tab & item 1 of actualPosition & tab & item 2 of actualPosition & tab & item 1 of actualSize & tab & item 2 of actualSize
end run
APPLESCRIPT
}

request_main_window() {
    osascript - "$APP_PROCESS" <<'APPLESCRIPT'
on run argv
    set appName to item 1 of argv

    tell application appName to activate
    tell application "System Events"
        if not (exists process appName) then error "process is not running: " & appName
        tell process appName
            set frontmost to true
            repeat 20 times
                if (count of windows) > 0 then return "already-windowed"
                delay 0.25
            end repeat

            keystroke "n" using command down
            repeat 20 times
                if (count of windows) > 0 then return "opened-with-command-n"
                delay 0.25
            end repeat
        end tell
    end tell

    error "process has no windows after activation and Command-N"
end run
APPLESCRIPT
}

dump_accessibility_sample() {
    local output="$OUT_DIR/accessibility-elements.tsv"
    local stderr_file="$OUT_DIR/accessibility-elements.stderr"

    if osascript - "$APP_PROCESS" >"$output" 2>"$stderr_file" <<'APPLESCRIPT'
on run argv
    set appName to item 1 of argv
    tell application "System Events"
        if not (exists process appName) then error "process is not running: " & appName
        tell process appName
            set frontmost to true
            if (count of windows) is 0 then error "process has no windows"
            set rows to "index" & tab & "role" & tab & "subrole" & tab & "name" & tab & "description" & tab & "value"
            with timeout of 20 seconds
                set elementsToInspect to entire contents of window 1
                set maxItems to 160
                set itemCount to count of elementsToInspect
                if itemCount > maxItems then set itemCount to maxItems
                repeat with itemIndex from 1 to itemCount
                    set uiElement to item itemIndex of elementsToInspect
                    set rows to rows & linefeed & itemIndex & tab & my clean(my readAttribute(uiElement, "role")) & tab & my clean(my readAttribute(uiElement, "subrole")) & tab & my clean(my readAttribute(uiElement, "name")) & tab & my clean(my readAttribute(uiElement, "description")) & tab & my clean(my readAttribute(uiElement, "value"))
                end repeat
            end timeout
            return rows
        end tell
    end tell
end run

on readAttribute(uiElement, attributeName)
    try
        if attributeName is "role" then return role of uiElement
        if attributeName is "subrole" then return subrole of uiElement
        if attributeName is "name" then return name of uiElement
        if attributeName is "description" then return description of uiElement
        if attributeName is "value" then return value of uiElement
    on error
        return ""
    end try
    return ""
end readAttribute

on clean(valueText)
    set textValue to valueText as text
    set textValue to my replaceText(textValue, tab, " ")
    set textValue to my replaceText(textValue, linefeed, " ")
    return textValue
end clean

on replaceText(sourceText, searchText, replacementText)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to searchText
    set textChunks to text items of sourceText
    set AppleScript's text item delimiters to replacementText
    set replacedText to textChunks as text
    set AppleScript's text item delimiters to oldDelimiters
    return replacedText
end replaceText
APPLESCRIPT
    then
        ACCESSIBILITY_RESULT="sampled: $output"
        rm -f "$stderr_file"
        log "Wrote accessibility element sample: $output"
    else
        ACCESSIBILITY_RESULT="skipped: AppleScript accessibility dump failed"
        warn "Accessibility sample failed; see $stderr_file"
        if is_truthy "$STRICT_GUI"; then
            die "accessibility sample failed"
        fi
    fi
}

run_gui_audit() {
    local window_tool="$TMP_DIR/window-tool.swift"
    local screenshots_dir="$OUT_DIR/screenshots"
    local window_evidence="$OUT_DIR/window-evidence.tsv"
    local process_evidence="$OUT_DIR/process-evidence.txt"
    local pid=""

    if is_truthy "$SKIP_GUI"; then
        skip_gui "--no-gui or RUSTTOP_TAHOE_QA_SKIP_GUI=1 was set"
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        skip_gui "GUI audit requires macOS"
        return 0
    fi

    for command_name in open osascript screencapture swift pgrep ps; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            skip_gui "required GUI command '$command_name' was not found"
            return 0
        fi
    done

    if ! pgrep -x WindowServer >/dev/null 2>&1; then
        skip_gui "WindowServer is not running; likely a headless session"
        return 0
    fi

    write_gui_environment_evidence
    if ! gui_accessibility_enabled; then
        skip_gui "Accessibility control is disabled for this terminal/Codex session; enable Privacy & Security > Accessibility for the host terminal and see $OUT_DIR/accessibility-preflight.txt"
        return 0
    fi

    prepare_gui_defaults
    mkdir -p "$screenshots_dir"
    write_window_tool "$window_tool"

    if pgrep -x "$APP_PROCESS" >/dev/null 2>&1; then
        APP_WAS_RUNNING=1
        pid="$(pgrep -x "$APP_PROCESS" | head -n 1)"
        log "Using already-running $APP_PROCESS process: pid $pid"
        if ! open_app_for_gui_audit >"$OUT_DIR/open-reopen.stdout" 2>"$OUT_DIR/open-reopen.stderr"; then
            warn "Could not request an app reopen event; see $OUT_DIR/open-reopen.stderr"
        fi
    else
        log "Launching app bundle for GUI audit..."
        if ! open_app_for_gui_audit >"$OUT_DIR/open.stdout" 2>"$OUT_DIR/open.stderr"; then
            skip_gui "open failed; see $OUT_DIR/open.stderr"
            return 0
        fi
        if ! pid="$(wait_for_app_process "$APP_PROCESS")"; then
            skip_gui "app process '$APP_PROCESS' did not appear within ${LAUNCH_WAIT_SECONDS}s"
            return 0
        fi
        APP_LAUNCHED_BY_QA=1
        APP_LAUNCHED_PID="$pid"
        log "Launched $APP_PROCESS: pid $pid"
    fi

    ps -p "$pid" -o pid,ppid,%cpu,%mem,rss,vsz,etime,command >"$process_evidence" 2>&1 || true
    printf 'target_size\twindow_name\tx\ty\tactual_width\tactual_height\tscreenshot\n' >"$window_evidence"
    swift "$window_tool" "$APP_PROCESS" list >"$OUT_DIR/window-list-initial.tsv" 2>"$OUT_DIR/window-list-initial.stderr" || true
    if ! swift "$window_tool" "$APP_PROCESS" id >"$OUT_DIR/window-id-initial.txt" 2>"$OUT_DIR/window-id-initial.stderr"; then
        if request_main_window >"$OUT_DIR/window-open-attempt.txt" 2>"$OUT_DIR/window-open-attempt.stderr"; then
            log "Requested main window: $(cat "$OUT_DIR/window-open-attempt.txt")"
        else
            warn "Could not request a main window; see $OUT_DIR/window-open-attempt.stderr"
        fi
        swift "$window_tool" "$APP_PROCESS" list >"$OUT_DIR/window-list-after-open-attempt.tsv" 2>"$OUT_DIR/window-list-after-open-attempt.stderr" || true
    fi

    for size in $WINDOW_SIZES; do
        local width="${size%x*}"
        local height="${size#*x}"
        local actual
        local screenshot="$screenshots_dir/RustTopTahoe-$size.png"
        local window_id

        if [[ ! "$width" =~ ^[0-9]+$ || ! "$height" =~ ^[0-9]+$ || "$width" == "$size" ]]; then
            warn "Skipping invalid window size '$size'; expected WxH"
            continue
        fi

        if ! actual="$(set_window_size "$width" "$height" 2>"$OUT_DIR/window-set-$size.stderr")"; then
            skip_gui "AppleScript could not control the app window; grant Accessibility permission and see $OUT_DIR/window-set-$size.stderr"
            return 0
        fi

        swift "$window_tool" "$APP_PROCESS" list >"$OUT_DIR/window-list-$size.tsv" 2>"$OUT_DIR/window-list-$size.stderr" || true

        if window_id="$(swift "$window_tool" "$APP_PROCESS" id 2>"$OUT_DIR/window-id-$size.stderr")"; then
            if screencapture -x -l "$window_id" "$screenshot" >"$OUT_DIR/screencapture-$size.stdout" 2>"$OUT_DIR/screencapture-$size.stderr" &&
                [[ -s "$screenshot" ]]; then
                SCREENSHOT_COUNT=$((SCREENSHOT_COUNT + 1))
                log "Captured screenshot for $size: $screenshot"
            else
                warn "Screenshot capture failed for $size; grant Screen Recording permission and see $OUT_DIR/screencapture-$size.stderr"
                screenshot="not-captured"
                if is_truthy "$STRICT_GUI"; then
                    die "screenshot capture failed for $size"
                fi
            fi
        else
            warn "Could not resolve a window id for $size; see $OUT_DIR/window-id-$size.stderr"
            screenshot="not-captured"
            if is_truthy "$STRICT_GUI"; then
                die "could not resolve window id for $size"
            fi
        fi

        printf '%s\t%s\t%s\n' "$size" "$actual" "$screenshot" >>"$window_evidence"
    done

    dump_accessibility_sample

    if ((SCREENSHOT_COUNT > 0)); then
        GUI_RESULT="captured $SCREENSHOT_COUNT screenshot(s)"
    else
        GUI_RESULT="completed without screenshots"
        if is_truthy "$STRICT_GUI"; then
            die "GUI audit completed without screenshots"
        fi
    fi

    if is_truthy "$QUIT_APP" && ((APP_WAS_RUNNING == 0)); then
        osascript -e "tell application \"$APP_PROCESS\" to quit" >/dev/null 2>&1 || true
        log "Quit $APP_PROCESS after GUI audit."
    fi
}

clean_tsv_field() {
    local value="$1"

    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    printf '%s' "$value"
}

quote_command() {
    local arg
    local first=1

    for arg in "$@"; do
        if ((first == 0)); then
            printf ' '
        fi
        first=0
        printf '%q' "$arg"
    done
}

run_evidence_command() {
    local output="$1"
    local status
    shift

    {
        printf '$ '
        quote_command "$@"
        printf '\n\n'
    } >"$output"

    set +e
    "$@" >>"$output" 2>&1
    status=$?
    set -e

    {
        printf '\n'
        printf 'exit_status=%s\n' "$status"
    } >>"$output"

    return "$status"
}

run_evidence_command_in_directory() {
    local output="$1"
    local directory="$2"
    local status
    shift 2

    {
        printf '$ cd %q && ' "$directory"
        quote_command "$@"
        printf '\n\n'
    } >"$output"

    set +e
    (
        cd "$directory" &&
            "$@"
    ) >>"$output" 2>&1
    status=$?
    set -e

    {
        printf '\n'
        printf 'exit_status=%s\n' "$status"
    } >>"$output"

    return "$status"
}

record_release_check() {
    local check="$1"
    local status="$2"
    local exit_status="$3"
    local evidence="$4"
    local note="$5"

    RELEASE_CHECKS=$((RELEASE_CHECKS + 1))
    case "$status" in
        pass)
            RELEASE_PASSED=$((RELEASE_PASSED + 1))
            ;;
        not-ready)
            RELEASE_NOT_READY=$((RELEASE_NOT_READY + 1))
            ;;
        skipped)
            RELEASE_SKIPPED=$((RELEASE_SKIPPED + 1))
            ;;
        fail)
            RELEASE_FAILED=$((RELEASE_FAILED + 1))
            ;;
        *)
            RELEASE_FAILED=$((RELEASE_FAILED + 1))
            status="fail"
            note="unknown release check status was normalized to fail: $note"
            ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(clean_tsv_field "$check")" \
        "$(clean_tsv_field "$status")" \
        "$(clean_tsv_field "$exit_status")" \
        "$(clean_tsv_field "$evidence")" \
        "$(clean_tsv_field "$note")" >>"$RELEASE_DIR/checks.tsv"

    log "Release validation $status: $check - $note"
}

notary_credentials_configured() {
    [[ -n "$NOTARY_PROFILE" ]] ||
        [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_TEAM_ID" && -n "$NOTARY_PASSWORD" ]]
}

find_release_dmg() {
    if [[ -n "$DMG" ]]; then
        printf '%s\n' "$DMG"
        return 0
    fi

    if [[ -d "$REPO/dist" ]]; then
        find "$REPO/dist" \
            -maxdepth 1 \
            -name 'RustTopTahoe-*-macos.dmg' \
            -type f \
            -print 2>/dev/null |
            sort |
            tail -n 1
    fi
}

find_release_zip() {
    if [[ -d "$REPO/dist" ]]; then
        find "$REPO/dist" \
            -maxdepth 1 \
            -name 'RustTopTahoe-*-macos.zip' \
            -type f \
            -print 2>/dev/null |
            sort |
            tail -n 1
    fi
}

write_release_environment_evidence() {
    local resolved_dmg="$1"
    local evidence="$RELEASE_DIR/release-environment.txt"
    local signing_source="none"
    local notary_source="none"

    if [[ -n "${RUSTTOP_TAHOE_SIGN_IDENTITY:-}" ]]; then
        signing_source="RUSTTOP_TAHOE_SIGN_IDENTITY"
    elif [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
        signing_source="DEVELOPER_ID_APPLICATION"
    fi

    if [[ -n "$NOTARY_PROFILE" ]]; then
        notary_source="RUSTTOP_TAHOE_NOTARY_PROFILE"
    elif [[ -n "$NOTARY_APPLE_ID" || -n "$NOTARY_TEAM_ID" || -n "$NOTARY_PASSWORD" ]]; then
        notary_source="apple-id/team/password environment"
    fi

    {
        echo "timestamp_utc=$TIMESTAMP"
        echo "app=$APP"
        echo "helper=$HELPER"
        echo "dmg=${resolved_dmg:-not-configured}"
        echo
        echo "## signing credentials"
        echo "signing_identity_configured=$([[ -n "$SIGN_IDENTITY" ]] && echo yes || echo no)"
        echo "signing_identity_source=$signing_source"
        echo "signing_identity_is_adhoc=$([[ "$SIGN_IDENTITY" == "-" ]] && echo yes || echo no)"
        echo
        echo "## notary credentials"
        echo "notary_credentials_configured=$(notary_credentials_configured && echo yes || echo no)"
        echo "notary_credential_source=$notary_source"
        echo "notary_profile_configured=$([[ -n "$NOTARY_PROFILE" ]] && echo yes || echo no)"
        echo "notary_apple_id_configured=$([[ -n "$NOTARY_APPLE_ID" ]] && echo yes || echo no)"
        echo "notary_team_id_configured=$([[ -n "$NOTARY_TEAM_ID" ]] && echo yes || echo no)"
        echo "notary_password_configured=$([[ -n "$NOTARY_PASSWORD" ]] && echo yes || echo no)"
        echo
        echo "## release validation mode"
        echo "strict_release=$(is_truthy "$STRICT_RELEASE" && echo yes || echo no)"
        echo "skip_gui=$(is_truthy "$SKIP_GUI" && echo yes || echo no)"
    } >"$evidence"

    if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
        record_release_check \
            "release-signing-identity-env" \
            "pass" \
            "n/a" \
            "$evidence" \
            "Developer ID signing identity environment is configured via $signing_source"
    else
        record_release_check \
            "release-signing-identity-env" \
            "not-ready" \
            "n/a" \
            "$evidence" \
            "set RUSTTOP_TAHOE_SIGN_IDENTITY or DEVELOPER_ID_APPLICATION to produce a Developer ID signed release"
    fi

    if notary_credentials_configured; then
        record_release_check \
            "notary-credentials-env" \
            "pass" \
            "n/a" \
            "$evidence" \
            "notary credential environment is configured via $notary_source"
    else
        record_release_check \
            "notary-credentials-env" \
            "not-ready" \
            "n/a" \
            "$evidence" \
            "set RUSTTOP_TAHOE_NOTARY_PROFILE or Apple ID/team/password variables before submitting notarization"
    fi
}

run_codesign_validation() {
    local app_verified=0
    local app_developer_id=0
    local helper_verified=0
    local helper_developer_id=0
    local evidence
    local exit_status

    if ! command -v codesign >/dev/null 2>&1; then
        record_release_check \
            "codesign-command" \
            "skipped" \
            "n/a" \
            "" \
            "codesign is unavailable; run release signature validation on macOS"
        return 0
    fi

    evidence="$RELEASE_DIR/codesign-app-verify.txt"
    if run_evidence_command "$evidence" codesign --verify --deep --strict --verbose=2 "$APP"; then
        app_verified=1
        record_release_check \
            "signed-app-codesign-verify" \
            "pass" \
            "0" \
            "$evidence" \
            "app bundle signature verifies with nested code"
    else
        exit_status=$?
        record_release_check \
            "signed-app-codesign-verify" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "app bundle is unsigned, ad hoc, incomplete, or fails strict verification"
    fi

    evidence="$RELEASE_DIR/codesign-app-display.txt"
    if run_evidence_command "$evidence" codesign -dv --verbose=4 "$APP"; then
        record_release_check \
            "signed-app-codesign-display" \
            "pass" \
            "0" \
            "$evidence" \
            "app signature details captured"
        if grep -q '^Authority=Developer ID Application:' "$evidence"; then
            app_developer_id=1
            record_release_check \
                "signed-app-developer-id-authority" \
                "pass" \
                "0" \
                "$evidence" \
                "app is signed with a Developer ID Application authority"
        else
            record_release_check \
                "signed-app-developer-id-authority" \
                "not-ready" \
                "0" \
                "$evidence" \
                "app signature is present but does not show a Developer ID Application authority"
        fi
    else
        exit_status=$?
        record_release_check \
            "signed-app-codesign-display" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "app signature details could not be displayed"
    fi

    evidence="$RELEASE_DIR/codesign-helper-verify.txt"
    if run_evidence_command "$evidence" codesign --verify --strict --verbose=2 "$HELPER"; then
        helper_verified=1
        record_release_check \
            "embedded-helper-codesign-verify" \
            "pass" \
            "0" \
            "$evidence" \
            "embedded helper signature verifies"
    else
        exit_status=$?
        record_release_check \
            "embedded-helper-codesign-verify" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "embedded helper is unsigned, ad hoc, incomplete, or fails strict verification"
    fi

    evidence="$RELEASE_DIR/codesign-helper-display.txt"
    if run_evidence_command "$evidence" codesign -dv --verbose=4 "$HELPER"; then
        record_release_check \
            "embedded-helper-codesign-display" \
            "pass" \
            "0" \
            "$evidence" \
            "embedded helper signature details captured"
        if grep -q '^Authority=Developer ID Application:' "$evidence"; then
            helper_developer_id=1
            record_release_check \
                "embedded-helper-developer-id-authority" \
                "pass" \
                "0" \
                "$evidence" \
                "embedded helper is signed with a Developer ID Application authority"
        else
            record_release_check \
                "embedded-helper-developer-id-authority" \
                "not-ready" \
                "0" \
                "$evidence" \
                "embedded helper signature is present but does not show a Developer ID Application authority"
        fi
    else
        exit_status=$?
        record_release_check \
            "embedded-helper-codesign-display" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "embedded helper signature details could not be displayed"
    fi

    if ((app_verified == 1 && app_developer_id == 1 && helper_verified == 1 && helper_developer_id == 1)); then
        RELEASE_APP_SIGNATURE_READY=1
    fi
}

run_gatekeeper_validation() {
    local resolved_dmg="$1"
    local evidence
    local exit_status

    if ! command -v spctl >/dev/null 2>&1; then
        record_release_check \
            "spctl-command" \
            "skipped" \
            "n/a" \
            "" \
            "spctl is unavailable; run Gatekeeper validation on macOS"
        return 0
    fi

    evidence="$RELEASE_DIR/spctl-app-assess.txt"
    if run_evidence_command "$evidence" spctl --assess --type execute --verbose=4 "$APP"; then
        record_release_check \
            "gatekeeper-app-assessment" \
            "pass" \
            "0" \
            "$evidence" \
            "Gatekeeper accepts the app bundle for execution"
    else
        exit_status=$?
        record_release_check \
            "gatekeeper-app-assessment" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "Gatekeeper does not accept the app bundle for execution"
    fi

    evidence="$RELEASE_DIR/spctl-dmg-assess.txt"
    if [[ -z "$resolved_dmg" ]]; then
        record_release_check \
            "gatekeeper-dmg-assessment" \
            "not-ready" \
            "n/a" \
            "" \
            "no DMG path configured with --dmg/RUSTTOP_TAHOE_DMG or discovered under dist"
    elif [[ ! -f "$resolved_dmg" ]]; then
        record_release_check \
            "gatekeeper-dmg-assessment" \
            "not-ready" \
            "n/a" \
            "" \
            "DMG path does not exist: $resolved_dmg"
    elif run_evidence_command "$evidence" spctl --assess --type open --context context:primary-signature --verbose=4 "$resolved_dmg"; then
        record_release_check \
            "gatekeeper-dmg-assessment" \
            "pass" \
            "0" \
            "$evidence" \
            "Gatekeeper accepts the DMG primary signature"
    else
        exit_status=$?
        record_release_check \
            "gatekeeper-dmg-assessment" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "Gatekeeper does not accept the DMG primary signature"
    fi
}

run_stapler_validation() {
    local resolved_dmg="$1"
    local evidence
    local exit_status

    if ! command -v xcrun >/dev/null 2>&1; then
        record_release_check \
            "xcrun-command" \
            "skipped" \
            "n/a" \
            "" \
            "xcrun is unavailable; run stapler validation on macOS with Xcode command line tools"
        return 0
    fi

    evidence="$RELEASE_DIR/stapler-app-validate.txt"
    if run_evidence_command "$evidence" xcrun stapler validate "$APP"; then
        record_release_check \
            "stapled-app-validation" \
            "pass" \
            "0" \
            "$evidence" \
            "stapler validates a notarization ticket on the app bundle"
    else
        exit_status=$?
        record_release_check \
            "stapled-app-validation" \
            "not-ready" \
            "$exit_status" \
            "$evidence" \
            "app bundle does not have a stapled notarization ticket or stapler rejected it"
    fi

    if [[ -z "$resolved_dmg" ]]; then
        record_release_check \
            "stapled-dmg-validation" \
            "not-ready" \
            "n/a" \
            "" \
            "no DMG path configured with --dmg/RUSTTOP_TAHOE_DMG or discovered under dist"
    elif [[ ! -f "$resolved_dmg" ]]; then
        record_release_check \
            "stapled-dmg-validation" \
            "not-ready" \
            "n/a" \
            "" \
            "DMG path does not exist: $resolved_dmg"
    else
        evidence="$RELEASE_DIR/stapler-dmg-validate.txt"
        if run_evidence_command "$evidence" xcrun stapler validate "$resolved_dmg"; then
            record_release_check \
                "stapled-dmg-validation" \
                "pass" \
                "0" \
                "$evidence" \
                "stapler validates a notarization ticket on the DMG"
        else
            exit_status=$?
            record_release_check \
                "stapled-dmg-validation" \
                "not-ready" \
                "$exit_status" \
                "$evidence" \
                "DMG does not have a stapled notarization ticket or stapler rejected it"
        fi
    fi
}

run_dmg_image_validation() {
    local resolved_dmg="$1"
    local evidence
    local exit_status

    if [[ -z "$resolved_dmg" ]]; then
        record_release_check \
            "dmg-image-readable" \
            "not-ready" \
            "n/a" \
            "" \
            "no DMG path configured with --dmg/RUSTTOP_TAHOE_DMG or discovered under dist"
        return 0
    fi

    if [[ ! -f "$resolved_dmg" ]]; then
        record_release_check \
            "dmg-image-readable" \
            "not-ready" \
            "n/a" \
            "" \
            "DMG path does not exist: $resolved_dmg"
        return 0
    fi

    if ! command -v hdiutil >/dev/null 2>&1; then
        record_release_check \
            "dmg-image-readable" \
            "skipped" \
            "n/a" \
            "" \
            "hdiutil is unavailable; run DMG image validation on macOS"
        return 0
    fi

    evidence="$RELEASE_DIR/hdiutil-dmg-imageinfo.txt"
    if run_evidence_command "$evidence" hdiutil imageinfo "$resolved_dmg"; then
        record_release_check \
            "dmg-image-readable" \
            "pass" \
            "0" \
            "$evidence" \
            "hdiutil can read DMG metadata"
    else
        exit_status=$?
        record_release_check \
            "dmg-image-readable" \
            "fail" \
            "$exit_status" \
            "$evidence" \
            "hdiutil could not read the DMG image"
    fi
}

run_checksum_sidecar_validation() {
    local check="$1"
    local artifact="$2"
    local sidecar
    local evidence
    local exit_status

    if [[ -z "$artifact" ]]; then
        record_release_check \
            "$check" \
            "not-ready" \
            "n/a" \
            "" \
            "release artifact path is not configured or was not discovered"
        return 0
    fi

    sidecar="$artifact.sha256"
    evidence="$RELEASE_DIR/$check.txt"

    if [[ ! -f "$artifact" ]]; then
        record_release_check \
            "$check" \
            "not-ready" \
            "n/a" \
            "" \
            "release artifact does not exist: $artifact"
        return 0
    fi

    if [[ ! -f "$sidecar" ]]; then
        record_release_check \
            "$check" \
            "not-ready" \
            "n/a" \
            "" \
            "checksum sidecar does not exist: $sidecar"
        return 0
    fi

    if ! command -v shasum >/dev/null 2>&1; then
        record_release_check \
            "$check" \
            "skipped" \
            "n/a" \
            "" \
            "shasum is unavailable; checksum sidecar validation was skipped"
        return 0
    fi

    if run_evidence_command_in_directory \
        "$evidence" \
        "$(dirname "$artifact")" \
        shasum -a 256 -c "$(basename "$sidecar")"; then
        record_release_check \
            "$check" \
            "pass" \
            "0" \
            "$evidence" \
            "checksum sidecar matches $(basename "$artifact")"
    else
        exit_status=$?
        record_release_check \
            "$check" \
            "fail" \
            "$exit_status" \
            "$evidence" \
            "checksum sidecar does not match $(basename "$artifact")"
    fi
}

run_package_checksum_validation() {
    local resolved_dmg="$1"
    local resolved_zip

    resolved_zip="$(find_release_zip)"

    run_checksum_sidecar_validation "dmg-checksum-sidecar" "$resolved_dmg"
    run_checksum_sidecar_validation "zip-checksum-sidecar" "$resolved_zip"
}

run_signed_helper_export_validation() {
    local evidence="$RELEASE_DIR/signed-helper-export.txt"
    local snapshot="$RELEASE_DIR/signed-helper-snapshot.json"
    local json_stderr="$RELEASE_DIR/signed-helper-json-parse.stderr"
    local exit_status
    local json_status=0

    if ((RELEASE_APP_SIGNATURE_READY == 0)); then
        record_release_check \
            "signed-embedded-helper-export" \
            "not-ready" \
            "n/a" \
            "" \
            "app/helper signatures are not Developer ID verified, so signed helper export was not attempted"
        return 0
    fi

    if run_evidence_command "$evidence" "$HELPER" --export-json "$snapshot"; then
        if [[ ! -s "$snapshot" ]]; then
            record_release_check \
                "signed-embedded-helper-export" \
                "fail" \
                "0" \
                "$evidence" \
                "signed embedded helper ran but produced no JSON snapshot"
            return 0
        fi

        if validate_json_file "$snapshot" "$json_stderr"; then
            rm -f "$json_stderr"
            record_release_check \
                "signed-embedded-helper-export" \
                "pass" \
                "0" \
                "$evidence" \
                "signed embedded helper exports a valid schema-v1 JSON snapshot"
        else
            json_status=$?
            if ((json_status == 2)) &&
                grep -Eq '"schema_version"[[:space:]]*:[[:space:]]*1' "$snapshot"; then
                record_release_check \
                    "signed-embedded-helper-export" \
                    "pass" \
                    "0" \
                    "$evidence" \
                    "signed embedded helper exported schema-v1 JSON; parser unavailable, schema marker verified"
            else
                record_release_check \
                    "signed-embedded-helper-export" \
                    "fail" \
                    "$json_status" \
                    "$json_stderr" \
                    "signed embedded helper JSON snapshot did not parse as schema-v1 JSON"
            fi
        fi
    else
        exit_status=$?
        record_release_check \
            "signed-embedded-helper-export" \
            "fail" \
            "$exit_status" \
            "$evidence" \
            "signed embedded helper failed to export a snapshot"
    fi
}

run_signed_launch_validation() {
    local evidence="$RELEASE_DIR/signed-app-launch.txt"
    local pid=""
    local was_running=0
    local open_status

    if is_truthy "$SKIP_GUI"; then
        record_release_check \
            "signed-app-launch" \
            "skipped" \
            "n/a" \
            "" \
            "--no-gui or RUSTTOP_TAHOE_QA_SKIP_GUI=1 was set"
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        record_release_check \
            "signed-app-launch" \
            "skipped" \
            "n/a" \
            "" \
            "signed app launch evidence requires macOS"
        return 0
    fi

    if ((RELEASE_APP_SIGNATURE_READY == 0)); then
        record_release_check \
            "signed-app-launch" \
            "not-ready" \
            "n/a" \
            "" \
            "app/helper signatures are not Developer ID verified, so signed launch evidence was not attempted"
        return 0
    fi

    for command_name in open pgrep ps; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            record_release_check \
                "signed-app-launch" \
                "skipped" \
                "n/a" \
                "" \
                "required launch command '$command_name' was not found"
            return 0
        fi
    done

    if ! pgrep -x WindowServer >/dev/null 2>&1; then
        record_release_check \
            "signed-app-launch" \
            "skipped" \
            "n/a" \
            "" \
            "WindowServer is not running; likely a headless session"
        return 0
    fi

    {
        echo "signature_ready=yes"
        echo "app=$APP"
        echo "process=$APP_PROCESS"
        printf '$ '
        quote_command open "$APP"
        printf '\n\n'
    } >"$evidence"

    if pgrep -x "$APP_PROCESS" >/dev/null 2>&1; then
        was_running=1
        echo "process_state=already-running-before-open" >>"$evidence"
    else
        echo "process_state=not-running-before-open" >>"$evidence"
    fi

    set +e
    open "$APP" >>"$evidence" 2>&1
    open_status=$?
    set -e
    echo "open_exit_status=$open_status" >>"$evidence"

    if ((open_status != 0)); then
        record_release_check \
            "signed-app-launch" \
            "fail" \
            "$open_status" \
            "$evidence" \
            "open rejected the signed app bundle"
        return 0
    fi

    if pid="$(wait_for_app_process "$APP_PROCESS")"; then
        {
            echo "launched_pid=$pid"
            ps -p "$pid" -o pid,ppid,%cpu,%mem,rss,vsz,etime,command
        } >>"$evidence" 2>&1 || true
        record_release_check \
            "signed-app-launch" \
            "pass" \
            "0" \
            "$evidence" \
            "signed app bundle launches and process appears"
    else
        record_release_check \
            "signed-app-launch" \
            "fail" \
            "timeout" \
            "$evidence" \
            "signed app process did not appear within ${LAUNCH_WAIT_SECONDS}s"
    fi

    if is_truthy "$QUIT_APP" && ((was_running == 0)) && command -v osascript >/dev/null 2>&1; then
        osascript -e "tell application \"$APP_PROCESS\" to quit" >>"$evidence" 2>&1 || true
        echo "quit_after_launch=yes" >>"$evidence"
    fi
}

write_clean_machine_checklist() {
    local resolved_dmg="$1"
    local checklist_dmg="${resolved_dmg:-dist/RustTopTahoe-<version>-macos.dmg}"
    local checklist_dmg_name
    local install_app="/Applications/RustTopTahoe.app"

    checklist_dmg_name="$(basename "$checklist_dmg")"
    CLEAN_MACHINE_CHECKLIST="$RELEASE_DIR/clean-machine-install-checklist.md"

    cat >"$CLEAN_MACHINE_CHECKLIST" <<EOF
# RustTop Tahoe Clean-Machine Install Checklist

Use this on a clean macOS Tahoe machine or VM after producing signed,
notarized, and stapled release artifacts. Leave every evidence line empty until
the command has been run on that clean machine.

- [ ] Confirm the machine has no existing RustTop Tahoe app.
  - Command: \`rm -rf "$install_app"\`
  - Evidence:
- [ ] Transfer the DMG and checksum sidecar to the clean machine.
  - Artifact: \`$checklist_dmg\`
  - Checksum: \`$checklist_dmg.sha256\`
  - Evidence:
- [ ] Verify the DMG checksum.
  - Command: \`shasum -a 256 -c "$checklist_dmg_name.sha256"\`
  - Evidence:
- [ ] Verify the DMG is stapled.
  - Command: \`xcrun stapler validate "$checklist_dmg_name"\`
  - Evidence:
- [ ] Verify Gatekeeper accepts the DMG primary signature.
  - Command: \`spctl --assess --type open --context context:primary-signature --verbose=4 "$checklist_dmg_name"\`
  - Evidence:
- [ ] Mount the DMG read-only.
  - Command: \`hdiutil attach -readonly "$checklist_dmg_name"\`
  - Evidence:
- [ ] Install the app into Applications from the mounted image.
  - Command: \`ditto "/Volumes/RustTop Tahoe"/*.app "$install_app"\`
  - Evidence:
- [ ] Verify the installed app signature and nested code.
  - Command: \`codesign --verify --deep --strict --verbose=2 "$install_app"\`
  - Evidence:
- [ ] Verify the embedded helper signature directly.
  - Command: \`codesign --verify --strict --verbose=2 "$install_app/Contents/Resources/rust_top"\`
  - Evidence:
- [ ] Verify the installed app is stapled.
  - Command: \`xcrun stapler validate "$install_app"\`
  - Evidence:
- [ ] Verify Gatekeeper accepts the installed app for execution.
  - Command: \`spctl --assess --type execute --verbose=4 "$install_app"\`
  - Evidence:
- [ ] Launch the installed app from Finder or \`open\`.
  - Command: \`open "$install_app"\`
  - Evidence:
- [ ] Confirm the first launch has no unidentified-developer warning and the
      dashboard refreshes from the embedded helper.
  - Command: \`"$install_app/Contents/Resources/rust_top" --export-json /tmp/rusttop-tahoe-clean-machine.json\`
  - Evidence:
- [ ] Unmount the DMG.
  - Command: \`hdiutil detach "/Volumes/RustTop Tahoe"\`
  - Evidence:
EOF

    record_release_check \
        "clean-machine-install-checklist" \
        "pass" \
        "n/a" \
        "$CLEAN_MACHINE_CHECKLIST" \
        "clean-machine install evidence checklist generated"
}

run_release_validation() {
    local resolved_dmg

    if ! is_truthy "$RUN_RELEASE_VALIDATION"; then
        RELEASE_RESULT="skipped"
        log "Skipping release validation evidence."
        return 0
    fi

    RELEASE_DIR="$OUT_DIR/release-validation"
    mkdir -p "$RELEASE_DIR"
    printf 'check\tstatus\texit_status\tevidence\tnote\n' >"$RELEASE_DIR/checks.tsv"

    resolved_dmg="$(find_release_dmg)"

    log "Collecting release validation evidence..."
    write_release_environment_evidence "$resolved_dmg"
    run_codesign_validation
    run_signed_helper_export_validation
    run_gatekeeper_validation "$resolved_dmg"
    run_dmg_image_validation "$resolved_dmg"
    run_package_checksum_validation "$resolved_dmg"
    run_stapler_validation "$resolved_dmg"
    write_clean_machine_checklist "$resolved_dmg"
    run_signed_launch_validation

    if ((RELEASE_FAILED > 0)); then
        RELEASE_RESULT="failed: $RELEASE_FAILED failure(s), $RELEASE_NOT_READY not-ready, $RELEASE_PASSED passed, $RELEASE_SKIPPED skipped"
    elif ((RELEASE_NOT_READY > 0)); then
        RELEASE_RESULT="not-ready: $RELEASE_NOT_READY check(s) need signed/notarized release inputs, $RELEASE_PASSED passed, $RELEASE_SKIPPED skipped"
    else
        RELEASE_RESULT="passed: $RELEASE_PASSED check(s), $RELEASE_SKIPPED skipped"
    fi

    log "Release validation result: $RELEASE_RESULT"
}

write_summary() {
    {
        echo "# RustTop Tahoe QA/Audit Summary"
        echo
        echo "- Timestamp UTC: $TIMESTAMP"
        echo "- App bundle: \`$APP\`"
        echo "- Helper: \`$HELPER\`"
        echo "- Output directory: \`$OUT_DIR\`"
        echo "- Build: $(is_truthy "$RUN_BUILD" && echo "requested" || echo "skipped")"
        echo "- Helper smoke: $SMOKE_RESULT"
        echo "- Persistent helper stream: $STREAM_RESULT"
        echo "- GUI audit: $GUI_RESULT"
        echo "- Accessibility sample: $ACCESSIBILITY_RESULT"
        echo "- Release validation: $RELEASE_RESULT"
        echo
        echo "This harness creates repeatable audit artifacts. It does not prove"
        echo "manual visual QA, VoiceOver quality, performance stability, signing"
        echo "readiness, notarization acceptance, or clean-machine install behavior"
        echo "unless the release checks pass and the clean-machine checklist is"
        echo "completed on a separate Mac."
        echo
        echo "Key artifacts:"
        echo
        echo "- \`qa.log\`"
        echo "- \`app-evidence.txt\`"
        if [[ -n "$RELEASE_DIR" ]]; then
            echo "- \`release-validation/checks.tsv\` and command transcripts"
        fi
        if [[ -n "$CLEAN_MACHINE_CHECKLIST" ]]; then
            echo "- \`release-validation/clean-machine-install-checklist.md\`"
        fi
        echo "- \`helper-smoke/iterations.csv\`"
        echo "- \`helper-stream/snapshots.jsonl\` and \`helper-stream/process-samples.csv\` when stream smoke runs"
        echo "- \`window-evidence.tsv\` and \`window-list-*.tsv\` when GUI audit runs"
        echo "- \`screenshots/*.png\` when screenshot capture is permitted"
        echo "- \`accessibility-elements.tsv\` when Accessibility inspection is permitted"
    } >"$SUMMARY"

    log "Wrote summary: $SUMMARY"
}

log "RustTop Tahoe QA/audit harness"
log "Output directory: $OUT_DIR"
run_build
verify_app_artifacts
collect_static_evidence
run_helper_smoke
run_helper_stream_smoke
run_gui_audit
run_release_validation
write_summary
if is_truthy "$STRICT_RELEASE" && ((RELEASE_FAILED > 0 || RELEASE_NOT_READY > 0)); then
    die "release validation did not pass; see $RELEASE_DIR/checks.tsv"
fi
log "Done."
