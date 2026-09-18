interface Env {
  LTA_ACCOUNT_KEY?: string;
  APP_API_KEY?: string;
  APP_API_KEY_PREVIOUS?: string;
}

type Direction = "forettToBeautyWorld" | "beautyWorldToForett";

const STOP_CONFIG: Record<Direction, { code: string; name: string }> = {
  forettToBeautyWorld: { code: "42221", name: "Forett @ Bt Timah" },
  beautyWorldToForett: { code: "42151", name: "Beauty World Stn Exit C" },
};
const SERVICES = new Set(["41", "77"]);
const LTA_URL = "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival";
const CACHE_SECONDS = 20;

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "Authorization, Content-Type",
  "access-control-allow-methods": "GET, OPTIONS",
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
      return typeof service === "object" && service !== null && SERVICES.has(String((service as { ServiceNo?: unknown }).ServiceNo));
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
  if (url.pathname !== "/v1/arrivals") {
    return json({ error: "Not found" }, 404, { "cache-control": "no-store" });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: jsonHeaders });
  }
  if (request.method !== "GET") {
    return json({ error: "Method not allowed" }, 405, {
      allow: "GET, OPTIONS",
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

  const direction = parseDirection(url.searchParams.get("direction"));
  if (!direction) {
    return json({ error: "Invalid direction" }, 400, {
      "cache-control": "no-store",
    });
  }

  const stop = STOP_CONFIG[direction];
  const cacheKey = new Request(
    `${url.origin}/v1/arrivals?direction=${direction}`,
  );
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  let normalized;
  try {
    normalized = normalizeLta(await fetchLta(stop.code, env), direction, stop);
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
