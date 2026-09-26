import { describe, expect, it, vi } from "vitest";
import { handleWebRequest } from "./web";

function environment(overrides: Record<string, unknown> = {}) {
  const database = {
    prepare: vi.fn((query: string) => {
      const parameters: unknown[] = [];
      const statement = {
        bind: vi.fn((...values: unknown[]) => {
          parameters.push(...values);
          return statement;
        }),
        first: vi.fn(async () => query.includes('FROM installations') ? {
          id: 1,
          session_hash: String(parameters[0] ?? 'test-session'),
          expires_at: new Date(Date.now() + 60_000).toISOString(),
        } : null),
        run: vi.fn(async () => ({ meta: { changes: 1 } })),
      };
      return statement;
    }),
  };
  const rateLimit = { limit: vi.fn(async () => ({ success: true })) };
  return {
    ASSETS: { fetch: vi.fn(async () => new Response("missing", { status: 404 })) },
    TRANSPORT: { fetch: vi.fn(async () => new Response(JSON.stringify({ ok: true }))) },
    DB: database,
    IP_RATE_LIMITER: rateLimit,
    READ_RATE_LIMITER: rateLimit,
    WRITE_RATE_LIMITER: rateLimit,
    PLAN_RATE_LIMITER: rateLimit,
    SESSION_RATE_LIMITER: rateLimit,
    WEB_TRANSPORT_API_KEY: "server-only-key",
    ...overrides,
  } as never;
}

const sessionCookie = `__Host-forett_session=${"a".repeat(43)}`;

