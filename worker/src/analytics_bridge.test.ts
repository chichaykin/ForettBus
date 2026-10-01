import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";
import { describe, expect, it, vi } from "vitest";

interface AnalyticsBridge {
  enabled(): boolean;
  setEnabled(value: boolean): void;
  start(): void;
  track(name: string, parameters: string): void;
}

async function setup(initial: Record<string, string> = {}, online = false) {
  const values = new Map(Object.entries(initial));
  const timers = new Map<number, () => void>();
  let nextTimer = 1;
  const fetch = vi.fn(async (url: string) => {
    if (url === "/api/analytics/config") {
      return new Response(JSON.stringify({ enabled: true, measurementId: "G-TEST123" }));
    }
    if (url === "/api/session") return new Response(null, { status: 200 });
    if (url === "/api/analytics/events") return new Response(null, { status: 204 });
    throw new Error(`Unexpected request: ${url}`);
  });
  const window = {
    addEventListener: vi.fn(),
    forettAnalytics: undefined as AnalyticsBridge | undefined,
    gtag: undefined as undefined | ((...args: unknown[]) => void),
    dataLayer: undefined as undefined | unknown[],
  };
  const document = {
    visibilityState: "visible",
    cookie: "",
    addEventListener: vi.fn(),
    getElementById: () => null,
    createElement: () => ({ id: "", async: false, src: "", onload: () => {}, onerror: () => {}, remove: () => {} }),
    head: {
      appendChild: (script: { onload: () => void }) => {
        const original = window.gtag!;
        window.gtag = (...args: unknown[]) => {
          if (args[0] === "get") (args[3] as (value: string) => void)("123.456");
          else original(...args);
        };
        script.onload();
      },
    },
  };
  const source = await readFile(new URL("../../web/analytics_bridge.js", import.meta.url), "utf8");
  runInNewContext(source, {
    window,
    document,
    navigator: { onLine: online },
    location: {
      hostname: "forett-shuttle-web.forett-shuttle-api.workers.dev",
      origin: "https://forett-shuttle-web.forett-shuttle-api.workers.dev",
      pathname: "/",
    },
    localStorage: {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
      removeItem: (key: string) => values.delete(key),
    },
    crypto: { randomUUID: () => "event-id" },
    AbortController,
    fetch,
    setTimeout: (callback: () => void) => {
      const id = nextTimer++;
      timers.set(id, callback);
      return id;
    },
    clearTimeout: (id: number) => timers.delete(id),
    setInterval: () => 1,
  });
  return { bridge: window.forettAnalytics!, values, timers, fetch };
}

describe("web analytics bridge", () => {
  it("queues offline events without route details and clears them on opt-out", async () => {
    const { bridge, values, fetch } = await setup();
    bridge.start();
    bridge.track("trip_card_saved", JSON.stringify({ action: "created", address: "private place" }));
    const queue = JSON.parse(values.get("forett.analytics.queue.v1")!);
    expect(queue).toHaveLength(1);
    expect(queue[0].params).toEqual({ action: "created" });
    expect(fetch).not.toHaveBeenCalled();

    bridge.setEnabled(false);
    expect(bridge.enabled()).toBe(false);
    expect(values.has("forett.analytics.queue.v1")).toBe(false);
    bridge.track("reminder_set", "{}");
    expect(values.has("forett.analytics.queue.v1")).toBe(false);
  });

  it("keeps the Google tag off for a saved opt-out", async () => {
    const { bridge, timers, fetch } = await setup({ "forett.analytics.enabled.v1": "false" });
    bridge.start();
    expect(bridge.enabled()).toBe(false);
    expect(timers.size).toBe(0);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("records one visible app opening per Singapore day", async () => {
    const { bridge, values, timers } = await setup();
    bridge.start();
    expect(timers.size).toBe(1);
    const callback = timers.values().next().value;
    callback!();
    const queue = JSON.parse(values.get("forett.analytics.queue.v1")!);
    expect(queue).toHaveLength(1);
    expect(queue[0].name).toBe("app_open");
    expect(queue[0].params.engagement_time_msec).toBe(1000);
    bridge.start();
    expect(timers.size).toBe(1);
  });

  it("flushes a recent offline event through the same-origin Worker", async () => {
    const offline = {
      id: "offline-id", name: "app_open", params: { engagement_time_msec: 1000 },
      timestampMicros: Date.now() * 1000,
    };
    const { bridge, values, fetch } = await setup({
      "forett.analytics.queue.v1": JSON.stringify([offline]),
    }, true);
    bridge.start();
    await new Promise((resolve) => setImmediate(resolve));
    await new Promise((resolve) => setImmediate(resolve));
    const calls = fetch.mock.calls;
    expect(calls.map(([url]) => url)).toContain("/api/analytics/events");
    const eventCall = calls.find(([url]) => url === "/api/analytics/events")!;
    expect(JSON.parse(String((eventCall[1] as RequestInit).body))).toEqual({
      clientId: "123.456", events: [offline],
    });
    expect(JSON.parse(values.get("forett.analytics.queue.v1")!)).toEqual([]);
  });
});
