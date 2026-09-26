const CACHE_PREFIX = "forett-shuttle-";
const PRECACHE = self.__WB_MANIFEST;
const CACHE_VERSION = PRECACHE.map((entry) =>
  typeof entry === "string" ? entry : entry.revision || entry.url)
  .join("-").slice(0, 48);
const CACHE_NAME = `${CACHE_PREFIX}${CACHE_VERSION}`;
const REQUIRED = ["/", "/index.html", "/main.dart.js", "/flutter_bootstrap.js"];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    const urls = PRECACHE.map((entry) =>
      typeof entry === "string" ? entry : entry.url);
    // Workbox emits relative paths while REQUIRED uses root-relative paths.
    // Cache.addAll rejects the whole install if both forms resolve to one URL.
    const uniqueUrls = Array.from(new Set([...urls, ...REQUIRED]
      .map((url) => new URL(url, self.location.origin).href)));
    await cache.addAll(uniqueUrls);
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("message", (event) => {
  if (event.data === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" ||
      url.origin !== self.location.origin ||
      url.pathname.startsWith("/api/")) return;
  event.respondWith((async () => {
    const cached = await caches.match(event.request);
    if (cached) return cached;
    if (event.request.mode === "navigate") {
      const appShell = await caches.match("/");
      if (appShell) return appShell;
    }
    const response = await fetch(event.request);
    if (response.ok && response.type === "basic") {
      const cache = await caches.open(CACHE_NAME);
      await cache.put(event.request, response.clone());
    }
    return response;
  })());
});

self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }
  const reminderId = typeof payload.reminderId === "string"
    ? payload.reminderId : "shuttle";
  const direction = payload.direction === "beautyWorldToForett"
    ? "beautyWorldToForett" : "forettToBeautyWorld";
  event.waitUntil(self.registration.showNotification(
    typeof payload.title === "string" ? payload.title : "Forett Shuttle",
    {
      body: typeof payload.body === "string"
        ? payload.body : "Your shuttle departs in 5 minutes.",
      icon: "/icons/Icon-192.png",
      badge: "/icons/Icon-192.png",
      tag: `forett-reminder-${reminderId}`,
      data: { direction },
    },
  ));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const direction = event.notification.data?.direction ===
      "beautyWorldToForett" ? "beautyWorldToForett" : "forettToBeautyWorld";
  const target = `/?direction=${encodeURIComponent(direction)}`;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({
      type: "window",
      includeUncontrolled: true,
    });
    const existing = windows.find((client) =>
      new URL(client.url).origin === self.location.origin);
    if (existing) {
      await existing.navigate(target);
      return existing.focus();
    }
    return self.clients.openWindow(target);
  })());
});
