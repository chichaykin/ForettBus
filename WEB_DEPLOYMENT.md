# Forett Shuttle Web deployment

No Cloudflare resource identifiers or secrets belong in Git. The checked-in
configuration is a template and deliberately cannot deploy unchanged.

The current engineering deployment is
`https://forett-shuttle-web-test.forett-shuttle-api.workers.dev`. Its ignored
local configuration uses the test D1 database and test Queue. Do not use this
address for the final resident QR code.

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

## Verification

- Open `/`, `/install.html`, `/help.html`, and `/privacy.html`.
- Confirm a missing asset and unknown `/api/*` route return 404.
- Inspect browser requests: Web requests use `/api` and contain no app Bearer
  key.
- Install from Safari, grant notifications from the installed app, schedule a
  future departure, close the PWA, and lock the phone.
- Confirm replacement and cancellation from a second app launch.
- Run the 100-job load scenario only with test subscriptions.

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
