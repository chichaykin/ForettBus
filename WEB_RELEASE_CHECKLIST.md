# Forett Shuttle Web release checklist

Last updated: 2026-09-26 (Asia/Singapore)

## Build and automated checks

- [x] Flutter 3.44.6 / Dart 3.12.2 baseline recorded.
- [x] Dart formatting check passes.
- [x] `flutter analyze` passes.
- [x] 65 Flutter tests pass.
- [x] Standard JavaScript Web release builds without `.bus_api.env`.
- [x] Generated Web output contains no mobile/server secret-name markers.
- [x] Exactly one registered service worker handles offline resources and push.
- [x] Versioned JSON backup validation and restore state handling have unit/widget coverage for route cards, timetable, theme and main direction.
- [x] 21 Worker tests pass, including D1 through Miniflare, session protection,
  a 100-session concurrent shared-IP simulation, synchronous push subscription,
  and duplicate-free service worker installation.
- [x] Worker TypeScript check passes.
- [x] Standard Android debug APK with live API builds.
- [x] Isolated `.debug` package with live API installs and updates with `adb install -r`.
- [x] All 3 Pixel integration tests pass with `--no-uninstall` and mocked preferences; the standard debug APK was rebuilt after the integration run.

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
- [x] Local Worker tests verify transport is rejected without a valid anonymous installation session.
- [x] Local 100-installation simulation keeps ETA, plan, write, and read limits independent per session on one IP.
- [x] Local Miniflare test processes 100 queued reminders with an intercepted test push endpoint; it sends no notifications to Apple/FCM.
- [x] Deployed shared-IP test: 100 concurrent anonymous sessions returned 201,
  followed by 100 concurrent ETA requests that all returned 200.
- [x] Fixed duplicate cache URLs that prevented service worker installation;
  a fresh temporary Chrome profile on macOS now has one activated service
  worker and reports push readiness.
- [x] A real MacBook browser created a Web Push subscription; the test D1
  contains it, and the user confirmed notifications now work on Mac.
- [x] The installed iPhone PWA created a second subscription and displayed
  `Reminder Set`. The first 15:05 push failed three delivery attempts because
  Cloudflare Workers rejects `redirect: "error"` on outbound `fetch`.
- [x] Changed push delivery to `redirect: "manual"`, added a regression check
  to the 100-reminder test, and redeployed the test Worker. A new 15:30
  departure reminder was accepted by the push provider at 15:25:19 Singapore
  time on the first attempt; test D1 records `sent` with no error.
- [x] The user confirmed the notification appeared on the locked iPhone while
  the Home Screen PWA was closed. Opening it exposed a white startup screen;
  a branded `Loading…` shell and Forett launcher icons were deployed to the
  test origin. The production-origin PWA subsequently opened Home directly
  from a notification without a white screen.
- [ ] Permission denial/revocation and restart on iPhone.
- [ ] Offline launch on iPhone/iPad.

## UI and regression

- [x] Narrow browser pass for Home, Schedule and Profile.
- [x] Web schedule hides photo import and retains CSV import.
- [x] Published site displays live public-bus results.
- [x] Android light and dark Profile screens visually checked on the connected
  Android emulator; the original light theme was restored before these changes.
- [x] Updated backup/restore Profile UI visually checked on Pixel 8 Pro in light and dark themes using a temporary `com.forett.shuttle_bus.debug` package; the installed `com.forett.shuttle_bus` app was preserved.
- [x] Integration test confirms both backup controls appear in Profile and route cards render in light/dark themes.
- [ ] Current and previous major iOS versions.
- [ ] iPad and Android Chrome device pass.
- [ ] Real Pixel notification permission pass; Pixel 8 Pro was not connected
  for this release pass. Pixel 9a emulator integration tests passed.

## Production and resident materials

- [x] Installation, Help and Privacy pages are included in the site.
- [x] Resident message and A4 notice copy are drafted.
- [x] Deployment, rollback, cleanup, key rotation and OneMap-token notes exist.
- [x] Created independent production D1, Queue and VAPID keys after test push
  passed. Production IDs and secrets are outside Git.
- [x] Deployed production with `PUSH_ENABLED=false` at
  `https://forett-shuttle-web.forett-shuttle-api.workers.dev`. HTTPS pages,
  anonymous session creation, protected arrivals, holidays and disabled push
  configuration passed smoke checks.
- [x] Installed the production-origin PWA on iPhone with the Forett launcher
  icon and enabled production push. The first subscription and 18:40 departure
  reminder were recorded in production D1.
- [x] The production Worker sent the reminder at 18:36:01 Singapore time on its
  first attempt; D1 records `sent` without error. The user confirmed the
  notification appeared on the locked iPhone while the PWA was closed.
- [x] Tapping the production notification opened Home immediately without a
  white screen or Safari toolbar; a real iPhone screenshot confirms the Home
  layout and live public-bus arrivals.
- [x] Corrected offline startup: Flutter now loads CanvasKit from the app
  origin, the service worker precaches the regular and Chromium renderer
  bundles, and offline navigations with a direction query use the cached app
  shell. Fresh Chrome profiles opened Home offline on both published HTTPS
  origins after completing the online cache.
- [x] Home shows the supported 41/77 Scheduled fallback immediately while a
  live request is pending, including on a narrow screen with larger text.
- [x] Updated the reminder button to `Remind me (~5 min before)` because Web
  Push delivery depends on the network and iOS scheduling. The installed iPhone
  PWA picked up the update without reinstalling, and the user confirmed its
  reminder was preserved.
- [x] Recorded the exact production URL above. Do not distribute it by QR until
  the pilot is complete.
- [ ] Capture real iPhone screenshots without personal/test data.
- [ ] Generate final PNG/SVG QR code and A4 layout from the production URL.
- [ ] Run 100-job load test with test subscriptions.
- [ ] Complete 5–10 resident pilot for 3–5 days.
- [ ] Review Cloudflare account-wide free quotas during and after the pilot.
- [ ] Confirm the account is not on a paid/auto-upgrade plan and capture baseline usage before the 100-job test.

## Current release blockers (2026-09-26)

- Locked-screen delivery succeeded on both test and production origins. The
  production PWA has the Forett launcher icon; tapping the reminder opened Home
  directly. A controlled PWA update preserved the reminder and displayed the
  new button label on the installed iPhone app.
- The Play-signed Pixel 8 Pro app was previously preserved because the local
  debug signature differs. Pixel 9a emulator integration tests passed with mock
  preferences, and the ordinary live API debug APK was rebuilt and reinstalled
  with `adb install -r` afterward.
- The production URL has been verified; do not print a QR code until the
  resident pilot and remaining release checks are complete.

## Known limitations to publish

- Reminder delivery needs a network connection and its exact display time is
  controlled by iOS and notification settings.
- Cloudflare Workers Free currently documents 100,000 Worker requests per
  account per day and 10 ms CPU per invocation; account-wide usage still needs
  review before confirming the $0 operating budget.
- Saved cards, theme and imported schedule are local to one browser installation.
- Clearing site data removes those local settings.
- OneMap token renewal is manual.
- The test URL is for engineering validation and must not be printed as the
  residents' permanent QR code.
