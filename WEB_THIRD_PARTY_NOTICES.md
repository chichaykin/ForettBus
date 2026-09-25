# Web-specific third-party components

The generated Flutter build includes its complete machine-generated notice file
at `assets/NOTICES`. Keep that file in every deployment.

Web-specific additions introduced for this release:

| Component | Version | Purpose | License |
|---|---:|---|---|
| `@block65/webcrypto-web-push` | 2.0.0 | RFC 8291 payload encryption and VAPID headers in Workers | MIT |
| `workbox-build` | 7.4.1 | Build-time precache manifest injection | MIT |
| `url_launcher` | 6.3.2 | `mailto:` and `tel:` actions across Flutter platforms | BSD-3-Clause |

These packages are fixed by `worker/package-lock.json` and `pubspec.lock`.
Workbox is a build dependency and is not loaded from a CDN at runtime.
