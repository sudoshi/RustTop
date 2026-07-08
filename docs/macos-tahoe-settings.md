# RustTop Tahoe Settings And Migration

Tahoe v1 stores native app preferences in `UserDefaults` under the
`RustTopTahoe` app identity. It does not write RustTop's existing TOML config.

This keeps the native shell safe while it is a separate product bundle:

- The Rust helper remains the source of truth for collection and export.
- SwiftUI owns presentation preferences such as panel visibility, dashboard
  density, theme, accent, startup behavior, notification behavior, and helper
  override path.
- Existing RustTop TOML files are never rewritten by the Tahoe app.
- Users can still point Tahoe at a specific helper binary with the helper path
  override.

## Migration Policy

Tahoe v1 treats existing RustTop TOML as read-only context. The app should not
silently import, rewrite, or delete TOML settings because the current Rust/iced
app and the Tahoe shell can coexist.

Future migration can be added after the product identity is settled:

1. Add a read-only TOML summary in Settings that shows the discovered config
   path, parse status, and relevant collection defaults.
2. Offer an explicit one-time import for matching preferences such as refresh
   interval and panel visibility.
3. Keep the imported values in `UserDefaults`.
4. Add a reset action that clears Tahoe preferences without touching TOML.
5. Only add TOML writes if Tahoe replaces the Rust/iced app identity or the user
   explicitly opts into shared config.

## Recovery

Invalid helper paths, unsupported snapshot schema versions, and failed helper
execution should surface as native recovery UI. The user should be able to clear
the helper override without editing files by hand.
