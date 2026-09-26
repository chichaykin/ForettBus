import {
  buildPushPayload,
  type PushSubscription,
} from "@block65/webcrypto-web-push";

type Direction = "forettToBeautyWorld" | "beautyWorldToForett";
type ReminderMessage = { reminderId: string };

interface Env {
  ASSETS: Fetcher;
  TRANSPORT: Fetcher;
  DB: D1Database;
  REMINDER_QUEUE: Queue<ReminderMessage>;
  READ_RATE_LIMITER?: RateLimit;
  WRITE_RATE_LIMITER?: RateLimit;
  PLAN_RATE_LIMITER?: RateLimit;
  IP_RATE_LIMITER?: RateLimit;
  SESSION_RATE_LIMITER?: RateLimit;
  WEB_TRANSPORT_API_KEY?: string;
  VAPID_PUBLIC_KEY?: string;
  VAPID_PRIVATE_KEY?: string;
  VAPID_SUBJECT?: string;
  PUSH_ENABLED?: string;
}

interface Installation {
  id: number;
  session_hash: string;
  expires_at: string;
}

interface ReminderRow {
  id: string;
  installation_id: number;
  departure_at: string;
  send_at: string;
  direction: Direction;
  schedule_revision: string;
  status: string;
  attempts: number;
  subscription_version: number | null;
  locked_until: string | null;
}

interface SubscriptionRow {
  endpoint: string;
  p256dh: string;
  auth: string;
  version: number;
}

const SESSION_COOKIE = "__Host-forett_session";
const SESSION_DAYS = 180;
const MAX_BODY_BYTES = 16 * 1024;
const HOLIDAY_URL = "https://data.gov.sg/api/action/datastore_search?resource_id=d_8ef23381f9417e4d4254ee8b4dcdb176&limit=200";
const TRANSPORT_PATHS = new Set([
  "/v1/arrivals",
  "/v1/stops/search",
  "/v1/stops",
  "/v1/trips/plan",
]);

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...jsonHeaders, ...headers },
  });
}

function nowIso(): string {
  return new Date().toISOString();
}

function addDays(value: Date, days: number): string {
  return new Date(value.getTime() + days * 86_400_000).toISOString();
}

function cookieValue(request: Request, name: string): string | null {
  const cookies = request.headers.get("cookie") ?? "";
  for (const part of cookies.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=");
  }
  return null;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return base64Url(new Uint8Array(digest));
}

function newSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

function originAllowed(request: Request): boolean {
  const origin = request.headers.get("origin");
  return origin === new URL(request.url).origin;
}

async function limited(binding: RateLimit | undefined, key: string): Promise<boolean> {
  if (!binding) return false;
  return !(await binding.limit({ key })).success;
}

function clientIp(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? "unknown";
}

async function bodyText(request: Request): Promise<string> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) throw new Response("", { status: 413 });
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new Response("", { status: 413 });
  }
  return text;
}

async function bodyObject(request: Request): Promise<Record<string, unknown>> {
  try {
    const parsed = JSON.parse(await bodyText(request));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return parsed as Record<string, unknown>;
  } catch (error) {
    if (error instanceof Response) throw error;
    throw json({ error: "Invalid JSON request" }, 400);
  }
}

async function installationFor(
  request: Request,
  env: Env,
  touch = true,
): Promise<Installation | null> {
  const token = cookieValue(request, SESSION_COOKIE);
  if (!token || token.length < 40 || token.length > 64) return null;
  const hash = await sha256(token);
  const installation = await env.DB.prepare(
    "SELECT id, session_hash, expires_at FROM installations WHERE session_hash = ? AND expires_at > ?",
  ).bind(hash, nowIso()).first<Installation>();
  if (!installation) return null;
  if (touch) {
    const now = new Date();
    await env.DB.prepare(
      "UPDATE installations SET last_seen_at = ?, expires_at = ? WHERE id = ?",
    ).bind(now.toISOString(), addDays(now, SESSION_DAYS), installation.id).run();
  }
  return installation;
}

