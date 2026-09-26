import { injectManifest } from "workbox-build";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { rm } from "node:fs/promises";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectDirectory = resolve(scriptDirectory, "../..");
await Promise.all([
  rm(resolve(projectDirectory, "build/web/flutter_service_worker.js"), {
    force: true,
  }),
  rm(resolve(projectDirectory, "build/web/service-worker-src.js"), {
    force: true,
  }),
  rm(resolve(
    projectDirectory,
    "build/web/assets/packages/flutter_local_notifications_web/web/notifications_service_worker.js",
  ), { force: true }),
]);

const result = await injectManifest({
  swSrc: resolve(projectDirectory, "web/service-worker-src.js"),
  swDest: resolve(projectDirectory, "build/web/service-worker.js"),
  globDirectory: resolve(projectDirectory, "build/web"),
  globPatterns: [
    "**/*.{html,js,json,css,png,svg,woff,woff2,wasm}",
  ],
  // Flutter ships several alternative renderer bundles. Precache the regular
  // CanvasKit and Skwasm paths; fetching every variant delayed service worker
  // activation long enough to break push setup on a fresh Chrome install.
  globIgnores: [
    "service-worker.js",
    "canvaskit/chromium/**",
    "canvaskit/experimental_webparagraph/**",
    "canvaskit/wimp.*",
    "canvaskit/skwasm_heavy.*",
  ],
  maximumFileSizeToCacheInBytes: 12 * 1024 * 1024,
});

if (result.warnings.length) {
  for (const warning of result.warnings) console.warn(warning);
}
console.log(`Injected ${result.count} assets (${result.size} bytes)`);
