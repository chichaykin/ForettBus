# Forett Shuttle Web deployment

No Cloudflare resource identifiers or secrets belong in Git. The checked-in
configuration is a template and deliberately cannot deploy unchanged.

The current engineering deployment is
`https://forett-shuttle-web-test.forett-shuttle-api.workers.dev`. Its ignored
local configuration uses the test D1 database and test Queue. Do not use this
address for the final resident QR code.

The production worker name is `forett-shuttle-web`, which gives the intended
resident origin `https://forett-shuttle-web.forett-shuttle-api.workers.dev`.
Confirm that exact origin in Wrangler's deployment output before producing any
resident-facing QR code. Treat it as permanent because browser storage and Web
Push subscriptions belong to the origin.

The exact production origin was deployed on 2026-09-26 with its own D1 database,
Queue and VAPID key pair. After installation on an iPhone, production push was
enabled. The first reminder was accepted by the push provider at 18:36:01
Singapore time for an 18:40 departure, and the user confirmed it appeared on
the locked iPhone while the PWA was closed.
The test origin remains available for engineering checks.

## One-time test environment

1. Build the browser files with `./tool/build_web.sh`.
2. In `worker/`, copy `wrangler.web.toml.example` to `wrangler.web.toml`.
3. Create a test D1 database and replace the placeholder database ID.
4. Create a test Queue and make its names match the producer and consumer
   entries in the configuration.
5. Verify that the `TRANSPORT` service binding targets the already deployed
   `forett-shuttle-api` Worker.
6. Apply `migrations/0001_web.sql` through Wrangler.
7. Configure Worker secrets without placing their values in shell history or
   files committed to Git:
   `WEB_TRANSPORT_API_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and
   `VAPID_SUBJECT`.
8. Deploy using `npm run deploy:web` and record the actual HTTPS URL in the
   release checklist.

Use independent D1, Queue, VAPID keys and secrets for production. Keep
`PUSH_ENABLED=false` until the test subscription has been received on an
installed iPhone PWA. Changing it back to `false` stops accepting new reminder
jobs and stops queue delivery while leaving schedules and transport data
available.

## Production environment

1. Complete the locked-iPhone push proof against the test origin.
2. Create a separate production D1 database and Queue. Copy
   `wrangler.web.production.toml.example` to the ignored
   `wrangler.web.production.toml`, then put the production D1 ID in that local
   file. Keep the test configuration and resources intact.
3. Apply `migrations/0001_web.sql` to production and set
   `WEB_TRANSPORT_API_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and
   `VAPID_SUBJECT` as production Worker secrets. Use a new production VAPID key
   pair; never copy the test pair.
4. Build with `./tool/build_web.sh` and deploy with
   `npm run deploy:web:production`. Confirm the resulting origin is the exact
   address above, then verify the home page, install/help/privacy pages,
   session creation, transport proxy and holiday endpoint.
5. Keep `PUSH_ENABLED=false` while checking HTTPS, API, pages and Home Screen
   installation at the production origin. Then change it to `true` in the
   ignored production config and deploy again. Create a new reminder from that
   installed PWA and confirm locked-iPhone delivery before announcing the site.
6. Record the URL and final checks in `WEB_RELEASE_CHECKLIST.md`. Generate the
   QR code and resident notice from that recorded URL only.

Production data is independent of the test environment. Never copy test
subscriptions or reminder rows to production. The anonymous session is created
for every browser before transport requests so rate limits apply per validated
installation rather than making residents on one Wi-Fi network share the
per-session limit. The IP limit remains as a separate abuse guard.

## Verification

- Open `/`, `/install.html`, `/help.html`, and `/privacy.html`.
- Confirm a missing asset and unknown `/api/*` route return 404.
- Inspect browser requests: Web requests use `/api` and contain no app Bearer
  key.
- Install from Safari, grant notifications from the installed app, schedule a
  future departure, close the PWA, and lock the phone.
- Confirm replacement and cancellation from a second app launch.
- Open the installed app online until the service worker has cached the app
  shell and local CanvasKit files. Close it, disconnect Wi-Fi and mobile data,
  then launch from the Home Screen icon. Home, the timetable, and saved local
  data should open; live arrivals and new push delivery require a connection.
- Exercise a shared-IP scenario with 100 simulated installations and verify
  transport and place-planning limits are applied per session.
- Run 100 due reminders through a test-only delivery stub; never target resident
  push endpoints for this load test.

The notification error code shown on Home and Profile identifies the failed
stage. `PUSH_WORKER_NOT_READY` or `PUSH_WORKER_INIT_FAILED` points to service
worker registration or activation; `PUSH_PERMISSION_*` is browser or system
permission; `PUSH_CONFIG_*` is VAPID configuration; `PUSH_SUBSCRIBE_FAILED` is
the browser push subscription; `PUSH_SESSION_FAILED` is anonymous session
creation; `PUSH_SAVE_FAILED` is server subscription storage; and
`REMINDER_SAVE_FAILED` is reminder storage. Check the browser console and
Cloudflare Worker logs for the exact underlying error. Do not ask residents to
send push endpoints, keys, cookies, or complete browser logs.

## Cost guard

Keep both web and transport Workers on the Free plan; do not enable a paid plan,
pay-as-you-go upgrade, or automatic billing transition. As of 2026-09-26,
Cloudflare documents a 100,000 Worker requests/day account limit and 10 ms CPU
per invocation on Workers Free ([Workers limits](https://developers.cloudflare.com/workers/platform/limits/)).
Queue message retention is 24 hours on Free ([Queues limits](https://developers.cloudflare.com/queues/platform/limits/)).
These limits are account-wide or shared by other account projects, so record
the Cloudflare Dashboard baseline before the 100-job test and review actual
request, CPU, D1, and Queue usage during the resident pilot. Repository
configuration cannot guarantee a $0 bill if the Cloudflare account enables
paid services elsewhere.

## Rollback and data operations

Cloudflare deployment versions provide the site rollback point. A schema
migration must be backward compatible with the immediately preceding Worker
version. Export D1 before a destructive migration. Completed, cancelled,
replaced and failed reminder rows are removed after seven days by the scheduled
handler; expired installations cascade to subscriptions and reminders.

Rotate the Web transport key together with the existing transport Worker's
accepted key window. Rotate VAPID keys only with an explicit re-subscription
plan because existing browser subscriptions are tied to their public key.
OneMap token renewal remains manual until server-side renewal credentials and
logic are explicitly implemented.