async function session(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, { allow: "POST" });
  if (!originAllowed(request)) return json({ error: "Invalid origin" }, 403);
  const existing = await installationFor(request, env);
  if (existing) {
    const token = cookieValue(request, SESSION_COOKIE)!;
    return json({ session: "ready" }, 200, {
      "set-cookie": `${SESSION_COOKIE}=${token}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_DAYS * 86_400}`,
    });
  }
  if (await limited(env.SESSION_RATE_LIMITER, clientIp(request))) {
    return json({ error: "Too many requests" }, 429, { "retry-after": "60" });
  }
  const token = newSessionToken();
  const hash = await sha256(token);
  const now = new Date();
  await env.DB.prepare(
    "INSERT INTO installations(session_hash, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?)",
  ).bind(hash, now.toISOString(), now.toISOString(), addDays(now, SESSION_DAYS)).run();
  return json({ session: "created" }, 201, {
    "set-cookie": `${SESSION_COOKIE}=${token}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_DAYS * 86_400}`,
  });
}

function validPushEndpoint(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || (url.port && url.port !== "443")) return false;
    const apple = url.hostname === "web.push.apple.com" || url.hostname.endsWith(".push.apple.com");
    const fcm = url.hostname === "fcm.googleapis.com" || url.hostname === "updates.push.services.mozilla.com";
    return (apple || fcm) && url.pathname.length > 1;
  } catch (_) {
    return false;
  }
}

function validKey(value: unknown, min: number, max: number): value is string {
  return typeof value === "string" && value.length >= min && value.length <= max && /^[A-Za-z0-9_-]+$/.test(value);
}

async function pushApi(request: Request, env: Env, path: string): Promise<Response> {
  if (path === "/api/push/config") {
    if (request.method !== "GET") return json({ error: "Method not allowed" }, 405, { allow: "GET" });
    return json({
      available: env.PUSH_ENABLED !== "false" && Boolean(env.VAPID_PUBLIC_KEY),
      vapidPublicKey: env.VAPID_PUBLIC_KEY ?? "",
    });
  }
  if (!originAllowed(request)) return json({ error: "Invalid origin" }, 403);
  const installation = await installationFor(request, env);
  if (!installation) return json({ error: "Session required" }, 401);

  if (path === "/api/push/subscription" && request.method === "PUT") {
    if (env.PUSH_ENABLED === "false") return json({ error: "Push is disabled" }, 503);
    const body = await bodyObject(request);
    const keys = body.keys;
    if (!validPushEndpoint(body.endpoint) || !keys || typeof keys !== "object") {
      return json({ error: "Invalid push subscription" }, 400);
    }
    const p256dh = (keys as Record<string, unknown>).p256dh;
    const auth = (keys as Record<string, unknown>).auth;
    if (!validKey(p256dh, 80, 120) || !validKey(auth, 16, 64)) {
      return json({ error: "Invalid push keys" }, 400);
    }
    const timestamp = nowIso();
    const existing = await env.DB.prepare(
      "SELECT version FROM push_subscriptions WHERE installation_id = ?",
    ).bind(installation.id).first<{ version: number }>();
    const version = (existing?.version ?? 0) + 1;
    await env.DB.batch([
      env.DB.prepare(`
      INSERT INTO push_subscriptions(installation_id, endpoint, p256dh, auth, version, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(installation_id) DO UPDATE SET
        endpoint = excluded.endpoint,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        version = excluded.version,
        updated_at = excluded.updated_at
      `).bind(installation.id, body.endpoint, p256dh, auth, version, timestamp),
      env.DB.prepare("UPDATE reminders SET subscription_version = ?, updated_at = ? WHERE installation_id = ? AND status IN ('active','queued','sending')")
        .bind(version, timestamp, installation.id),
    ]);
    return json({ subscription: "ready" });
  }

  if (path === "/api/push/subscription" && request.method === "DELETE") {
    const timestamp = nowIso();
    await env.DB.batch([
      env.DB.prepare("UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE installation_id = ? AND status IN ('active','queued','sending')").bind(timestamp, installation.id),
      env.DB.prepare("DELETE FROM push_subscriptions WHERE installation_id = ?").bind(installation.id),
    ]);
    return new Response(null, { status: 204, headers: jsonHeaders });
  }
  return json({ error: "Method not allowed" }, 405);
}

