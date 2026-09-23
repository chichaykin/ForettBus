---
name: code-review
description: Review Forett Shuttle changes for regressions in shuttle timing, live arrival handling, notifications, Worker security, and Android state. Use for pull requests that affect Flutter, Worker, Android, schedules, or saved trips.
---

# Forett Shuttle code review

Review the diff for introduced, actionable regressions. Do not restate unrelated
existing debt. Read `AGENTS.md` for the complete product and validation
requirements.

## Time and timetable

- Preserve `BusSchedule.now()` and `Asia/Singapore` for every service-time
  calculation. The timetable operates Monday through Saturday.
- A direction changes its timetable and shuttle departure countdown. The
  countdown is the departure from that direction's origin, not the arrival.
- Keep Sunday and post-service states distinct. Do not present the next day's
  first departure as a service available today.
- When models or imports change, retain compatibility with saved timetable,
  settings, and trip-card data.

## Arrivals and routes

- Public-bus ETA is independent of the shuttle timetable and is an arrival at
  the boarding stop. Check `Live`, `Scheduled`, `Estimated`, stale, and
  no-data labels against their actual conditions.
- Only the supported 41/77 stops may use static fallback. Do not create an ETA
  for a custom stop or expose Worker or LTA implementation errors.
- Preserve request sharing, rate limits, and response invalidation when a user
  changes direction, card, or stop.
- A transfer is a change of bus. Walking is not a transfer; retain saved
  segment durations and the catchability calculation.

## Notifications and async UI

- Keep `NotificationService` initialization retryable and
  `activeReminder` as the shared reminder state.
- Do not remove Android notification or exact-alarm permissions and receivers.
- Flag StatefulWidget code that uses context or calls `setState` after an
  `await` without first confirming `mounted`.

## Worker and secrets

- Flutter calls only Worker HTTPS endpoints. The app API key stays in a dart
  define file; LTA and OneMap credentials stay only in Worker secrets.
- Bearer validation must happen before cache and upstream requests. Preserve
  documented endpoint compatibility and do not add paid API dependencies.

## Evidence

For each material finding, identify the changed code, affected user behavior,
and a test that demonstrates the regression. For UI, notification, Worker, or
persisted-data changes, verify that the relevant checks in `AGENTS.md` were
updated or run.
