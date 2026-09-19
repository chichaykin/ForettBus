interface Env {
  LTA_ACCOUNT_KEY?: string;
  APP_API_KEY?: string;
  APP_API_KEY_PREVIOUS?: string;
  ONEMAP_TOKEN?: string;
}

type Direction = "forettToBeautyWorld" | "beautyWorldToForett";

const STOP_CONFIG: Record<Direction, { code: string; name: string }> = {
  forettToBeautyWorld: { code: "42221", name: "Forett @ Bt Timah" },
  beautyWorldToForett: { code: "42151", name: "Beauty World Stn Exit C" },
};
const LEGACY_SERVICES = new Set(["41", "77"]);
const LTA_URL = "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival";
const CACHE_SECONDS = 20;

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "Authorization, Content-Type",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

function json(data: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...jsonHeaders, ...extra },
  });
}

export function isAuthorized(request: Request, env: Env): boolean {
  const header = request.headers.get("Authorization");
  if (!header?.startsWith("Bearer ")) return false;
  const supplied = header.slice("Bearer ".length).trim();
  if (!supplied) return false;
  return supplied === env.APP_API_KEY || supplied === env.APP_API_KEY_PREVIOUS;
}

function parseDirection(value: string | null): Direction | null {
  return value === "forettToBeautyWorld" || value === "beautyWorldToForett"
    ? value
    : null;
}