function reminderJson(row: ReminderRow) {
  return {
    id: row.id,
    departureAt: row.departure_at,
    direction: row.direction,
    scheduleRevision: row.schedule_revision,
    status: row.status,
  };
}

function validReminderId(value: unknown): value is string {
  return typeof value === "string" && value.length >= 32 && value.length <= 64 && /^[A-Za-z0-9_-]+$/.test(value);
}

async function reminderApi(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET" && !originAllowed(request)) return json({ error: "Invalid origin" }, 403);
  const installation = await installationFor(request, env);
  if (!installation) return json({ error: "Session required" }, 401);

  if (request.method === "GET") {
    const row = await env.DB.prepare(
      "SELECT * FROM reminders WHERE installation_id = ? AND status IN ('active','queued','sending') ORDER BY updated_at DESC LIMIT 1",
    ).bind(installation.id).first<ReminderRow>();
    return json({ reminder: row ? reminderJson(row) : null });
  }

  if (request.method === "PUT") {
    if (env.PUSH_ENABLED === "false") return json({ error: "Push is disabled" }, 503);
    const subscription = await env.DB.prepare(
      "SELECT version FROM push_subscriptions WHERE installation_id = ?",
    ).bind(installation.id).first<{ version: number }>();
    if (!subscription) return json({ error: "Push subscription required" }, 409);
    const body = await bodyObject(request);
    const id = body.id;
    const direction = body.direction;
    const revision = body.scheduleRevision;
    const departureAt = typeof body.departureAt === "string" ? new Date(body.departureAt) : new Date(Number.NaN);
    if (!validReminderId(id) ||
        (direction !== "forettToBeautyWorld" && direction !== "beautyWorldToForett") ||
        typeof revision !== "string" || revision.length < 8 || revision.length > 128 ||
        Number.isNaN(departureAt.getTime())) {
      return json({ error: "Invalid reminder" }, 400);
    }
    const now = new Date();
    const sendAt = new Date(departureAt.getTime() - 5 * 60_000);
    if (sendAt.getTime() <= now.getTime() || departureAt.getTime() > now.getTime() + 7 * 86_400_000) {
      return json({ error: "Reminder time is outside the allowed range" }, 400);
    }
    const previous = await env.DB.prepare("SELECT * FROM reminders WHERE id = ?").bind(id).first<ReminderRow>();
    if (previous) {
      const same = previous.installation_id === installation.id &&
        previous.departure_at === departureAt.toISOString() &&
        previous.direction === direction && previous.schedule_revision === revision;
      if (same && ["active", "queued", "sending", "sent"].includes(previous.status)) {
        return json({ reminder: reminderJson(previous) });
      }
      return json({ error: "Reminder ID cannot be reused" }, 409);
    }
    const timestamp = now.toISOString();
    await env.DB.batch([
      env.DB.prepare("UPDATE reminders SET status = 'replaced', updated_at = ? WHERE installation_id = ? AND status IN ('active','queued','sending')").bind(timestamp, installation.id),
      env.DB.prepare(`
        INSERT INTO reminders(id, installation_id, departure_at, send_at, direction, schedule_revision, status, attempts, subscription_version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 'active', 0, ?, ?, ?)
      `).bind(id, installation.id, departureAt.toISOString(), sendAt.toISOString(), direction, revision, subscription.version, timestamp, timestamp),
    ]);
    const created = await env.DB.prepare("SELECT * FROM reminders WHERE id = ?").bind(id).first<ReminderRow>();
    return json({ reminder: reminderJson(created!) }, 201);
  }

  if (request.method === "DELETE") {
    const id = new URL(request.url).searchParams.get("id");
    if (id && !validReminderId(id)) return json({ error: "Invalid reminder ID" }, 400);
    const timestamp = nowIso();
    const statement = id
      ? env.DB.prepare("UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE id = ? AND installation_id = ? AND status IN ('active','queued','sending')").bind(timestamp, id, installation.id)
      : env.DB.prepare("UPDATE reminders SET status = 'cancelled', updated_at = ? WHERE installation_id = ? AND status IN ('active','queued','sending')").bind(timestamp, installation.id);
    await statement.run();
    return new Response(null, { status: 204, headers: jsonHeaders });
  }
  return json({ error: "Method not allowed" }, 405);
}

