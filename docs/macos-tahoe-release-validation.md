# RustTop Tahoe Release Validation

This runbook validates signed, notarized, and stapled RustTop Tahoe release
artifacts without requiring Developer ID credentials for ordinary local QA runs.
It is evidence-first: unsigned local bundles should produce `not-ready`
findings, not a green release result.

The release validation harness lives in `scripts/qa-macos-tahoe.sh`. It records
command transcripts under `dist/tahoe-qa/<timestamp>/release-validation/` and
summarizes every release gate in `release-validation/checks.tsv`.

## Status Semantics

- `pass`: the command ran and the release gate accepted the artifact.
- `not-ready`: the expected release input is missing or rejected, such as an
  unsigned app, missing notary credentials, missing DMG, or absent staple.
- `skipped`: the local machine cannot run the check, usually because the host is
  not macOS, GUI access is disabled, or Apple command line tools are missing.
- `fail`: the command indicates a malformed artifact or an unexpected launch
  failure. Treat this as a release blocker.

Default runs are evidence-only so contributors can use the script without
Developer ID credentials. Add `--strict-release` when validating a real release
candidate and the script should exit nonzero for `not-ready` or `fail` checks.

## Local Evidence Run Without Credentials

Use this on development machines and CI jobs that do not have signing or notary
secrets. It should not claim the release is ready when credentials or signatures
are absent.

```bash
./scripts/qa-macos-tahoe.sh --no-gui
```

To reuse an existing bundle and skip helper smoke:

```bash
./scripts/qa-macos-tahoe.sh \
  --no-build \
  --no-smoke \
  --no-gui
```

Expected unsigned-result evidence:

- `release-validation/release-environment.txt` records whether signing and
  notary credential environment variables were present. It records password
  presence only, never the password value.
- `release-validation/codesign-app-verify.txt` records
  `codesign --verify --deep --strict --verbose=2 RustTopTahoe.app`.
- `release-validation/codesign-helper-verify.txt` records
  `codesign --verify --strict --verbose=2 RustTopTahoe.app/Contents/Resources/rust_top`.
- `release-validation/signed-helper-export.txt` records the embedded helper
  export command when the app and helper are Developer ID verified.
- `release-validation/dmg-checksum-sidecar.txt` and
  `release-validation/zip-checksum-sidecar.txt` verify packaged artifact
  checksum sidecars when those artifacts are present.
- `release-validation/checks.tsv` marks missing Developer ID signatures,
  missing notary credentials, missing DMG paths, and absent staples as
  `not-ready`.

## Signed And Notarized Candidate Run

After building with a Developer ID Application identity and notary credentials,
run the QA harness against the final app and DMG:

```bash
export RUSTTOP_TAHOE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export RUSTTOP_TAHOE_NOTARY_PROFILE="rusttop-tahoe"

RUSTTOP_TAHOE_NOTARIZE=1 \
  RUSTTOP_TAHOE_STAPLE=1 \
  RUSTTOP_TAHOE_PACKAGE_DMG=1 \
  ./scripts/build-macos-tahoe.sh

./scripts/qa-macos-tahoe.sh \
  --no-build \
  --strict-release \
  --dmg "dist/RustTopTahoe-$(awk -F '"' '/^version =/ { print $2; exit }' Cargo.toml)-macos.dmg"
```

Use `--no-gui` only when signed app launch evidence must be collected later on a
desktop Mac. With `--no-gui`, the release validation summary will mark
`signed-app-launch` as `skipped`.

## Explicit Release Checks

The harness records these commands when the local host has the required Apple
tools.

App signature and nested-code verification:

```bash
codesign --verify --deep --strict --verbose=2 RustTopTahoe.app
codesign -dv --verbose=4 RustTopTahoe.app
```

Embedded helper signature verification:

```bash
codesign --verify --strict --verbose=2 \
  RustTopTahoe.app/Contents/Resources/rust_top
codesign -dv --verbose=4 \
  RustTopTahoe.app/Contents/Resources/rust_top
RustTopTahoe.app/Contents/Resources/rust_top \
  --export-json /tmp/rusttop-tahoe-signed-helper.json
python3 -m json.tool /tmp/rusttop-tahoe-signed-helper.json >/dev/null
```

The release-ready signature evidence must show a `Developer ID Application`
authority for both the app and the embedded helper. The helper export check is
attempted only after that signature readiness is proven; unsigned local builds
should report it as `not-ready`.

Gatekeeper assessment:

```bash
spctl --assess --type execute --verbose=4 RustTopTahoe.app
spctl --assess --type open \
  --context context:primary-signature \
  --verbose=4 dist/RustTopTahoe-<version>-macos.dmg
```

Stapled notarization ticket verification:

```bash
xcrun stapler validate RustTopTahoe.app
xcrun stapler validate dist/RustTopTahoe-<version>-macos.dmg
```

DMG readability:

```bash
hdiutil imageinfo dist/RustTopTahoe-<version>-macos.dmg
```

Package integrity:

```bash
shasum -a 256 -c dist/RustTopTahoe-<version>-macos.dmg.sha256
shasum -a 256 -c dist/RustTopTahoe-<version>-macos.zip.sha256
```

Signed app launch evidence:

```bash
open RustTopTahoe.app
pgrep -x RustTopTahoe
ps -p <pid> -o pid,ppid,%cpu,%mem,rss,vsz,etime,command
```

The harness attempts signed app launch only after the app and embedded helper
have Developer ID signatures. A missing desktop session or `--no-gui` records a
`skipped` launch check.

## Clean-Machine Install Checklist

Each QA run writes
`release-validation/clean-machine-install-checklist.md`. Use that generated
file on a clean macOS Tahoe machine or VM after a release candidate has been
signed, notarized, stapled, and packaged.

Minimum manual evidence to collect on the clean machine:

- Verify the DMG checksum with `shasum -a 256 -c`.
- Verify the DMG staple with `xcrun stapler validate`.
- Verify the DMG Gatekeeper assessment with `spctl --assess --type open`.
- Mount the DMG read-only with `hdiutil attach -readonly`.
- Install `RustTopTahoe.app` into `/Applications`.
- Verify the installed app with
  `codesign --verify --deep --strict --verbose=2`.
- Verify the installed helper with
  `codesign --verify --strict --verbose=2`.
- Verify the installed app staple with `xcrun stapler validate`.
- Verify the installed app Gatekeeper assessment with
  `spctl --assess --type execute --verbose=4`.
- Launch the installed app and confirm the first launch reaches the dashboard
  or menu bar without a beachball/spinning wait, without requiring Force Quit,
  and without an unidentified-developer warning.
- Run the embedded helper export path from the installed app and confirm it
  writes valid JSON.

Do not substitute a development machine for this step. Gatekeeper, quarantine,
Launch Services, and prior local approvals can hide release defects.

## Release Readiness Bar

A Tahoe release candidate is ready for distribution only when:

- `release-validation/checks.tsv` has no `fail` rows.
- `release-validation/checks.tsv` has no `not-ready` rows when run with
  `--strict-release`.
- The signed app launch check passes on a logged-in macOS desktop session.
- The generated clean-machine checklist is completed on a separate clean Mac or
  VM.
- The checksum sidecars match the exact artifacts being distributed.

Keep the command transcripts with the release artifact notes so future failures
can be compared against concrete evidence instead of memory.
