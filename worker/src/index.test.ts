import { afterEach, describe, expect, it, vi } from "vitest";

import { handleRequest, isAuthorized, normalizeLta } from "./index";

afterEach(() => vi.unstubAllGlobals());

describe("worker authorization", () => {
  const env = { APP_API_KEY: "current", APP_API_KEY_PREVIOUS: "previous" };

  it("accepts current and previous keys only as bearer tokens", () => {
    expect(isAuthorized(new Request("https://example.test"), env)).toBe(false);
    expect(
      isAuthorized(
        new Request("https://example.test", {
          headers: { Authorization: "Bearer current" },
        }),
        env,
      ),
    ).toBe(true);
    expect(
      isAuthorized(
        new Request("https://example.test", {
          headers: { Authorization: "Bearer previous" },
        }),
        env,
      ),
    ).toBe(true);
    expect(
      isAuthorized(
        new Request("https://example.test", {
          headers: { Authorization: "Bearer stranger" },
        }),
        env,
      ),
    ).toBe(false);
  });
});

describe("worker request handling", () => {
  it("rejects unknown paths", async () => {
    const response = await handleRequest(
      new Request("https://example.test/not-the-api"),
      { APP_API_KEY: "current" },
    );

    expect(response.status).toBe(404);
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("rejects invalid auth before reading cache or calling LTA", async () => {
    const cacheMatch = vi.fn();
    const fetchMock = vi.fn();
    vi.stubGlobal("caches", { default: { match: cacheMatch } });
    vi.stubGlobal("fetch", fetchMock);

    const response = await handleRequest(
      new Request(
        "https://example.test/v1/arrivals?direction=forettToBeautyWorld",
      ),
      { APP_API_KEY: "current", LTA_ACCOUNT_KEY: "lta-key" },
    );

    expect(response.status).toBe(401);
    expect(cacheMatch).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("fetches, normalizes, and caches an authorized response", async () => {
    const cacheMatch = vi.fn().mockResolvedValue(undefined);
    const cachePut = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("caches", {
      default: { match: cacheMatch, put: cachePut },
    });
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            Services: [
              {
                ServiceNo: "41",
                NextBus: {
                  EstimatedArrival: "2026-09-18T10:05:00+08:00",
                  Monitored: 1,
                },
              },
            ],
          }),
          { status: 200 },
        ),
      ),
    );

    const response = await handleRequest(
      new Request(
        "https://example.test/v1/arrivals?direction=forettToBeautyWorld",
        { headers: { Authorization: "Bearer current" } },
      ),
      { APP_API_KEY: "current", LTA_ACCOUNT_KEY: "lta-key" },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { routes: unknown[] };
    expect(body.routes).toHaveLength(1);
    expect(cachePut).toHaveBeenCalledOnce();
  });

  it("supports arbitrary configured stop arrivals while filtering services", async () => {
    const cacheMatch = vi.fn().mockResolvedValue(undefined);
    const cachePut = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("caches", { default: { match: cacheMatch, put: cachePut } });
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            Services: [
              { ServiceNo: "963", NextBus: { EstimatedArrival: "2026-09-18T10:05:00+08:00", Monitored: 1 } },
              { ServiceNo: "41", NextBus: { EstimatedArrival: "2026-09-18T10:06:00+08:00", Monitored: 1 } },
            ],
          }),
          { status: 200 },
        ),
      ),
    );

    const response = await handleRequest(
      new Request("https://example.test/v1/arrivals?stopCode=18049&services=963", {
        headers: { Authorization: "Bearer current" },
      }),
      { APP_API_KEY: "current", LTA_ACCOUNT_KEY: "lta-key" },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { stop: { code: string }; routes: Array<{ serviceNo: string }> };
    expect(body.stop.code).toBe("18049");
    expect(body.routes.map((route) => route.serviceNo)).toEqual(["963"]);
  });
});

describe("LTA response normalization", () => {
  it("keeps only the configured services and three ETA fields", () => {
    const result = normalizeLta(
      {
        Services: [
          {
            ServiceNo: "41",
            NextBus: { EstimatedArrival: "2026-09-18T10:05:00+08:00", Monitored: 1 },
            NextBus2: { EstimatedArrival: "2026-09-18T10:15:00+08:00", Monitored: 0 },
            NextBus3: { EstimatedArrival: "" },
          },
          { ServiceNo: "999", NextBus: { EstimatedArrival: "2026-09-18T10:06:00+08:00" } },
        ],
      },
      "forettToBeautyWorld",
      { code: "42221", name: "Forett @ Bt Timah" },
    );

    expect(result.routes).toHaveLength(1);
    expect(result.routes[0].serviceNo).toBe("41");
    expect(result.routes[0].arrivals).toEqual([
      { estimatedArrival: "2026-09-18T10:05:00+08:00", monitored: true },
      { estimatedArrival: "2026-09-18T10:15:00+08:00", monitored: false },
    ]);
  });
});

describe("trip stop arrivals", () => {
  it("returns every service for a stop when the client requests a shared snapshot", async () => {
    vi.stubGlobal("caches", { default: { match: vi.fn(), put: vi.fn() } });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ Services: [
      { ServiceNo: "963", NextBus: { EstimatedArrival: "2026-09-19T14:00:00+08:00", Monitored: 1 } },
      { ServiceNo: "188", NextBus: { EstimatedArrival: "2026-09-19T14:05:00+08:00", Monitored: 1 } },
    ] }))));
    const response = await handleRequest(new Request("https://example.test/v1/arrivals?stopCode=18131", { headers: { Authorization: "Bearer test" } }), { APP_API_KEY: "test", LTA_ACCOUNT_KEY: "test" });
    const result = await response.json() as { routes: Array<{ serviceNo: string }> };
    expect(response.status).toBe(200);
    expect(result.routes.map((route) => route.serviceNo)).toEqual(["188", "963"]);
  });

  it("rejects invalid stop codes before cache and upstream access", async () => {
    const cacheMatch = vi.fn();
    const upstream = vi.fn();
    vi.stubGlobal("caches", { default: { match: cacheMatch } });
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(new Request("https://example.test/v1/arrivals?stopCode=SciencePk", { headers: { Authorization: "Bearer test" } }), { APP_API_KEY: "test" });
    expect(response.status).toBe(400);
    expect(cacheMatch).not.toHaveBeenCalled();
    expect(upstream).not.toHaveBeenCalled();
  });
});
