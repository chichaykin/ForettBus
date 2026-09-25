# Forett Shuttle Web release checklist

Last updated: 2026-09-25 (Asia/Singapore)

## Build and automated checks

- [x] Flutter 3.44.6 / Dart 3.12.2 baseline recorded.
- [x] Dart formatting check passes.
- [x] `flutter analyze` passes.
- [x] 59 Flutter tests pass.
- [x] Standard JavaScript Web release builds without `.bus_api.env`.
- [x] Generated Web output contains no mobile/server secret-name markers.
- [x] Exactly one registered service worker handles offline resources and push.
- [x] 15 Worker tests pass, including D1 through Miniflare.
- [x] Worker TypeScript check passes.
- [x] Android debug APK with live API builds and installs with `adb install -r`.

## Published test environment

- [x] Test D1 database created in APAC and migration applied.
- [x] Test Queue, Service Binding, rate limits and one-minute cron configured.
- [x] Independent test VAPID pair stored as Worker secrets.
- [x] HTTPS test site deployed:
  `https://forett-shuttle-web-test.forett-shuttle-api.workers.dev`
- [x] Published Home, Push config, D1 session, holidays and live arrivals return
  successful responses.
- [x] Published reminder API passed create, ownership isolation, replacement,
  old-ID cancellation safety and final cancellation.
- [ ] Real push delivery to a closed Home Screen PWA on a locked iPhone.
- [ ] Permission denial/revocation and restart on iPhone.
- [ ] Offline launch and controlled update on iPhone/iPad.

## UI and regression

- [x] Narrow browser pass for Home, Schedule and Profile.
- [x] Web schedule hides photo import and retains CSV import.
- [x] Published site displays live public-bus results.
- [x] Android light and dark Profile screens visually checked on the connected
  Android emulator; the original light theme was restored.
- [ ] Current and previous major iOS versions.
- [ ] iPad and Android Chrome device pass.
- [ ] Real Pixel notification permission pass (only an emulator was available).

## Production and resident materials

- [x] Installation, Help and Privacy pages are included in the site.
- [x] Resident message and A4 notice copy are drafted.
- [x] Deployment, rollback, cleanup, key rotation and OneMap-token notes exist.
- [ ] Create independent production D1, Queue and VAPID keys after test push
  passes.
- [ ] Record the final production URL.
- [ ] Capture real iPhone screenshots without personal/test data.
- [ ] Generate final PNG/SVG QR code and A4 layout from the production URL.
- [ ] Run 100-job load test with test subscriptions.
- [ ] Complete 5–10 resident pilot for 3–5 days.
- [ ] Review Cloudflare account-wide free quotas during and after the pilot.

## Known limitations to publish

- Reminder delivery needs a network connection and its exact display time is
  controlled by iOS and notification settings.
- Saved cards, theme and imported schedule are local to one browser installation.
- Clearing site data removes those local settings.
- OneMap token renewal is manual.
- The test URL is for engineering validation and must not be printed as the
  residents' permanent QR code.
