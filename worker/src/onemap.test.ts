import { afterEach, describe, expect, it, vi } from "vitest";

import { handleRequest } from "./index";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

const credentials = () => ({
  APP_API_KEY: "test",
  ONEMAP_EMAIL: "administrator@example.test",
  ONEMAP_PASSWORD: "test-password",
});
const request = () => new Request("https://example.test/v1/stops/search?q=138498", {
  headers: { Authorization: "Bearer test" },
});
const places = () => Response.json({ results: [{ SEARCHVAL: "MEDIA CLOSE" }] });
const token = (value = "test-token", expiresAt = Date.now() + 3 * 86_400_000) =>
  Response.json({ access_token: value, expiry_timestamp: String(expiresAt / 1_000) });

describe("OneMap authentication", () => {
  it("authenticates with server credentials and reuses the token", async () => {
    const env = credentials();
    const upstream = vi.fn()
      .mockResolvedValueOnce(token())
      .mockResolvedValueOnce(places())
      .mockResolvedValueOnce(places());
    vi.stubGlobal("fetch", upstream);

    expect((await handleRequest(request(), env)).status).toBe(200);
    expect((await handleRequest(request(), env)).status).toBe(200);
    expect(upstream).toHaveBeenCalledTimes(3);
    expect(upstream.mock.calls[0][0]).toBe("https://www.onemap.gov.sg/api/auth/post/getToken");
    expect(JSON.parse(upstream.mock.calls[0][1].body)).toEqual({
      email: env.ONEMAP_EMAIL, password: env.ONEMAP_PASSWORD,
    });
    expect(upstream.mock.calls[1][1].headers.Authorization).toBe("test-token");
    expect(upstream.mock.calls[2][1].headers.Authorization).toBe("test-token");
  });

  it("refreshes on demand within a minute of the expiry timestamp", async () => {
    vi.useFakeTimers();
    const env = credentials();
    const upstream = vi.fn()
      .mockResolvedValueOnce(token("first", Date.now() + 120_000))
      .mockResolvedValueOnce(places());
    vi.stubGlobal("fetch", upstream);
    await handleRequest(request(), env);
    vi.setSystemTime(Date.now() + 61_000);
    upstream.mockResolvedValueOnce(token("second")).mockResolvedValueOnce(places());
    expect((await handleRequest(request(), env)).status).toBe(200);
    expect(upstream.mock.calls[3][1].headers.Authorization).toBe("second");
  });

  it("combines concurrent authentication in the same instance", async () => {
    const env = credentials();
    const upstream = vi.fn()
      .mockResolvedValueOnce(token())
      .mockImplementation(async () => places());
    vi.stubGlobal("fetch", upstream);
    const responses = await Promise.all([
      handleRequest(request(), env), handleRequest(request(), env),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(upstream).toHaveBeenCalledTimes(3);
  });

  it.each([401, 403, 200])("renews and retries an authentication rejection (HTTP %s)", async (status) => {
    const upstream = vi.fn()
      .mockResolvedValueOnce(token("first"))
      .mockResolvedValueOnce(Response.json({ error: "Authentication token expired." }, { status }))
      .mockResolvedValueOnce(token("second"))
      .mockResolvedValueOnce(places());
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(request(), credentials());
    expect(response.status).toBe(200);
    expect(upstream).toHaveBeenCalledTimes(4);
    expect(upstream.mock.calls[3][1].headers.Authorization).toBe("second");
    expect(upstream.mock.calls[1][1].signal).toBe(upstream.mock.calls[3][1].signal);
    expect(upstream.mock.calls[0][1].signal).not.toBe(upstream.mock.calls[3][1].signal);
    expect(upstream.mock.calls[2][1].signal).not.toBe(upstream.mock.calls[3][1].signal);
  });

  it("keeps shared authentication alive when its first caller times out", async () => {
    const first = new AbortController();
    const authentication = new AbortController();
    const second = new AbortController();
    vi.spyOn(AbortSignal, "timeout")
      .mockReturnValueOnce(first.signal)
      .mockReturnValueOnce(authentication.signal)
      .mockReturnValueOnce(second.signal);
    let finishAuthentication!: (response: Response) => void;
    const pending = new Promise<Response>((resolve) => { finishAuthentication = resolve; });
    const upstream = vi.fn()
      .mockImplementationOnce(async (_url, options) => {
        await pending;
        options.signal.throwIfAborted();
        return token();
      })
      .mockImplementation(async (_url, options) => {
        options.signal.throwIfAborted();
        return places();
      });
    vi.stubGlobal("fetch", upstream);
    const env = credentials();
    const firstResponse = handleRequest(request(), env);
    const secondResponse = handleRequest(request(), env);
    first.abort();
    finishAuthentication(token());

    expect((await firstResponse).status).toBe(502);
    expect((await secondResponse).status).toBe(200);
    expect(authentication.signal.aborted).toBe(false);
    expect(upstream).toHaveBeenCalledTimes(3);
  });

  it("does not retry indefinitely or expose upstream errors", async () => {
    const upstream = vi.fn()
      .mockResolvedValueOnce(token("first"))
      .mockResolvedValueOnce(Response.json({ error: "Authentication token expired." }))
      .mockResolvedValueOnce(token("second"))
      .mockResolvedValueOnce(Response.json({ error: "Authentication token expired." }));
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(request(), credentials());
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "Place search unavailable" });
    expect(upstream).toHaveBeenCalledTimes(4);
  });

  it("preserves manually configured token support without authentication calls", async () => {
    const upstream = vi.fn().mockResolvedValueOnce(places());
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(request(), { APP_API_KEY: "test", ONEMAP_TOKEN: "manual" });
    expect(response.status).toBe(200);
    expect(upstream).toHaveBeenCalledOnce();
    expect(upstream.mock.calls[0][1].headers.Authorization).toBe("manual");
  });

  it("treats an HTTP 200 error as a failure even when it contains results", async () => {
    const upstream = vi.fn().mockResolvedValueOnce(Response.json({
      error: "Authentication token expired.", results: [{ SEARCHVAL: "MEDIA CLOSE" }],
    }));
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(request(), { APP_API_KEY: "test", ONEMAP_TOKEN: "manual" });
    expect(response.status).toBe(502);
    expect(upstream).toHaveBeenCalledOnce();
  });

  it.each([
    { access_token: "", expiry_timestamp: "9999999999" },
    { access_token: "test", expiry_timestamp: "invalid" },
    { access_token: "test", expiry_timestamp: "1" },
    { error: "Invalid credentials" },
  ])("rejects invalid authentication responses without leaking them", async (result) => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(Response.json(result)));
    const response = await handleRequest(request(), credentials());
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "Place search unavailable" });
  });

  it("can authenticate again after a failed attempt without falling back to the static token", async () => {
    const env = { ...credentials(), ONEMAP_TOKEN: "old-manual-token" };
    const upstream = vi.fn()
      .mockRejectedValueOnce(new Error("Network failure"))
      .mockResolvedValueOnce(token())
      .mockResolvedValueOnce(places());
    vi.stubGlobal("fetch", upstream);
    expect((await handleRequest(request(), env)).status).toBe(502);
    expect((await handleRequest(request(), env)).status).toBe(200);
    expect(upstream).toHaveBeenCalledTimes(3);
  });

  it("does not silently use a static token with incomplete credentials", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(request(), {
      APP_API_KEY: "test", ONEMAP_EMAIL: "administrator@example.test", ONEMAP_TOKEN: "manual",
    });
    expect(response.status).toBe(502);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects unauthenticated requests before logging in to OneMap", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(
      new Request("https://example.test/v1/stops/search?q=138498"), credentials(),
    );
    expect(response.status).toBe(401);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("uses the same authentication for trip planning", async () => {
    const upstream = vi.fn()
      .mockResolvedValueOnce(token())
      .mockResolvedValueOnce(Response.json({ plan: { itineraries: [] } }));
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(new Request("https://example.test/v1/trips/plan", {
      method: "POST",
      headers: { Authorization: "Bearer test", "content-type": "application/json" },
      body: JSON.stringify({
        start: "1.345,103.764", end: "1.292,103.793", date: "10-16-2026", time: "08:00:00",
      }),
    }), credentials());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ itineraries: [] });
    expect(upstream.mock.calls[1][1].headers.Authorization).toBe("test-token");
  });

  it("does not renew credentials for an unrelated upstream failure", async () => {
    const upstream = vi.fn()
      .mockResolvedValueOnce(token())
      .mockResolvedValueOnce(new Response("Unavailable", { status: 503 }));
    vi.stubGlobal("fetch", upstream);
    const response = await handleRequest(request(), credentials());
    expect(response.status).toBe(502);
    expect(upstream).toHaveBeenCalledTimes(2);
  });
});
