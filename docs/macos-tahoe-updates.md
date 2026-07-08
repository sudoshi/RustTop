# RustTop Tahoe Updates And Distribution Strategy

Tahoe v1 uses manual downloads from release artifacts. Automatic updates should
not ship until signed and notarized Developer ID distribution is proven on a
clean Mac.

## Sparkle Decision

Sparkle is the preferred future update framework if RustTop Tahoe needs
automatic updates outside the Mac App Store.

Do not enable Sparkle until these prerequisites are true:

- The app and embedded helper are signed with Developer ID.
- The app and DMG are notarized and stapled.
- Release artifacts have stable versioning and SHA-256 sidecars.
- A signed Sparkle appcast can be hosted from a trusted release location.
- Rollback and minimum-version behavior are documented.

Until then, Tahoe should keep update behavior manual and explicit.

## Homebrew Cask Path

Homebrew cask distribution should follow, not precede, the signed/notarized
release path.

The cask should point at the versioned DMG or zip after the artifact is:

- Universal or intentionally scoped to the supported architecture.
- Signed and notarized.
- Verified by checksum.
- Installable on a clean Mac by dragging `RustTopTahoe.app` into
  `/Applications`.

## Release Order

1. Prove local unsigned build and packaging.
2. Prove Developer ID signing for app and helper.
3. Prove notarization and stapling for app and DMG.
4. Prove clean-Mac install and Gatekeeper launch.
5. Add Homebrew cask metadata.
6. Add Sparkle appcast only if automatic updates are desired.
