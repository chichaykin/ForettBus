import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";
import { describe, expect, it, vi } from "vitest";

describe("Web service worker", () => {
  it("precache install has no equivalent relative and absolute URLs", async () => {
    const origin = "https://forett.example";
    const addAll = vi.fn(async (urls: string[]) => {
      const resolved = urls.map((url) => new URL(url, origin).href);
      if (new Set(resolved).size !== resolved.length) {
        throw new Error("Cache.addAll rejects duplicate requests");
      }
    });
    const handlers = new Map<string, (event: { waitUntil(value: Promise<void>): void }) => void>();
    const self = {
      location: { origin },
      __WB_MANIFEST: [
        { url: "index.html", revision: "index" },
        { url: "main.dart.js", revision: "main" },
        { url: "flutter_bootstrap.js", revision: "bootstrap" },
      ],
      addEventListener: (type: string, handler: (event: { waitUntil(value: Promise<void>): void }) => void) => {
        handlers.set(type, handler);
      },
    };
    const source = await readFile(new URL("../../web/service-worker-src.js", import.meta.url), "utf8");
    runInNewContext(source, {
      self,
      URL,
      caches: { open: async () => ({ addAll }) },
    });

    let installation: Promise<void> | undefined;
    handlers.get("install")!({ waitUntil: (value) => { installation = value; } });
    await installation;

    expect(addAll).toHaveBeenCalledOnce();
    const urls = addAll.mock.calls[0][0];
    expect(urls).toHaveLength(4);
    expect(urls).toContain(`${origin}/`);
  });

  it("serves the cached app shell for an offline navigation with a query", async () => {
    const origin = "https://forett.example";
    const shell = new Response("cached Home");
    const match = vi.fn(async (request: { url?: string } | string) =>
      request === "/" ? shell : undefined);
    const networkFetch = vi.fn(async () => { throw new Error("offline"); });
    const handlers = new Map<string, (event: {
      request: { method: string; mode: string; url: string };
      respondWith(value: Promise<Response>): void;
    }) => void>();
    const source = await readFile(new URL("../../web/service-worker-src.js", import.meta.url), "utf8");
    runInNewContext(source, {
      self: {
        location: { origin },
        __WB_MANIFEST: [],
        addEventListener: (type: string, handler: (event: {
          request: { method: string; mode: string; url: string };
          respondWith(value: Promise<Response>): void;
        }) => void) => { handlers.set(type, handler); },
      },
      URL,
      caches: { match },
      fetch: networkFetch,
    });

    let response: Promise<Response> | undefined;
    handlers.get("fetch")!({
      request: { method: "GET", mode: "navigate", url: `${origin}/?direction=beautyWorldToForett` },
      respondWith: (value) => { response = value; },
    });

    expect(await response?.then((value) => value.text())).toBe("cached Home");
    expect(networkFetch).not.toHaveBeenCalled();
  });
});
