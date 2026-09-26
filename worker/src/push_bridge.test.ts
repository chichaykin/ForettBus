import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";
import { describe, expect, it, vi } from "vitest";

describe("iPhone push bridge", () => {
  it("starts subscription in the button tap before awaiting a Promise", async () => {
    const subscription = {
      toJSON: () => ({ endpoint: "https://example.test/push" }),
    };
    const subscribe = vi.fn(() => Promise.resolve(subscription));
    const registration = {
      active: {},
      pushManager: {
        getSubscription: () => Promise.resolve(null),
        subscribe,
      },
    };
    const window = {
      matchMedia: () => ({ matches: true }),
      navigator: { standalone: true },
      isSecureContext: true,
      PushManager: class {},
      Notification: class {},
      forettPush: undefined as unknown,
    };
    const navigator = {
      userAgent: "iPhone",
      platform: "iPhone",
      serviceWorker: { register: () => Promise.resolve(registration) },
    };
    const source = await readFile(new URL("../../web/push_bridge.js", import.meta.url), "utf8");
    runInNewContext(source, {
      window, navigator, Notification: { permission: "granted" },
      atob, Uint8Array, setTimeout, clearTimeout,
    });

    const bridge = window.forettPush as {
      existingSubscription(): Promise<string>;
      subscribe(key: string): Promise<string>;
    };
    await bridge.existingSubscription();
    const result = bridge.subscribe("AQID");
    expect(subscribe).toHaveBeenCalledOnce();
    expect(await result).toContain("https://example.test/push");
  });
});
