import type { Env, NotificationPayload } from "./types";

export interface ApnsResult {
  success: boolean;
  apnsId?: string;
  error?: string;
  reason?: string;
  statusCode?: number;
  host?: string;
}

// Module-level caches — valid for the lifetime of the isolate
let cachedKey: CryptoKey | null = null;
let cachedKeySource = "";
// APNs rejects provider tokens updated more than once per 20 minutes
let cachedJwt = "";
let cachedJwtIat = 0;
const JWT_MAX_AGE_SECONDS = 15 * 60; // refresh after 15 min (expires at 60 min)

async function importApnsKey(p8Base64: string): Promise<CryptoKey> {
  if (cachedKey && cachedKeySource === p8Base64) return cachedKey;

  // Decode base64 → PEM text
  const pem = atob(p8Base64);

  // Strip PEM headers/footers and whitespace → raw base64
  const rawB64 = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s/g, "");

  // Decode to DER bytes
  const der = Uint8Array.from(atob(rawB64), (c) => c.charCodeAt(0));

  cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  cachedKeySource = p8Base64;
  return cachedKey;
}

function b64url(data: string): string {
  return btoa(data).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

async function makeJwt(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwtIat < JWT_MAX_AGE_SECONDS) return cachedJwt;

  const key = await importApnsKey(env.APNS_KEY_P8);

  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const payload = b64url(
    JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now })
  );

  const unsigned = `${header}.${payload}`;
  const signatureBuffer = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned)
  );

  const sig = b64url(String.fromCharCode(...new Uint8Array(signatureBuffer)));
  cachedJwt = `${unsigned}.${sig}`;
  cachedJwtIat = now;
  return cachedJwt;
}

function resolveApnsHost(apnsEnv: string | undefined): string {
  // Default to production so TestFlight/App Store tokens work even if APNS_ENV
  // is missing or misconfigured.
  const normalized = apnsEnv?.trim().toLowerCase();
  if (normalized === "sandbox" || normalized === "development") {
    return "api.sandbox.push.apple.com";
  }
  return "api.push.apple.com";
}

export async function sendPushNotification(
  deviceToken: string,
  payload: NotificationPayload,
  env: Env
): Promise<ApnsResult> {
  const host = resolveApnsHost(env.APNS_ENV);

  const jwt = await makeJwt(env);
  const body = JSON.stringify(buildApsPayload(payload));

  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    "apns-topic": env.APNS_BUNDLE_ID,
    "apns-push-type": "alert",
    "content-type": "application/json",
  };

  if (payload["interruption-level"]) {
    headers["apns-priority"] = payload["interruption-level"] === "passive" ? "5" : "10";
  }
  if (payload.expiration_date) {
    const ts = Math.floor(new Date(payload.expiration_date).getTime() / 1000);
    if (!isNaN(ts)) {
      headers["apns-expiration"] = String(ts);
    }
  }

  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers,
    body,
  });

  const apnsId = response.headers.get("apns-id") ?? undefined;

  if (response.ok) {
    return { success: true, apnsId, statusCode: response.status, host };
  }

  let apnsReason: string | undefined;
  let errorReason = `HTTP ${response.status}`;
  try {
    const json = (await response.json()) as { reason?: string };
    if (json.reason) {
      apnsReason = json.reason;
      errorReason = json.reason;
    }
  } catch {
    // Not JSON (or already consumed); include status fallback only.
  }

  return {
    success: false,
    error: errorReason,
    reason: apnsReason,
    apnsId,
    statusCode: response.status,
    host,
  };
}

// Only allow alphanumeric, hyphen, underscore — prevents path traversal in sound names.
const SAFE_SOUND_BASE_RE = /^[a-zA-Z0-9_-]{1,64}$/;

function sanitizeSound(sound: string): string | undefined {
  const s = sound.trim();
  if (s === "default" || s === "system") return "default";
  const base = s.endsWith(".caf") ? s.slice(0, -4) : s;
  if (!SAFE_SOUND_BASE_RE.test(base)) return undefined;
  return `${base}.caf`;
}

// Enforce https:// to prevent device-side SSRF via Notification Service Extensions.
function isSafeUrl(url: string): boolean {
  try {
    return new URL(url).protocol === "https:";
  } catch {
    return false;
  }
}

function buildApsPayload(payload: NotificationPayload): Record<string, unknown> {
  const alert: Record<string, string> = { body: payload.message };
  if (payload.title) alert.title = payload.title;
  if (payload.subtitle) alert.subtitle = payload.subtitle;

  const aps: Record<string, unknown> = { alert, "content-available": 1 };

  if (payload.sound && payload.sound !== "none") {
    const safe = sanitizeSound(payload.sound);
    if (safe) aps.sound = safe;
  }

  if (payload["interruption-level"]) {
    aps["interruption-level"] = payload["interruption-level"];
  }

  if (payload.thread_id) {
    aps["thread-id"] = payload.thread_id;
  }

  if (payload["filter-criteria"]) {
    aps["filter-criteria"] = payload["filter-criteria"];
  }

  if (payload.category) {
    aps.category = payload.category;
  }

  const result: Record<string, unknown> = { aps };
  if (payload.open_url && isSafeUrl(payload.open_url)) result.open_url = payload.open_url;
  if (payload.image_url && isSafeUrl(payload.image_url)) result.image_url = payload.image_url;
  if (payload.callback_url && isSafeUrl(payload.callback_url)) result.callback_url = payload.callback_url;

  return result;
}
