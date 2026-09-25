import { readFile } from "node:fs/promises";
import { convertV4MiniflareOptions, Miniflare } from "miniflare";
import { afterEach, describe, expect, it } from "vitest";

const instances: Miniflare[] = [];

afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("Web reminder D1 schema", () => {
  it("enforces one current reminder per installation in real local D1", async () => {
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
});
