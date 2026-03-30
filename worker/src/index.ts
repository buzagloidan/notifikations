import { Hono, type Context } from "hono";
import type {
  Env,
  NotificationPayload,
  RegisterBody,
  RcWebhookPayload,
  RotateBody,
  RotateUserBody,
  UnregisterBody,
  UpdateStatusBody,
  CreateWebhookBody,
  DeleteWebhookBody,
} from "./lib/types";
import { sha256Hex, isValidDigest } from "./lib/hash";
import {
  getDevice,
  setDevice,
  deleteDevice,
  getUserDevices,
  addDeviceToUser,
  removeDeviceFromUser,
  setUserDevices,
  getTokenMapping,
  setTokenMapping,
  deleteTokenMapping,
  getRcUserDevice,
  setRcUserDevice,
  deleteRcUserDevice,
  getWebhook,
  setWebhook,
  deleteWebhook,
  getOwnerWebhooks,
  setOwnerWebhooks,
  addWebhookToOwner,
  removeWebhookFromOwner,
  MAX_NAMED_WEBHOOKS_PER_DEVICE,
  setScheduledJob,
  deleteScheduledJob,
  listDueJobs,
  countPendingJobsForDigest,
  MAX_PENDING_JOBS_PER_DIGEST,
  MAX_SCHEDULE_DAYS,
} from "./lib/kv";
import { sendPushNotification } from "./lib/apns";

const app = new Hono<{ Bindings: Env }>();

// Constant-time string comparison — guards against timing attacks on secrets.
// crypto.subtle.timingSafeEqual throws if buffers differ in length, so we
// always compare equal-length buffers and check length separately.
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aBytes = enc.encode(a);
  const bBytes = enc.encode(b);
  if (aBytes.length !== bBytes.length) {
    // Run a dummy comparison so execution time doesn't reveal the length mismatch.
    crypto.subtle.timingSafeEqual(aBytes, aBytes);
    return false;
  }
  return crypto.subtle.timingSafeEqual(aBytes, bBytes);
}

// ── Register ───────────────────────────────────────────────────────────────

