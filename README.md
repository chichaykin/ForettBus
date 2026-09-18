# Forett Shuttle

Forett Shuttle is a Flutter app for checking the Forett Condo shuttle between
Forett and Beauty World, with live public-bus arrival predictions for routes 41
and 77.

The primary validation target is an Android Pixel device. The schedule uses the
`Asia/Singapore` time zone and runs Monday through Saturday.

## Features

- Shuttle countdown with the exact departure time.
- Direction-aware shuttle schedule for both routes.
- Next-service information after the last shuttle and on Sundays.
- Live ETA predictions for public buses 41 and 77.
- A clearly labelled scheduled timetable fallback when live data is unavailable.
- Optional five-minute shuttle reminders with Android notifications.
- Light and dark themes.

## Architecture

- `lib/schedule.dart` contains the shuttle timetable and Singapore time-zone
  calculations.
- `lib/notifications.dart` contains notification and exact-alarm handling.
- `lib/bus_arrivals.dart` contains the live ETA client and static fallback.
- `lib/screens/` contains the Home, Schedule, and Profile screens.
- `worker/` contains the Cloudflare Worker that authenticates requests and
  proxies the required LTA arrival data.

The Flutter app talks only to the HTTPS Worker. LTA credentials stay in
Cloudflare Worker secrets and are never shipped in the app.

## Run the Flutter app

Install Flutter and Android tooling, then install dependencies:

```bash
flutter pub get
```

For live arrivals, create a local environment file from the checked-in example:

```bash
cp .bus_api.env.example .bus_api.env
```

Set the Worker URL and the app key in `.bus_api.env`, then run or build with the
file:

```bash
flutter run --dart-define-from-file=.bus_api.env
flutter build apk --debug --dart-define-from-file=.bus_api.env
```

`.bus_api.env` is ignored by Git. Do not commit it, paste its values into source
files, or include it in an issue, screenshot, APK, or log.

Without the local define file, the app remains usable with the bundled scheduled
fallback for routes 41 and 77.

## Deploy the Worker

From `worker/`:

```bash
npm ci
npx wrangler login
npx wrangler secret put LTA_ACCOUNT_KEY
npx wrangler secret put APP_API_KEY
npx wrangler deploy
```

The Worker accepts only the supported `/v1/arrivals` endpoint, directions,
boarding stops, and routes. Configure secrets with Wrangler; never put secret
values in `wrangler.toml`, source code, tests, or Git history.

## Validation

```bash
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
cd worker && npm ci && npm test && npm run typecheck
```

For Android validation, build and install the regular debug APK after any
integration-test run so the device does not retain a test entrypoint:

```bash
flutter build apk --debug --dart-define-from-file=.bus_api.env
flutter install --debug -d <device-id>
```

## Security notes

- `APP_API_KEY` is an access-control credential for the Worker, not proof that
  an APK is trusted; mobile app values can be extracted.
- `LTA_ACCOUNT_KEY` must exist only as a Worker secret.
- Local environment files, signing keys, keystores, certificates, APKs, and
  generated build output are excluded by `.gitignore`.
- Before making a repository public, inspect both the working tree and Git
  history for credentials, private keys, personal data, and local configuration.
