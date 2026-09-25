import { describe, expect, it, vi } from "vitest";
import { handleWebRequest } from "./web";

function environment(overrides: Record<string, unknown> = {}) {
  return {
    ASSETS: { fetch: vi.fn(async () => new Response("missing", { status: 404 })) },
    TRANSPORT: { fetch: vi.fn(async () => new Response(JSON.stringify({ ok: true }))) },
    WEB_TRANSPORT_API_KEY: "server-only-key",
    ...overrides,
  } as never;
}

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
      new Request("https://app.example/api/v1/arrivals?stopCode=not-a-stop"),
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
      new Request("https://app.example/api/v1/arrivals?stopCode=42221"),
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
      headers: { origin: "https://app.example", "content-type": "application/json" },
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
      headers: { origin: "https://app.example", "content-type": "application/json" },
      body: JSON.stringify({ start: "1.3,103.7", padding: "x".repeat(17_000) }),
    }), env);

    expect(response.status).toBe(413);
    expect((env as { TRANSPORT: { fetch: ReturnType<typeof vi.fn> } }).TRANSPORT.fetch).not.toHaveBeenCalled();
  });
});
