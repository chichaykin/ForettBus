(function () {
  "use strict";

  const productionHost = "forett-shuttle-web.forett-shuttle-api.workers.dev";
  const preferenceKey = "forett.analytics.enabled.v1";
  const queueKey = "forett.analytics.queue.v1";
  const openDayKey = "forett.analytics.open_day.v1";
  const maximumAgeMs = 72 * 60 * 60 * 1000;
  const maximumQueueLength = 100;
  const eventNames = new Set([
    "app_open",
    "screen_view",
    "reminder_set",
    "reminder_cancelled",
    "trip_card_saved",
    "trip_card_deleted",
  ]);

  let started = false;
  let measurementId = null;
  let tagLoaded = false;
  let pageViewSent = false;
  let configPending = null;
  let flushPending = null;
  let openTimer = null;
  let pendingRequest = null;
  let lastOpenDay = null;

  function readStorage(key) {
    try { return localStorage.getItem(key); } catch (_) { return undefined; }
  }

  function writeStorage(key, value) {
    try { localStorage.setItem(key, value); } catch (_) { /* Optional storage. */ }
  }

  function removeStorage(key) {
    try { localStorage.removeItem(key); } catch (_) { /* Optional storage. */ }
  }

  function enabled() {
    const saved = readStorage(preferenceKey);
    return saved !== undefined && saved !== "false";
  }

  function singaporeDay() {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Singapore", year: "numeric", month: "2-digit", day: "2-digit",
    }).format(new Date());
  }

  function readQueue() {
    try {
      const value = JSON.parse(readStorage(queueKey) || "[]");
      return Array.isArray(value) ? value : [];
    } catch (_) {
      return [];
    }
  }

  function freshEvents(events) {
    const cutoff = Date.now() - maximumAgeMs;
    return events.filter((event) =>
      event && typeof event.timestampMicros === "number" &&
      event.timestampMicros / 1000 >= cutoff && event.timestampMicros / 1000 <= Date.now() + 60_000 &&
      eventNames.has(event.name)
    ).slice(-maximumQueueLength);
  }

  function queueEvent(event) {
    writeStorage(queueKey, JSON.stringify(freshEvents([...readQueue(), event])));
  }

  function clearAnalyticsCookies() {
    for (const item of document.cookie.split(";")) {
      const name = item.trim().split("=")[0];
      if (name === "_ga" || name.startsWith("_ga_")) {
        document.cookie = `${name}=; Max-Age=0; Path=/; SameSite=Lax`;
      }
    }
  }

  function setEnabled(value) {
    writeStorage(preferenceKey, value ? "true" : "false");
    if (!value) {
      if (measurementId) window[`ga-disable-${measurementId}`] = true;
      if (pendingRequest) pendingRequest.abort();
      removeStorage(queueKey);
      removeStorage(openDayKey);
      lastOpenDay = null;
      clearAnalyticsCookies();
      return;
    }
    if (measurementId) window[`ga-disable-${measurementId}`] = false;
    if (started) {
      scheduleOpen();
      void ensureConfig();
      void flush();
    }
  }

  function track(name, parametersJson) {
    if (!started || !enabled() || !eventNames.has(name)) return;
    let parameters = {};
    try { parameters = JSON.parse(parametersJson || "{}"); } catch (_) { return; }
    if (!parameters || typeof parameters !== "object" || Array.isArray(parameters)) return;
    const safe = {};
    if (name === "screen_view" && ["Home", "Schedule", "Profile"].includes(parameters.screen_name)) {
      safe.screen_name = parameters.screen_name;
    }
    if (name === "trip_card_saved" && ["created", "updated"].includes(parameters.action)) {
      safe.action = parameters.action;
    }
    if (name === "app_open") safe.engagement_time_msec = 1000;
    const event = {
      id: crypto.randomUUID(),
      name,
      params: safe,
      timestampMicros: Date.now() * 1000,
    };
    if (tagLoaded && navigator.onLine) {
      window.gtag("event", name, safe);
    } else {
      queueEvent(event);
      if (navigator.onLine) void ensureConfig();
    }
  }

  function scheduleOpen() {
    if (!started || !enabled() || document.visibilityState !== "visible" || openTimer) return;
    if (lastOpenDay === singaporeDay() || readStorage(openDayKey) === singaporeDay()) return;
    openTimer = setTimeout(() => {
      openTimer = null;
      if (!enabled() || document.visibilityState !== "visible") return;
      const day = singaporeDay();
      if (lastOpenDay === day || readStorage(openDayKey) === day) return;
      lastOpenDay = day;
      writeStorage(openDayKey, day);
      track("app_open", "{}");
    }, 1000);
  }

  function cancelOpen() {
    if (openTimer) clearTimeout(openTimer);
    openTimer = null;
  }

  function sendPageView() {
    if (pageViewSent || !tagLoaded || !enabled()) return;
    pageViewSent = true;
    window.gtag("event", "page_view", {
      page_title: "Forett Shuttle",
      page_location: location.origin + location.pathname,
    });
  }

  function loadTag() {
    if (tagLoaded || document.getElementById("forett-ga4-tag") || !enabled()) return;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag("js", new Date());
    window.gtag("set", { page_location: location.origin + location.pathname });
    window.gtag("config", measurementId, {
      send_page_view: false,
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
    });
    const script = document.createElement("script");
    script.id = "forett-ga4-tag";
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`;
    script.onload = () => {
      tagLoaded = true;
      sendPageView();
      void flush();
    };
    script.onerror = () => script.remove();
    document.head.appendChild(script);
  }

  async function ensureConfig() {
    if (!enabled() || !navigator.onLine || location.hostname !== productionHost) return;
    if (measurementId) {
      if (tagLoaded) {
        sendPageView();
        void flush();
      } else loadTag();
      return;
    }
    if (configPending) return configPending;
    configPending = (async () => {
      try {
        const response = await fetch("/api/analytics/config", { cache: "no-store" });
        if (!response.ok || !enabled()) return;
        const config = await response.json();
        if (config.enabled !== true || !/^G-[A-Z0-9]+$/.test(config.measurementId)) return;
        measurementId = config.measurementId;
        loadTag();
      } catch (_) {
        // Retry on the next online event or visible app launch.
      } finally {
        configPending = null;
      }
    })();
    return configPending;
  }

  function getClientId() {
    return new Promise((resolve) => {
      const timeout = setTimeout(() => resolve(null), 5000);
      window.gtag("get", measurementId, "client_id", (value) => {
        clearTimeout(timeout);
        resolve(typeof value === "string" ? value : null);
      });
    });
  }

  async function flush() {
    if (flushPending || !tagLoaded || !enabled() || !navigator.onLine) return flushPending;
    flushPending = (async () => {
      try {
        let queue = freshEvents(readQueue());
        writeStorage(queueKey, JSON.stringify(queue));
        if (queue.length === 0) return;
        const clientId = await getClientId();
        if (!clientId || !enabled()) return;
        const session = await fetch("/api/session", { method: "POST", credentials: "same-origin" });
        if (!session.ok || !enabled()) return;
        while (queue.length > 0 && enabled()) {
          const batch = queue.slice(0, 25);
          pendingRequest = new AbortController();
          const response = await fetch("/api/analytics/events", {
            method: "POST",
            credentials: "same-origin",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ clientId, events: batch }),
            signal: pendingRequest.signal,
          });
          pendingRequest = null;
          if (!response.ok || !enabled()) return;
          const sentIds = new Set(batch.map((event) => event.id));
          queue = freshEvents(readQueue()).filter((event) => !sentIds.has(event.id));
          writeStorage(queueKey, JSON.stringify(queue));
        }
      } catch (_) {
        // Keep the queue for a later reconnection.
      } finally {
        pendingRequest = null;
        flushPending = null;
      }
    })();
    return flushPending;
  }

  function start() {
    if (started) return;
    started = true;
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") {
        scheduleOpen();
        void ensureConfig();
      } else cancelOpen();
    });
    window.addEventListener("online", () => { void ensureConfig(); void flush(); });
    setInterval(() => {
      scheduleOpen();
      if (document.visibilityState === "visible" && navigator.onLine) {
        void ensureConfig();
        void flush();
      }
    }, 60_000);
    scheduleOpen();
    void ensureConfig();
  }

  window.forettAnalytics = { enabled, setEnabled, start, track };
})();