async function fetchLta(stopCode: string, env: Env): Promise<unknown> {
  if (!env.LTA_ACCOUNT_KEY) throw new Error("LTA_ACCOUNT_KEY is not configured");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch(`${LTA_URL}?BusStopCode=${stopCode}`, {
      headers: { AccountKey: env.LTA_ACCOUNT_KEY, accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`LTA returned HTTP ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchLtaDataset(path: string, env: Env): Promise<unknown> {
  if (!env.LTA_ACCOUNT_KEY) throw new Error("LTA_ACCOUNT_KEY is not configured");
  const response = await fetch(`https://datamall2.mytransport.sg/ltaodataservice/${path}`, {
    headers: { AccountKey: env.LTA_ACCOUNT_KEY, accept: "application/json" },
  });
  if (!response.ok) throw new Error(`LTA returned HTTP ${response.status}`);
  return await response.json();
}

async function fetchOneMap(url: URL, env: Env): Promise<unknown> {
  if (!env.ONEMAP_TOKEN) throw new Error("ONEMAP_TOKEN is not configured");
  const response = await fetch(url, {
    headers: { Authorization: env.ONEMAP_TOKEN, accept: "application/json" },
  });
  if (!response.ok) throw new Error(`OneMap returned HTTP ${response.status}`);
  return await response.json();
}

function parseServices(value: string | null): Set<string> | null {
  if (!value) return null;
  return new Set(value.split(",").map((service) => service.trim()).filter((service) => /^[0-9]{1,4}[A-Za-z]?$/.test(service)));
}

function normalizeArrivals(source: unknown, stop: { code: string; name: string }, services: Set<string> | null) {
  if (!source || typeof source !== "object") throw new Error("Invalid LTA response");
  const sourceServices = (source as { Services?: unknown }).Services;
  if (!Array.isArray(sourceServices)) throw new Error("Invalid LTA services response");
  const routes = sourceServices
    .filter((service): service is Record<string, unknown> => {
      return typeof service === "object" && service !== null && (!services || services.has(String((service as { ServiceNo?: unknown }).ServiceNo)));
    })
    .map((service) => {
      const arrivals = ["NextBus", "NextBus2", "NextBus3"]
        .map((key) => service[key])
        .filter((bus): bus is Record<string, unknown> => typeof bus === "object" && bus !== null)
        .map((bus) => {
          const timestamp = bus.EstimatedArrival;
          if (typeof timestamp !== "string" || !timestamp) return null;
          return { estimatedArrival: timestamp, monitored: String(bus.Monitored) === "1" };
        })
        .filter((bus): bus is { estimatedArrival: string; monitored: boolean } => bus !== null);
      return { serviceNo: String(service.ServiceNo), arrivals };
    })
    .sort((a, b) => Number(a.serviceNo) - Number(b.serviceNo));
  return { stop, fetchedAt: new Date().toISOString(), routes };
}

function parseOneMapRoute(source: unknown): unknown {
  if (!source || typeof source !== "object") throw new Error("Invalid OneMap response");
  const root = source as { plan?: { itineraries?: unknown[] } };
  const itineraries = root.plan?.itineraries;
  if (!Array.isArray(itineraries)) throw new Error("OneMap returned no itineraries");
  return itineraries.slice(0, 3);
}

export function normalizeLta(
  source: unknown,
  direction: Direction,
  stop: { code: string; name: string },
) {
  if (!source || typeof source !== "object") throw new Error("Invalid LTA response");
  const services = (source as { Services?: unknown }).Services;
  if (!Array.isArray(services)) throw new Error("Invalid LTA services response");

  const routes = services
    .filter((service): service is Record<string, unknown> => {
      return typeof service === "object" && service !== null && LEGACY_SERVICES.has(String((service as { ServiceNo?: unknown }).ServiceNo));
    })
    .map((service) => {
      const arrivals = ["NextBus", "NextBus2", "NextBus3"]
        .map((key) => service[key])
        .filter((bus): bus is Record<string, unknown> => typeof bus === "object" && bus !== null)
        .map((bus) => {
          const timestamp = bus.EstimatedArrival;
          if (typeof timestamp !== "string" || !timestamp) return null;
          return {
            estimatedArrival: timestamp,
            monitored: String(bus.Monitored) === "1",
          };
        })
        .filter((bus): bus is { estimatedArrival: string; monitored: boolean } => bus !== null);
      return { serviceNo: String(service.ServiceNo), arrivals };
    })
    .sort((a, b) => Number(a.serviceNo) - Number(b.serviceNo));

  return {
    direction,
    stop,
    fetchedAt: new Date().toISOString(),
    routes,
  };
}

export default {
  fetch: handleRequest,
};

export async function handleRequest(
  request: Request,
  env: Env,
): Promise<Response> {
  const url = new URL(request.url);
  const supportedPath = url.pathname === "/v1/arrivals" ||
    url.pathname === "/v1/stops/search" ||
    url.pathname === "/v1/stops" ||
    url.pathname === "/v1/trips/plan";
  if (!supportedPath) {
    return json({ error: "Not found" }, 404, { "cache-control": "no-store" });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: jsonHeaders });
  }
  const methodAllowed = url.pathname === "/v1/trips/plan"
    ? request.method === "POST"
    : request.method === "GET";
  if (!methodAllowed) {
    return json({ error: "Method not allowed" }, 405, {
      allow: url.pathname === "/v1/trips/plan" ? "POST, OPTIONS" : "GET, OPTIONS",
      "cache-control": "no-store",
    });
  }

  // Authorization deliberately runs before cache lookup and before any LTA call.
  if (!env.APP_API_KEY && !env.APP_API_KEY_PREVIOUS) {
    return json({ error: "API authentication is not configured" }, 503, {
      "cache-control": "no-store",
    });
  }
  if (!isAuthorized(request, env)) {
    return json({ error: "Unauthorized" }, 401, {
      "cache-control": "no-store",
    });
  }

  if (url.pathname === "/v1/stops/search") {
    const query = url.searchParams.get("q")?.trim();
    if (!query || query.length < 2) return json({ error: "Search query is required" }, 400, { "cache-control": "no-store" });
    try {
      const searchUrl = new URL("https://www.onemap.gov.sg/api/common/elastic/search");
      searchUrl.searchParams.set("searchVal", query);
      searchUrl.searchParams.set("returnGeom", "Y");
      searchUrl.searchParams.set("getAddrDetails", "Y");
      const source = await fetchOneMap(searchUrl, env);
      return json(source, 200, { "cache-control": "public, max-age=300" });
    } catch (_) {
      return json({ error: "Place search unavailable" }, 502, { "cache-control": "no-store" });
    }
  }

  if (url.pathname === "/v1/stops") {
    const query = url.searchParams.get("search")?.trim().toLowerCase();
    if (!query || query.length < 2) return json({ error: "Stop search is required" }, 400, { "cache-control": "no-store" });
    const cacheKey = new Request(`${url.origin}/v1/stops?search=${encodeURIComponent(query)}`);
    const cached = await caches.default.match(cacheKey);
    if (cached) return cached;
    try {
      const matches: Array<{ code: string; name: string; road: string; latitude: number; longitude: number }> = [];
      for (let skip = 0; skip < 2_000 && matches.length < 20; skip += 500) {
        const source = await fetchLtaDataset(`BusStops?$skip=${skip}`, env);
        const values = source && typeof source === "object" && Array.isArray((source as { value?: unknown }).value)
          ? (source as { value: Array<Record<string, unknown>> }).value
          : [];
        for (const stop of values) {
          const name = String(stop.Description ?? "");
          const road = String(stop.RoadName ?? "");
          if (!`${name} ${road} ${stop.BusStopCode ?? ""}`.toLowerCase().includes(query)) continue;
          matches.push({
            code: String(stop.BusStopCode ?? ""),
            name,
            road,
            latitude: Number(stop.Latitude),
            longitude: Number(stop.Longitude),
          });
          if (matches.length >= 20) break;
        }
        if (values.length < 500) break;
      }
      const response = json({ stops: matches }, 200, { "cache-control": "public, max-age=300" });
      await caches.default.put(cacheKey, response.clone());
      return response;
    } catch (_) {
      return json({ error: "Stop search unavailable" }, 502, { "cache-control": "no-store" });
    }
  }

  if (url.pathname === "/v1/trips/plan") {
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, { allow: "POST", "cache-control": "no-store" });
    let body: { start?: string; end?: string; date?: string; time?: string };
    try {
      body = await request.json() as typeof body;
    } catch (_) {
      return json({ error: "Invalid request" }, 400, { "cache-control": "no-store" });
    }
    if (!body.start || !body.end || !body.date || !body.time) return json({ error: "Start, end, date and time are required" }, 400, { "cache-control": "no-store" });
    try {
      const routeUrl = new URL("https://www.onemap.gov.sg/api/public/routingsvc/route");
      routeUrl.searchParams.set("start", body.start);
      routeUrl.searchParams.set("end", body.end);
      routeUrl.searchParams.set("routeType", "pt");
      routeUrl.searchParams.set("mode", "bus");
      routeUrl.searchParams.set("date", body.date);
      routeUrl.searchParams.set("time", body.time);
      routeUrl.searchParams.set("numItineraries", "3");
      routeUrl.searchParams.set("maxWalkDistance", "1500");
      return json({ itineraries: parseOneMapRoute(await fetchOneMap(routeUrl, env)) }, 200, { "cache-control": "public, max-age=60" });
    } catch (_) {
      return json({ error: "Trip planning unavailable" }, 502, { "cache-control": "no-store" });
    }
  }

  const direction = parseDirection(url.searchParams.get("direction"));
  const stopCode = url.searchParams.get("stopCode")?.trim();
  if (!direction && !stopCode) {
    return json({ error: "Direction or stopCode is required" }, 400, { "cache-control": "no-store" });
  }

  if (!direction && !/^\d{5}$/.test(stopCode!)) return json({ error: "Invalid stopCode" }, 400, { "cache-control": "no-store" });

  const stop = direction ? STOP_CONFIG[direction] : { code: stopCode!, name: stopCode! };
  const services = parseServices(url.searchParams.get("services"));
  const cacheKey = new Request(
    `${url.origin}/v1/arrivals?${direction ? `direction=${direction}` : `stopCode=${encodeURIComponent(stop.code)}`}&services=${services ? [...services].sort().join(",") : "all"}`,
  );
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  let normalized;
  try {
    normalized = direction
      ? normalizeLta(await fetchLta(stop.code, env), direction, stop)
      : normalizeArrivals(await fetchLta(stop.code, env), stop, services);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "LTA request failed";
    console.error("LTA arrivals request failed", message);
    const status = message.includes("aborted") ? 504 : 502;
    return json(
      { error: "Upstream arrivals service unavailable" },
      status,
      { "cache-control": "no-store" },
    );
  }

  const response = json(normalized, 200, {
    "cache-control": `public, max-age=${CACHE_SECONDS}`,
  });
  await cache.put(cacheKey, response.clone());
  return response;
}
