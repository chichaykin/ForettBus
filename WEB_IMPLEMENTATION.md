# Forett Shuttle Web implementation log

This document is the hand-off record for the Flutter Web/PWA implementation.
It records what is present in the repository; device and production checks are
only marked complete after they have actually run.

## Baseline

- Starting revision: `f8f1b18`
- Node.js: `v24.18.0`
- npm: `11.16.0`
- Flutter `3.44.6`, Dart `3.12.2`.
- Starting worktree: clean.

## Progress

| Stage | Implementation | Local verification | Device/deployment |
|---|---|---|---|
| 0. Baseline and journal | Complete | Complete | Cloudflare, Pixel and iPhone access not established |
| 1. Platform services and first Web build | Complete | Release build and Flutter tests pass | Android/iPhone regression pending |
| 2. Shared transport configuration | Complete | Native/Web configuration tests pass | Published proxy pending |
| 3. Web Worker and API proxy | Complete | Typecheck, routing tests and Miniflare D1 pass | Test deployment and smoke test pass |
| 4. iPhone Web Push proof | Pending | N/A | Requires a real iPhone and deployed HTTPS origin |
| 5. Sessions and reminders | Complete in source | Published create/isolate/replace/cancel flow passes | Push delivery pending |
| 6. Flutter notification integration | Complete in source | Facade and state tests pass | Permission/delivery pending |
| 7. PWA, offline mode and UI | Complete in source | Release build and narrow browser visual pass | Offline/update pass on devices pending |
| 8. Release materials | Partial | Install, Help, Privacy, copy and operations docs present | Requires final URL and iPhone screenshots for QR/A4 |

## Intended commands

```bash
./tool/build_web.sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
cd worker && npm ci && npm test && npm run typecheck
```

The Android integration test and restoration build remain governed by
`AGENTS.md`; do not run the test without preserving device settings and using
`--no-uninstall`.

## Secrets and deployment resources

The browser build must not contain `APP_API_KEY`, `LTA_ACCOUNT_KEY`,
`ONEMAP_TOKEN`, the VAPID private key, D1 identifiers, or Queue identifiers.
Deployment configuration committed to the repository is a template. Real
resource IDs and secrets are supplied through Cloudflare configuration and
Worker secrets.

## Known external checks

- Web Push delivery while the installed PWA is closed and the iPhone is locked.
- Current and previous major iOS release, iPad, and Android Chrome.
- Cloudflare Free plan quotas for the account and the final `workers.dev` URL.
- Pilot with 5–10 residents for 3–5 days.

Test deployment: `https://forett-shuttle-web-test.forett-shuttle-api.workers.dev`.
It is an engineering origin, not the final resident QR target.

## Last verification

- `dart format --output=none --set-exit-if-changed lib test integration_test`: passed.
- `flutter analyze`: passed with no issues.
- `flutter test`: 59 tests passed.
- `npm test`: 15 tests passed, including local D1 through Miniflare.
- `npm run typecheck`: passed.
- `./tool/build_web.sh`: passed; 30 application assets injected into the
  offline service worker, with the plugin's second notification worker removed.
- Release artifact scan found no mobile/server secret-name markers.
- Local narrow-browser visual pass: Home, Schedule and Profile rendered;
  photo import is absent on Web and CSV import remains available.
- Published HTTPS smoke test: static app, Push config, D1 session, reminder
  ownership isolation/replacement/cancellation, holidays and live ETA passed.
- Android debug APK built with live API, installed with `adb install -r`, and
  Home/Profile were visually checked in light and dark themes on the available
  Android emulator.