describe("Web Worker routing", () => {
  it("returns JSON 404 for an unknown API route without serving the app", async () => {
    const env = environment();
    const response = await handleWebRequest(new Request("https://app.example/api/unknown"), env);

    expect(response.status).toBe(404);
    expect(response.headers.get("content-type")).toContain("application/json");
    expect((env as { ASSETS: { fetch: ReturnType<typeof vi.fn> } }).ASSETS.fetch).not.toHaveBeenCalled();
  });

  it("rejects an invalid stop before the transport service binding", async () => {
    const env = environment();
    const response = await handleWebRequest(
      new Request("https://app.example/api/v1/arrivals?stopCode=not-a-stop", {
        headers: { cookie: sessionCookie },
      }),
      env,
    );

    expect(response.status).toBe(400);
    expect((env as { TRANSPORT: { fetch: ReturnType<typeof vi.fn> } }).TRANSPORT.fetch).not.toHaveBeenCalled();
  });

  it("adds server authorization and strips browser caching on proxy responses", async () => {
    const transport = vi.fn(async (request: Request) => {
      expect(request.headers.get("authorization")).toBe("Bearer server-only-key");
      return new Response(JSON.stringify({ routes: [] }), {
        headers: { "cache-control": "public, max-age=20" },
      });
    });
    const env = environment({ TRANSPORT: { fetch: transport } });
    const response = await handleWebRequest(
      new Request("https://app.example/api/v1/arrivals?stopCode=42221", {
        headers: { cookie: sessionCookie },
      }),
      env,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(transport).toHaveBeenCalledOnce();
  });

  it("rejects a state-changing request with a foreign origin before D1", async () => {
    const env = environment();
    const response = await handleWebRequest(new Request("https://app.example/api/session", {
      method: "POST",
      headers: { origin: "https://attacker.example" },
    }), env);

    expect(response.status).toBe(403);
  });

  it("rejects invalid trip coordinates before the transport service binding", async () => {
    const env = environment();
    const response = await handleWebRequest(new Request("https://app.example/api/v1/trips/plan", {
      method: "POST",
      headers: {
        origin: "https://app.example",
        cookie: sessionCookie,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        start: "not-coordinates",
        end: "1.34,103.77",
        date: "09-25-2026",
        time: "10:00:00",
      }),
    }), env);

    expect(response.status).toBe(400);
    expect((env as { TRANSPORT: { fetch: ReturnType<typeof vi.fn> } }).TRANSPORT.fetch).not.toHaveBeenCalled();
  });

  it("rejects oversized request bodies", async () => {
    const env = environment();
    const response = await handleWebRequest(new Request("https://app.example/api/v1/trips/plan", {
      method: "POST",
      headers: {
        origin: "https://app.example",
        cookie: sessionCookie,
        "content-type": "application/json",
      },
      body: JSON.stringify({ start: "1.3,103.7", padding: "x".repeat(17_000) }),
    }), env);

    expect(response.status).toBe(413);
    expect((env as { TRANSPORT: { fetch: ReturnType<typeof vi.fn> } }).TRANSPORT.fetch).not.toHaveBeenCalled();
  });

  it("requires a validated session before proxying public transport data", async () => {
    const env = environment();
    const response = await handleWebRequest(
      new Request("https://app.example/api/v1/arrivals?stopCode=42221"),
      env,
    );

    expect(response.status).toBe(401);
    expect((env as { TRANSPORT: { fetch: ReturnType<typeof vi.fn> } }).TRANSPORT.fetch).not.toHaveBeenCalled();
  });

  it("uses the validated installation hash for the shared read limit", async () => {
    const limiter = { limit: vi.fn(async () => ({ success: false })) };
    const env = environment({ READ_RATE_LIMITER: limiter });
    const response = await handleWebRequest(
      new Request("https://app.example/api/v1/arrivals?stopCode=42221", {
        headers: { cookie: sessionCookie },
      }),
      env,
    );

    expect(response.status).toBe(429);
    expect(limiter.limit).toHaveBeenCalledOnce();
    expect(limiter.limit.mock.calls[0][0].key).not.toBe("unknown");
    expect((env as { TRANSPORT: { fetch: ReturnType<typeof vi.fn> } }).TRANSPORT.fetch).not.toHaveBeenCalled();
  });

  it("keeps 100 installations on one shared IP independent for transport and trip planning", async () => {
    const makeLimiter = () => ({ limit: vi.fn(async () => ({ success: true })) });
    const ipLimiter = makeLimiter();
    const readLimiter = makeLimiter();
    const writeLimiter = makeLimiter();
    const planLimiter = makeLimiter();
    const env = environment({
      IP_RATE_LIMITER: ipLimiter,
      READ_RATE_LIMITER: readLimiter,
      WRITE_RATE_LIMITER: writeLimiter,
      PLAN_RATE_LIMITER: planLimiter,
    });
    const sharedIp = "203.0.113.42";
    const cookies = Array.from({ length: 100 }, (_, index) =>
      `__Host-forett_session=${String(index + 1).padStart(43, "a")}`,
    );
    const requests = cookies.flatMap((cookie) => [
      new Request("https://app.example/api/v1/arrivals?stopCode=42221", {
        headers: { cookie, "cf-connecting-ip": sharedIp },
      }),
      new Request("https://app.example/api/v1/trips/plan", {
        method: "POST",
        headers: {
          origin: "https://app.example",
          cookie,
          "cf-connecting-ip": sharedIp,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          start: "1.3,103.7",
          end: "1.34,103.77",
          date: "09-26-2026",
          time: "10:00:00",
        }),
      }),
    ]);

    const responses = await Promise.all(requests.map((request) => handleWebRequest(request, env)));

    expect(responses).toHaveLength(200);
    expect(responses.every((response) => response.status === 200)).toBe(true);
    expect(ipLimiter.limit).toHaveBeenCalledTimes(200);
    expect(new Set(ipLimiter.limit.mock.calls.map(([call]) => call.key))).toEqual(new Set([sharedIp]));
    expect(readLimiter.limit).toHaveBeenCalledTimes(100);
    expect(new Set(readLimiter.limit.mock.calls.map(([call]) => call.key)).size).toBe(100);
    expect(writeLimiter.limit).toHaveBeenCalledTimes(100);
    expect(new Set(writeLimiter.limit.mock.calls.map(([call]) => call.key)).size).toBe(100);
    expect(planLimiter.limit).toHaveBeenCalledTimes(100);
    expect(new Set(planLimiter.limit.mock.calls.map(([call]) => call.key)).size).toBe(100);
  });
});