app.post("/api/v1/register", async (c) => {
  let body: RegisterBody;
  try {
    body = await c.req.json<RegisterBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { deviceToken, deviceDigest, userDigest, label, rcUserId } = body;

  if (!deviceToken || !deviceDigest || !userDigest) {
    return c.json({ error: "deviceToken, deviceDigest, and userDigest are required" }, 400);
  }

  if (!isValidDigest(deviceDigest) || !isValidDigest(userDigest)) {
    return c.json({ error: "invalid digest format" }, 400);
  }

  const kv = c.env.NTF_KV;
  const previous = await getTokenMapping(kv, deviceToken);
  await Promise.all([
    previous &&
    (previous.userDigest !== userDigest || previous.deviceDigest !== deviceDigest)
      ? removeDeviceFromUser(kv, previous.userDigest, previous.deviceDigest)
      : Promise.resolve(),
    setDevice(kv, deviceDigest, { deviceToken, label, createdAt: new Date().toISOString(), rcUserId }),
    addDeviceToUser(kv, userDigest, deviceDigest),
    setTokenMapping(kv, deviceToken, userDigest, deviceDigest),
    rcUserId ? setRcUserDevice(kv, rcUserId, deviceDigest) : Promise.resolve(),
  ]);

  return c.json({ success: true });
});

// ── Unregister ─────────────────────────────────────────────────────────────

app.delete("/api/v1/unregister", async (c) => {
  let body: UnregisterBody;
  try {
    body = await c.req.json<UnregisterBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { deviceDigest, deviceToken } = body;
  if (!deviceDigest || !deviceToken) {
    return c.json({ error: "deviceDigest and deviceToken are required" }, 400);
  }

  const kv = c.env.NTF_KV;
  const existing = await getDevice(kv, deviceDigest);
  if (!existing || existing.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  const [mapping, ownedWebhookDigests] = await Promise.all([
    getTokenMapping(kv, existing.deviceToken),
    getOwnerWebhooks(kv, deviceDigest),
  ]);

  await Promise.all([
    deleteDevice(kv, deviceDigest),
    deleteTokenMapping(kv, existing.deviceToken),
    mapping
      ? removeDeviceFromUser(kv, mapping.userDigest, deviceDigest)
      : Promise.resolve(),
    existing.rcUserId ? deleteRcUserDevice(kv, existing.rcUserId) : Promise.resolve(),
    // Delete all named webhooks owned by this device
    ...ownedWebhookDigests.map((wd) => deleteWebhook(kv, wd)),
    ownedWebhookDigests.length > 0 ? kv.delete(`webhooks:${deviceDigest}`) : Promise.resolve(),
  ]);

  return c.json({ success: true });
});

// ── Rotate ─────────────────────────────────────────────────────────────────

app.post("/api/v1/rotate", async (c) => {
  let body: RotateBody;
  try {
    body = await c.req.json<RotateBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { oldDigest, newDigest, deviceToken } = body;
  if (!oldDigest || !newDigest || !deviceToken) {
    return c.json({ error: "oldDigest, newDigest, and deviceToken are required" }, 400);
  }

  const kv = c.env.NTF_KV;
  const existing = await getDevice(kv, oldDigest);
  if (!existing || existing.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  const [mapping, ownedWebhookDigests] = await Promise.all([
    getTokenMapping(kv, deviceToken),
    getOwnerWebhooks(kv, oldDigest),
  ]);

  await Promise.all([
    // Intentionally preserves createdAt so that rotating a secret cannot
    // reset or extend the free-trial window.
    setDevice(kv, newDigest, { ...existing }),
    deleteDevice(kv, oldDigest),
    mapping
      ? (async () => {
          await removeDeviceFromUser(kv, mapping.userDigest, oldDigest);
          await addDeviceToUser(kv, mapping.userDigest, newDigest);
          await setTokenMapping(kv, deviceToken, mapping.userDigest, newDigest);
        })()
      : deleteTokenMapping(kv, deviceToken),
    // Re-key named webhooks: update ownerDigest in each record + move the index
    ownedWebhookDigests.length > 0
      ? (async () => {
          await Promise.all(
            ownedWebhookDigests.map(async (wd) => {
              const rec = await getWebhook(kv, wd);
              if (rec) await setWebhook(kv, wd, { ...rec, ownerDigest: newDigest });
            })
          );
          await setOwnerWebhooks(kv, newDigest, ownedWebhookDigests);
          await kv.delete(`webhooks:${oldDigest}`);
        })()
      : Promise.resolve(),
  ]);

  return c.json({ success: true });
});

// ── Rotate User Secret (all-devices webhook) ───────────────────────────────

app.post("/api/v1/rotate-user", async (c) => {
  let body: RotateUserBody;
  try {
    body = await c.req.json<RotateUserBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { oldUserDigest, newUserDigest, deviceDigest, deviceToken } = body;
  if (!oldUserDigest || !newUserDigest || !deviceDigest || !deviceToken) {
    return c.json(
      {
        error:
          "oldUserDigest, newUserDigest, deviceDigest, and deviceToken are required",
      },
      400
    );
  }

  if (
    !isValidDigest(oldUserDigest) ||
    !isValidDigest(newUserDigest) ||
    !isValidDigest(deviceDigest)
  ) {
    return c.json({ error: "invalid digest format" }, 400);
  }

  const kv = c.env.NTF_KV;
  const oldDeviceDigests = await getUserDevices(kv, oldUserDigest);
  if (oldDeviceDigests.length === 0 || !oldDeviceDigests.includes(deviceDigest)) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  // Require proof this caller controls a currently registered device in the user set.
  const authDevice = await getDevice(kv, deviceDigest);
  if (!authDevice || authDevice.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  // Preserve any existing targets already tied to the new digest (unlikely but safe).
  const existingNewDigests = await getUserDevices(kv, newUserDigest);
  const mergedDigests = Array.from(new Set([...existingNewDigests, ...oldDeviceDigests]));

  await Promise.all([
    setUserDevices(kv, newUserDigest, mergedDigests),
    kv.delete(`userDigest:${oldUserDigest}`),
    ...oldDeviceDigests.map(async (dd) => {
      const rec = await getDevice(kv, dd);
      if (!rec) return;
      await setTokenMapping(kv, rec.deviceToken, newUserDigest, dd);
    }),
  ]);

  return c.json({
    success: true,
    moved: oldDeviceDigests.length,
  });
});

// ── Update Pro Status ──────────────────────────────────────────────────────

app.post("/api/v1/update-status", async (c) => {
  let body: UpdateStatusBody;
  try {
    body = await c.req.json<UpdateStatusBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { deviceDigest, deviceToken, isPro } = body;
  if (!deviceDigest || !deviceToken || typeof isPro !== "boolean") {
    return c.json({ error: "deviceDigest, deviceToken, and isPro are required" }, 400);
  }

  // Clients may only revoke Pro status (isPro: false). Granting Pro must be
  // done server-side via a RevenueCat webhook hitting a trusted endpoint.
  if (isPro === true) {
    return c.json({ error: "pro_status_cannot_be_granted_by_client" }, 403);
  }

  const kv = c.env.NTF_KV;
  const existing = await getDevice(kv, deviceDigest);
  if (!existing || existing.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  await setDevice(kv, deviceDigest, { ...existing, isPro });
  return c.json({ success: true });
});

// ── Named Webhooks — Create ────────────────────────────────────────────────

app.post("/api/v1/webhooks", async (c) => {
  let body: CreateWebhookBody;
  try {
    body = await c.req.json<CreateWebhookBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { deviceDigest, deviceToken, webhookDigest, label, scope = "device" } = body;

  if (!deviceDigest || !deviceToken || !webhookDigest || !label) {
    return c.json({ error: "deviceDigest, deviceToken, webhookDigest, and label are required" }, 400);
  }
  if (!isValidDigest(deviceDigest) || !isValidDigest(webhookDigest)) {
    return c.json({ error: "invalid digest format" }, 400);
  }
  if (scope !== "device" && scope !== "user") {
    return c.json({ error: "scope must be 'device' or 'user'" }, 400);
  }
  const trimmedLabel = label.trim().slice(0, 64);
  if (!trimmedLabel) {
    return c.json({ error: "label cannot be empty" }, 400);
  }

  const kv = c.env.NTF_KV;

  // Verify caller controls the device
  const device = await getDevice(kv, deviceDigest);
  if (!device || device.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  // Guard against collisions with device/user/existing named webhook digests
  const [collidingDevice, collidingUser, existingWebhook] = await Promise.all([
    getDevice(kv, webhookDigest),
    getUserDevices(kv, webhookDigest),
    getWebhook(kv, webhookDigest),
  ]);
  if (collidingDevice || collidingUser.length > 0 || existingWebhook) {
    return c.json({ error: "webhook digest already in use" }, 409);
  }

  // Enforce per-device limit
  const owned = await getOwnerWebhooks(kv, deviceDigest);
  if (owned.length >= MAX_NAMED_WEBHOOKS_PER_DEVICE) {
    return c.json(
      { error: `too_many_webhooks: max ${MAX_NAMED_WEBHOOKS_PER_DEVICE} named webhooks per device` },
      429
    );
  }

  await Promise.all([
    setWebhook(kv, webhookDigest, {
      ownerDigest: deviceDigest,
      label: trimmedLabel,
      scope,
      createdAt: new Date().toISOString(),
    }),
    addWebhookToOwner(kv, deviceDigest, webhookDigest),
  ]);

  return c.json({ success: true });
});

// ── Named Webhooks — List ──────────────────────────────────────────────────

app.get("/api/v1/webhooks", async (c) => {
  const deviceDigest = c.req.query("deviceDigest");
  const deviceToken = c.req.query("deviceToken");

  if (!deviceDigest || !deviceToken) {
    return c.json({ error: "deviceDigest and deviceToken are required" }, 400);
  }
  if (!isValidDigest(deviceDigest)) {
    return c.json({ error: "invalid digest format" }, 400);
  }

  const kv = c.env.NTF_KV;
  const device = await getDevice(kv, deviceDigest);
  if (!device || device.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }

  const webhookDigests = await getOwnerWebhooks(kv, deviceDigest);
  const webhooks = (
    await Promise.all(
      webhookDigests.map(async (wd) => {
        const rec = await getWebhook(kv, wd);
        if (!rec) return null;
        return { webhookDigest: wd, label: rec.label, scope: rec.scope, createdAt: rec.createdAt };
      })
    )
  ).filter(Boolean);

  return c.json({ webhooks });
});

// ── Named Webhooks — Delete ────────────────────────────────────────────────

app.delete("/api/v1/webhooks/:webhookDigest", async (c) => {
  let body: DeleteWebhookBody;
  try {
    body = await c.req.json<DeleteWebhookBody>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { deviceDigest, deviceToken } = body;
  const webhookDigest = c.req.param("webhookDigest");

  if (!deviceDigest || !deviceToken) {
    return c.json({ error: "deviceDigest and deviceToken are required" }, 400);
  }
  if (!isValidDigest(deviceDigest) || !isValidDigest(webhookDigest)) {
    return c.json({ error: "invalid digest format" }, 400);
  }

  const kv = c.env.NTF_KV;

  const [device, webhook] = await Promise.all([
    getDevice(kv, deviceDigest),
    getWebhook(kv, webhookDigest),
  ]);

  if (!device || device.deviceToken !== deviceToken) {
    return c.json({ error: "not found or unauthorized" }, 404);
  }
  if (!webhook || webhook.ownerDigest !== deviceDigest) {
    return c.json({ error: "webhook not found" }, 404);
  }

  await Promise.all([
    deleteWebhook(kv, webhookDigest),
    removeWebhookFromOwner(kv, deviceDigest, webhookDigest),
  ]);

  return c.json({ success: true });
});

// ── Scheduled job dispatcher (shared by webhook handler + cron) ────────────

async function dispatchToDevice(
  deviceDigest: string,
  payload: NotificationPayload,
  env: Env
): Promise<{ blocked?: boolean; result?: Awaited<ReturnType<typeof sendPushNotification>> }> {
  const rec = await getDevice(env.NTF_KV, deviceDigest);
  if (!rec) return {};
  if (!rec.isPro && !isTrialActive(rec.createdAt)) return { blocked: true };
  return { result: await sendPushNotification(rec.deviceToken, payload, env) };
}

// ── Trial helper ───────────────────────────────────────────────────────────

const TRIAL_DAYS = 14;

function isTrialActive(createdAt: string): boolean {
  const trialEndMs = new Date(createdAt).getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000;
  return Date.now() <= trialEndMs;
}

// ── Fan-out helper ─────────────────────────────────────────────────────────

async function fanOutToDevices(
  deviceDigests: string[],
  payload: NotificationPayload,
  env: Env
): Promise<{ blocked: number; results: PromiseSettledResult<Awaited<ReturnType<typeof sendPushNotification>> | undefined>[] }> {
  let blocked = 0;
  const results = await Promise.allSettled(
    deviceDigests.map(async (dd) => {
      const rec = await getDevice(env.NTF_KV, dd);
      if (!rec) return undefined;
      if (!rec.isPro && !isTrialActive(rec.createdAt)) {
        blocked++;
        return undefined;
      }
      return sendPushNotification(rec.deviceToken, payload, env);
    })
  );
  return { blocked, results };
}

// ── Webhook — send notification ────────────────────────────────────────────

async function handleWebhook(c: Context<{ Bindings: Env }, "/api/v1/:secret">) {
  const secret = c.req.param("secret");
  let payload: NotificationPayload;

  if (c.req.method === "GET") {
    const message = c.req.query("message");
    if (!message) return c.json({ error: "message is required" }, 400);
    payload = {
      message,
      title: c.req.query("title") ?? undefined,
      subtitle: c.req.query("subtitle") ?? undefined,
      sound: c.req.query("sound") ?? undefined,
      open_url: c.req.query("open_url") ?? undefined,
      image_url: c.req.query("image_url") ?? undefined,
      thread_id: c.req.query("thread_id") ?? undefined,
      "interruption-level":
        (c.req.query("interruption-level") as NotificationPayload["interruption-level"]) ?? undefined,
      "filter-criteria": c.req.query("filter-criteria") ?? undefined,
      category: (c.req.query("category") as NotificationPayload["category"]) ?? undefined,
      callback_url: c.req.query("callback_url") ?? undefined,
    };
  } else {
    const contentType = c.req.header("content-type") ?? "";
    if (contentType.includes("application/json")) {
      const body = await c.req.json<NotificationPayload>();
      if (!body.message) return c.json({ error: "message is required" }, 400);
      payload = body;
    } else {
      const text = (await c.req.text()).trim();
      if (!text) return c.json({ error: "message is required" }, 400);
      payload = { message: text };
    }
  }

  const kv = c.env.NTF_KV;
  const digest = await sha256Hex(secret);

  // ── Scheduled delivery ─────────────────────────────────────────────────
  const sendAtRaw =
    c.req.method === "GET"
      ? c.req.query("send_at")
      : (payload as NotificationPayload & { send_at?: string }).send_at;

  if (sendAtRaw !== undefined) {
    const sendAt = new Date(sendAtRaw);
    if (isNaN(sendAt.getTime()) || sendAt <= new Date()) {
      return c.json({ error: "send_at must be a valid future ISO 8601 timestamp" }, 400);
    }
    const maxAt = new Date(Date.now() + MAX_SCHEDULE_DAYS * 24 * 60 * 60 * 1000);
    if (sendAt > maxAt) {
      return c.json({ error: `send_at cannot be more than ${MAX_SCHEDULE_DAYS} days in the future` }, 400);
    }

    // Verify the digest is known before accepting the job
    const knownDevice = await getDevice(kv, digest);
    const knownUser = knownDevice ? null : await getUserDevices(kv, digest);
    const knownWebhook = !knownDevice && (!knownUser || knownUser.length === 0)
      ? await getWebhook(kv, digest)
      : null;
    if (!knownDevice && (!knownUser || knownUser.length === 0) && !knownWebhook) {
      return c.json({ error: "webhook not found" }, 404);
    }

    const pending = await countPendingJobsForDigest(kv, digest);
    if (pending >= MAX_PENDING_JOBS_PER_DIGEST) {
      return c.json({ error: `too_many_scheduled: max ${MAX_PENDING_JOBS_PER_DIGEST} pending jobs per webhook` }, 429);
    }

    const jobId = crypto.randomUUID();
    const sendAtIso = sendAt.toISOString();
    // Strip send_at from the stored payload
    const { send_at: _removed, ...storedPayload } = payload as NotificationPayload & { send_at?: string };
    await setScheduledJob(kv, sendAtIso, jobId, { digest, payload: storedPayload, createdAt: new Date().toISOString() });
    return c.json({ success: true, scheduled: true, jobId, sendAt: sendAtIso });
  }

  // Try as device digest
  const deviceRecord = await getDevice(kv, digest);
  if (deviceRecord) {
    if (!deviceRecord.isPro && !isTrialActive(deviceRecord.createdAt)) {
      return c.json(
        { error: "trial_expired", message: "Upgrade to Notifikations Pro to continue receiving notifications." },
        402
      );
    }
    const result = await sendPushNotification(deviceRecord.deviceToken, payload, c.env);
    if (!result.success) {
      return c.json(
        {
          error: result.error,
          reason: result.reason,
          apnsId: result.apnsId,
          statusCode: result.statusCode,
        },
        502
      );
    }
    return c.json({ success: true, apnsId: result.apnsId });
  }

  // Try as user digest (fan-out to all devices)
  const userDeviceDigests = await getUserDevices(kv, digest);
  if (userDeviceDigests.length > 0) {
    return fanOutResponse(await fanOutToDevices(userDeviceDigests, payload, c.env), c);
  }

  // Try as named webhook digest
  const namedWebhook = await getWebhook(kv, digest);
  if (namedWebhook) {
    if (namedWebhook.scope === "device") {
      const rec = await getDevice(kv, namedWebhook.ownerDigest);
      if (!rec) return c.json({ error: "webhook not found" }, 404);
      if (!rec.isPro && !isTrialActive(rec.createdAt)) {
        return c.json(
          { error: "trial_expired", message: "Upgrade to Notifikations Pro to continue receiving notifications." },
          402
        );
      }
      const result = await sendPushNotification(rec.deviceToken, payload, c.env);
      if (!result.success) {
        return c.json(
          { error: result.error, reason: result.reason, apnsId: result.apnsId, statusCode: result.statusCode },
          502
        );
      }
      return c.json({ success: true, apnsId: result.apnsId });
    } else {
      // user scope: fan-out to all devices sharing the owner's user secret
      const ownerDevice = await getDevice(kv, namedWebhook.ownerDigest);
      if (!ownerDevice) return c.json({ error: "webhook not found" }, 404);
      const mapping = await getTokenMapping(kv, ownerDevice.deviceToken);
      const targetDigests = mapping
        ? await getUserDevices(kv, mapping.userDigest)
        : [namedWebhook.ownerDigest];
      if (targetDigests.length === 0) return c.json({ error: "webhook not found" }, 404);
      return fanOutResponse(await fanOutToDevices(targetDigests, payload, c.env), c);
    }
  }

  return c.json({ error: "webhook not found" }, 404);
}

function fanOutResponse(
  { blocked, results }: Awaited<ReturnType<typeof fanOutToDevices>>,
  c: Context<{ Bindings: Env }>
) {
  const attempted = results.filter((r) => r.status === "fulfilled" && r.value !== undefined);
  if (attempted.length === 0) {
    return c.json(
      { error: "trial_expired", message: "Upgrade to Notifikations Pro to continue receiving notifications." },
      402
    );
  }
  const failures = results.filter((r) => r.status === "fulfilled" && r.value && !r.value.success);
  const rejected = results.filter((r) => r.status === "rejected");
  const firstFailure =
    failures.length > 0 && failures[0].status === "fulfilled" ? failures[0].value : undefined;
  return c.json({
    success: failures.length === 0 && rejected.length === 0,
    sent: attempted.length,
    blocked,
    failures: failures.length,
    rejected: rejected.length,
    firstFailure: firstFailure
      ? { error: firstFailure.error, reason: firstFailure.reason, apnsId: firstFailure.apnsId, statusCode: firstFailure.statusCode }
      : undefined,
  });
}

// ── RevenueCat server-to-server webhook ────────────────────────────────────
// Grants/revokes Pro status based on subscription events.
// Set up in RevenueCat Dashboard → Project Settings → Webhooks.
// Secret must match the RC_WEBHOOK_SECRET Wrangler secret.

const RC_PRO_GRANT_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
]);

const RC_PRO_REVOKE_EVENTS = new Set([
  "CANCELLATION",
  "EXPIRATION",
  "BILLING_ISSUE",
]);

app.post("/api/v1/webhook/revenuecat", async (c) => {
  const auth = c.req.header("authorization") ?? "";
  if (!c.env.RC_WEBHOOK_SECRET || !timingSafeEqual(auth, c.env.RC_WEBHOOK_SECRET)) {
    return c.json({ error: "unauthorized" }, 401);
  }

  let body: RcWebhookPayload;
  try {
    body = await c.req.json<RcWebhookPayload>();
  } catch {
    return c.json({ error: "invalid JSON" }, 400);
  }

  const { type, app_user_id } = body.event;

  const isPro = RC_PRO_GRANT_EVENTS.has(type);
  const isRevoke = RC_PRO_REVOKE_EVENTS.has(type);

  if (!isPro && !isRevoke) {
    return c.json({ success: true, ignored: true });
  }

  const kv = c.env.NTF_KV;
  const deviceDigest = await getRcUserDevice(kv, app_user_id);
  if (!deviceDigest) {
    return c.json({ error: "device not found for rc user" }, 404);
  }

  const device = await getDevice(kv, deviceDigest);
  if (!device) {
    return c.json({ error: "device record missing" }, 404);
  }

  await setDevice(kv, deviceDigest, { ...device, isPro });
  return c.json({ success: true, isPro });
});

app.get("/api/v1/:secret", handleWebhook);
app.post("/api/v1/:secret", handleWebhook);

// Redirect bare domain visits to the marketing site
app.all("*", (c) => c.redirect("https://notifikations.com", 301));

// ── Cron handler — fires due scheduled jobs ────────────────────────────────

export default {
  fetch: app.fetch,

  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    const due = await listDueJobs(env.NTF_KV, new Date());
    ctx.waitUntil(
      Promise.allSettled(
        due.map(async ({ sendAt, jobId, job }) => {
          const { digest, payload } = job;
          // Delete first — prevents double-fire if cron overlaps
          await deleteScheduledJob(env.NTF_KV, sendAt, jobId, digest);

          // Try as device digest
          const deviceRecord = await getDevice(env.NTF_KV, digest);
          if (deviceRecord) {
            await dispatchToDevice(digest, payload, env);
            return;
          }

          // Try as user digest (fan-out)
          const deviceDigests = await getUserDevices(env.NTF_KV, digest);
          if (deviceDigests.length > 0) {
            await Promise.allSettled(deviceDigests.map((dd) => dispatchToDevice(dd, payload, env)));
            return;
          }

          // Try as named webhook digest
          const namedWebhook = await getWebhook(env.NTF_KV, digest);
          if (namedWebhook) {
            if (namedWebhook.scope === "device") {
              await dispatchToDevice(namedWebhook.ownerDigest, payload, env);
            } else {
              const ownerDevice = await getDevice(env.NTF_KV, namedWebhook.ownerDigest);
              if (ownerDevice) {
                const mapping = await getTokenMapping(env.NTF_KV, ownerDevice.deviceToken);
                const targetDigests = mapping
                  ? await getUserDevices(env.NTF_KV, mapping.userDigest)
                  : [namedWebhook.ownerDigest];
                await Promise.allSettled(targetDigests.map((dd) => dispatchToDevice(dd, payload, env)));
              }
            }
          }
        })
      )
    );
  },
};