function validateTransport(url: URL, request: Request): Response | null {
  const path = url.pathname.replace(/^\/api/, "");
  if (!TRANSPORT_PATHS.has(path)) return json({ error: "Not found" }, 404);
  const expectedMethod = path === "/v1/trips/plan" ? "POST" : "GET";
  if (request.method !== expectedMethod) return json({ error: "Method not allowed" }, 405, { allow: expectedMethod });
  const allowed = path === "/v1/arrivals"
    ? new Set(["direction", "stopCode", "services"])
    : path === "/v1/stops/search" ? new Set(["q"])
    : path === "/v1/stops" ? new Set(["search"])
    : new Set<string>();
  for (const key of url.searchParams.keys()) if (!allowed.has(key)) return json({ error: "Invalid parameter" }, 400);
  const stop = url.searchParams.get("stopCode");
  if (stop && !/^\d{5}$/.test(stop)) return json({ error: "Invalid stopCode" }, 400);
  const direction = url.searchParams.get("direction");
  if (direction && direction !== "forettToBeautyWorld" && direction !== "beautyWorldToForett") {
    return json({ error: "Invalid direction" }, 400);
  }
  if (path === "/v1/arrivals" && Boolean(stop) === Boolean(direction)) {
    return json({ error: "Provide one direction or stopCode" }, 400);
  }
  const services = url.searchParams.get("services");
  if (services && (services.length > 100 || !/^[0-9]{1,4}[A-Za-z]?(,[0-9]{1,4}[A-Za-z]?)*$/.test(services))) {
    return json({ error: "Invalid services" }, 400);
  }
  for (const key of ["q", "search"]) {
    const value = url.searchParams.get(key);
    if (value && (value.trim().length < 2 || value.length > 100)) return json({ error: "Invalid search" }, 400);
  }
  return null;
}

