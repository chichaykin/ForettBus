import { readFile } from "node:fs/promises";
import { convertV4MiniflareOptions, Miniflare } from "miniflare";
import { afterEach, describe, expect, it, vi } from "vitest";
import webWorker from "./web";

const instances: Miniflare[] = [];

afterEach(async () => {
  vi.unstubAllGlobals();
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function fromBase64Url(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(
    atob(base64.padEnd(base64.length + ((4 - base64.length % 4) % 4), "=")),
    (character) => character.charCodeAt(0),
  );
}

async function migratedDatabase() {
  const miniflare = new Miniflare(convertV4MiniflareOptions({
    modules: true,
    script: "export default { fetch() { return new Response('ok') } }",
    d1Databases: ["DB"],
  }));
  instances.push(miniflare);
  const database = await miniflare.getD1Database("DB");
  const migration = await readFile(new URL("../migrations/0001_web.sql", import.meta.url), "utf8");
  for (const statement of migration.split(";").map((sql) => sql.trim()).filter(Boolean)) {
    await database.prepare(statement).run();
  }
  return database;
}

describe("Web reminder D1 schema", () => {
  it("enforces one current reminder per installation in real local D1", async () => {
    const database = await migratedDatabase();
    const now = new Date().toISOString();
    const installation = await database.prepare(
      "INSERT INTO installations(session_hash, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?) RETURNING id",
    ).bind("hash", now, now, new Date(Date.now() + 60_000).toISOString()).first<{ id: number }>();
    expect(installation?.id).toBeTypeOf("number");
    const insert = (id: string) => database.prepare(`
      INSERT INTO reminders(id, installation_id, departure_at, send_at, direction, schedule_revision, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'forettToBeautyWorld', 'revision1', 'active', ?, ?)
    `).bind(id, installation!.id, new Date(Date.now() + 600_000).toISOString(), new Date(Date.now() + 300_000).toISOString(), now, now).run();
    await insert("a".repeat(32));
    await expect(insert("b".repeat(32))).rejects.toThrow();
    await database.prepare("UPDATE reminders SET status = 'replaced' WHERE id = ?").bind("a".repeat(32)).run();
    await expect(insert("b".repeat(32))).resolves.toBeDefined();
  });

  it("sends 100 queued reminders through the test delivery stub", async () => {
    const database = await migratedDatabase();
    const pair = await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    ) as CryptoKeyPair;
    const publicJwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
    const privateJwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
    const publicKeyBytes = new Uint8Array([
      4,
      ...fromBase64Url(publicJwk.x!),
      ...fromBase64Url(publicJwk.y!),
    ]);
    const vapidPublicKey = base64Url(publicKeyBytes);
    const vapidPrivateKey = base64Url(fromBase64Url(privateJwk.d!));
    const subscriptionPublicKey = base64Url(publicKeyBytes);
    const subscriptionAuth = base64Url(crypto.getRandomValues(new Uint8Array(16)));
    const now = new Date();
    const createdAt = now.toISOString();
    const expiresAt = new Date(now.getTime() + 86_400_000).toISOString();
    const departureAt = new Date(now.getTime() + 15 * 60_000).toISOString();
    const queuedAt = new Date(now.getTime() - 60_000).toISOString();
    const reminders: Array<{ id: string; ack: ReturnType<typeof vi.fn>; retry: ReturnType<typeof vi.fn> }> = [];

    for (let index = 0; index < 100; index++) {
      const id = `loadtest-${String(index).padStart(4, "0")}`;
      const installation = await database.prepare(
        "INSERT INTO installations(session_hash, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?) RETURNING id",
      ).bind(`load-test-session-${index}`, createdAt, createdAt, expiresAt).first<{ id: number }>();
      await database.prepare(`
        INSERT INTO push_subscriptions(installation_id, endpoint, p256dh, auth, version, updated_at)
        VALUES (?, ?, ?, ?, 1, ?)
      `).bind(
        installation!.id,
        `https://fcm.googleapis.com/fcm/send/load-test-${index}`,
        subscriptionPublicKey,
        subscriptionAuth,
        createdAt,
      ).run();
      await database.prepare(`
        INSERT INTO reminders(id, installation_id, departure_at, send_at, direction, schedule_revision, status, attempts, subscription_version, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'forettToBeautyWorld', 'load-test-revision', 'queued', 0, 1, ?, ?)
      `).bind(id, installation!.id, departureAt, queuedAt, createdAt, createdAt).run();
      reminders.push({ id, ack: vi.fn(), retry: vi.fn() });
    }

    const testPushSend = vi.fn(async (_url: unknown, _init: { redirect?: string }) =>
      new Response(null, { status: 201 }));
    vi.stubGlobal("fetch", testPushSend);
    const environment = {
      DB: database,
      PUSH_ENABLED: "true",
      VAPID_PUBLIC_KEY: vapidPublicKey,
      VAPID_PRIVATE_KEY: vapidPrivateKey,
      VAPID_SUBJECT: "mailto:load-test@example.invalid",
    };

    await Promise.all(reminders.map(({ id, ack, retry }) => webWorker.queue({
      messages: [{ body: { reminderId: id }, ack, retry }],
    } as never, environment as never)));

    expect(testPushSend).toHaveBeenCalledTimes(100);
    expect(testPushSend.mock.calls.every(([, init]) => init.redirect === "manual")).toBe(true);
    expect(reminders.every(({ ack, retry }) => ack.mock.calls.length === 1 && retry.mock.calls.length === 0)).toBe(true);
    for (const { id } of reminders) {
      const reminder = await database.prepare("SELECT status FROM reminders WHERE id = ?")
        .bind(id).first<{ status: string }>();
      expect(reminder?.status).toBe("sent");
    }
  }, 30_000);
});
