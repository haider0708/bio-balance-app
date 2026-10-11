# BioBalance app

The Flutter app for phones, tablets and the web console (French and English).

- `lib/app` — the router, the phone and tablet navigation, the web console shell.
- `lib/core` — the API client, the session, alerts (background check and iPhone push), drafts, files and the on-phone cache, the theme and shared widgets.
- `lib/features/<feature>` — each feature's models, repository and screens.
- `test` — widget tests against a fake server, screenshots for visual review, the contract test against a real API (`test/contract`); `integration_test` drives the real app on a device.
- `tool/brand` — renders every icon and store graphic from the vector leaf mark.

Commands: the [repository README](../../README.md). Building, signing and store assets: [mobile-release.md](../../docs/mobile-release.md).