function validCoordinatePair(value: unknown): boolean {
  if (typeof value !== "string" || value.length > 50) return false;
  const parts = value.split(",");
  if (parts.length !== 2) return false;
  const latitude = Number(parts[0]);
  const longitude = Number(parts[1]);
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

function validTripBody(body: Record<string, unknown>): boolean {
  const allowed = new Set(["start", "end", "date", "time"]);
  if (Object.keys(body).some((key) => !allowed.has(key))) return false;
  return validCoordinatePair(body.start) && validCoordinatePair(body.end) &&
    typeof body.date === "string" && /^\d{2}-\d{2}-\d{4}$/.test(body.date) &&
    typeof body.time === "string" && /^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$/.test(body.time);
}

async function transportProxy(request: Request, env: Env): Promise<Response> {
  if (!env.WEB_TRANSPORT_API_KEY) return json({ error: "Transport proxy is not configured" }, 503);
  const url = new URL(request.url);
  const invalid = validateTransport(url, request);
  if (invalid) return invalid;
  if (request.method === "POST" && !originAllowed(request)) return json({ error: "Invalid origin" }, 403);
  let body: string | undefined;
  if (request.method === "POST") {
    const parsed = await bodyObject(request);
    if (!validTripBody(parsed)) return json({ error: "Invalid trip request" }, 400);
    body = JSON.stringify(parsed);
  }
  const upstreamUrl = new URL(url.pathname.replace(/^\/api/, "") + url.search, "https://transport.internal");
  const upstream = await env.TRANSPORT.fetch(new Request(upstreamUrl, {
    method: request.method,
    headers: {
      accept: "application/json",
      authorization: `Bearer ${env.WEB_TRANSPORT_API_KEY}`,
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body,
  }));
  const headers = new Headers(upstream.headers);
  headers.set("cache-control", "no-store");
  headers.delete("access-control-allow-origin");
  return new Response(upstream.body, { status: upstream.status, headers });
}

async function holidays(request: Request): Promise<Response> {
  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405, { allow: "GET" });
  const cache = caches.default;
  const key = new Request("https://forett-cache.invalid/holidays");
  const cached = await cache.match(key);
  if (cached) return new Response(cached.body, { headers: { ...Object.fromEntries(cached.headers), "cache-control": "no-store" } });
  const response = await fetch(HOLIDAY_URL, { headers: { accept: "application/json" } });
  if (!response.ok) return json({ error: "Holiday calendar unavailable" }, 502);
  const saved = new Response(response.body, { headers: { "content-type": "application/json", "cache-control": "public, max-age=86400" } });
  await cache.put(key, saved.clone());
  return new Response(saved.body, { headers: jsonHeaders });
}

export async function handleWebRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/api/")) return env.ASSETS.fetch(request);
  try {
    if (await limited(env.IP_RATE_LIMITER, clientIp(request))) {
      return json({ error: "Too many requests" }, 429, { "retry-after": "60" });
    }

    const isSessionRoute = url.pathname === "/api/session";
    const isPublicRead =
      request.method === "GET" &&
      (url.pathname === "/api/push/config" || url.pathname === "/api/holidays");
    const isProtectedRoute =
      url.pathname === "/api/reminder" ||
      url.pathname.startsWith("/api/push/") ||
      url.pathname.startsWith("/api/v1/");

    if (!isSessionRoute && !isPublicRead && isProtectedRoute) {
      const installation = await installationFor(request, env, false);
      if (!installation) return json({ error: "Session required" }, 401);
      if (await limited(
        request.method === "GET" ? env.READ_RATE_LIMITER : env.WRITE_RATE_LIMITER,
        installation.session_hash,
      )) {
        return json({ error: "Too many requests" }, 429, { "retry-after": "60" });
      }
      if (
        url.pathname === "/api/v1/trips/plan" &&
        await limited(env.PLAN_RATE_LIMITER, installation.session_hash)
      ) {
        return json({ error: "Too many requests" }, 429, { "retry-after": "60" });
      }
    }

    if (url.pathname === "/api/session") return await session(request, env);
    if (url.pathname.startsWith("/api/push/")) return await pushApi(request, env, url.pathname);
    if (url.pathname === "/api/reminder") return await reminderApi(request, env);
    if (url.pathname === "/api/holidays") return await holidays(request);
    if (url.pathname.startsWith("/api/v1/")) return await transportProxy(request, env);
    return json({ error: "Not found" }, 404);
  } catch (error) {
    if (error instanceof Response) return error;
    console.error("Web API request failed", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Request unavailable" }, 500);
  }
}

async function enqueueDue(env: Env): Promise<void> {
  const now = new Date();
  const due = await env.DB.prepare(`
    SELECT id FROM reminders
    WHERE departure_at > ? AND send_at <= ? AND (
      status = 'active' OR (status = 'queued' AND locked_until < ?)
    ) ORDER BY send_at LIMIT 100
  `).bind(now.toISOString(), now.toISOString(), now.toISOString()).all<{ id: string }>();
  for (const row of due.results) {
    const lockedUntil = new Date(now.getTime() + 120_000).toISOString();
    const result = await env.DB.prepare(`
      UPDATE reminders SET status = 'queued', locked_until = ?, updated_at = ?
      WHERE id = ? AND (status = 'active' OR (status = 'queued' AND locked_until < ?))
    `).bind(lockedUntil, now.toISOString(), row.id, now.toISOString()).run();
    if (result.meta.changes) await env.REMINDER_QUEUE.send({ reminderId: row.id });
  }
  const cutoff = new Date(now.getTime() - 7 * 86_400_000).toISOString();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM reminders WHERE status IN ('sent','cancelled','replaced','failed') AND updated_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM installations WHERE expires_at < ?").bind(now.toISOString()),
  ]);
}

function endpointAllowedForSend(endpoint: string): boolean {
  return validPushEndpoint(endpoint);
}

async function deliver(message: Message<ReminderMessage>, env: Env): Promise<void> {
  if (env.PUSH_ENABLED === "false") return;
  const row = await env.DB.prepare("SELECT * FROM reminders WHERE id = ?").bind(message.body.reminderId).first<ReminderRow>();
  if (!row || row.status !== "queued" || new Date(row.departure_at) <= new Date()) return;
  const lock = new Date(Date.now() + 60_000).toISOString();
  const claimed = await env.DB.prepare("UPDATE reminders SET status = 'sending', locked_until = ?, attempts = attempts + 1, updated_at = ? WHERE id = ? AND status = 'queued'")
    .bind(lock, nowIso(), row.id).run();
  if (!claimed.meta.changes) return;
  const subscription = await env.DB.prepare("SELECT * FROM push_subscriptions WHERE installation_id = ?").bind(row.installation_id).first<SubscriptionRow>();
  if (!subscription || subscription.version !== row.subscription_version || !endpointAllowedForSend(subscription.endpoint)) {
    await env.DB.prepare("UPDATE reminders SET status = 'failed', last_error = 'subscription', updated_at = ? WHERE id = ? AND status = 'sending'").bind(nowIso(), row.id).run();
    return;
  }
  if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY || !env.VAPID_SUBJECT) throw new Error("VAPID is not configured");
  const departure = new Date(row.departure_at);
  const singaporeTime = new Intl.DateTimeFormat("en-SG", {
    timeZone: "Asia/Singapore", hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(departure);
  const from = row.direction === "forettToBeautyWorld" ? "Forett" : "Beauty World MRT";
  const pushSubscription: PushSubscription = {
    endpoint: subscription.endpoint,
    expirationTime: null,
    keys: { p256dh: subscription.p256dh, auth: subscription.auth },
  };
  const ttl = Math.max(0, Math.floor((departure.getTime() - Date.now()) / 1000));
  const payload = await buildPushPayload({
    data: {
      title: "Forett Shuttle",
      body: `Shuttle departs at ${singaporeTime} from ${from}`,
      reminderId: row.id,
      direction: row.direction,
    },
    options: { ttl, urgency: "high", topic: row.id.slice(0, 32) },
  }, pushSubscription, {
    subject: env.VAPID_SUBJECT,
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: env.VAPID_PRIVATE_KEY,
  });
  const current = await env.DB.prepare("SELECT status FROM reminders WHERE id = ?").bind(row.id).first<{ status: string }>();
  if (current?.status !== "sending") return;
  // Workers fetch does not support redirect: "error". Manual redirects keep
  // the encrypted payload from being forwarded to another origin.
  const response = await fetch(subscription.endpoint, { ...payload, redirect: "manual" });
  if (response.ok) {
    await env.DB.prepare("UPDATE reminders SET status = 'sent', locked_until = NULL, updated_at = ? WHERE id = ? AND status = 'sending'").bind(nowIso(), row.id).run();
    return;
  }
  if (response.status === 404 || response.status === 410) {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM push_subscriptions WHERE installation_id = ? AND version = ?").bind(row.installation_id, subscription.version),
      env.DB.prepare("UPDATE reminders SET status = 'failed', last_error = 'subscription_expired', updated_at = ? WHERE id = ? AND status = 'sending'").bind(nowIso(), row.id),
    ]);
    return;
  }
  if (response.status === 401 || response.status === 403) throw new Error("Push provider rejected VAPID configuration");
  throw new Error(`Push provider returned ${response.status}`);
}

export default {
  fetch: handleWebRequest,
  scheduled(_controller: ScheduledController, env: Env, context: ExecutionContext) {
    context.waitUntil(enqueueDue(env));
  },
  async queue(batch: MessageBatch<ReminderMessage>, env: Env) {
    for (const message of batch.messages) {
      try {
        await deliver(message, env);
        message.ack();
      } catch (error) {
        const row = await env.DB.prepare("SELECT attempts, departure_at FROM reminders WHERE id = ?").bind(message.body.reminderId).first<{ attempts: number; departure_at: string }>();
        const retry = row && row.attempts < 3 && new Date(row.departure_at) > new Date();
        if (retry) {
          await env.DB.prepare("UPDATE reminders SET status = 'queued', locked_until = ?, last_error = 'temporary', updated_at = ? WHERE id = ? AND status = 'sending'")
            .bind(new Date(Date.now() + 60_000).toISOString(), nowIso(), message.body.reminderId).run();
          message.retry({ delaySeconds: 60 });
        } else {
          await env.DB.prepare("UPDATE reminders SET status = 'failed', last_error = 'delivery', updated_at = ? WHERE id = ? AND status = 'sending'")
            .bind(nowIso(), message.body.reminderId).run();
          message.ack();
        }
        console.error("Push delivery failed", error instanceof Error ? error.message : "unknown error");
      }
    }
  },
};
