import type { DeviceRecord, ScheduledJob, WebhookRecord } from "./types";

// digest:{sha256hex} → DeviceRecord
export async function getDevice(kv: KVNamespace, digest: string): Promise<DeviceRecord | null> {
  const value = await kv.get(`digest:${digest}`);
  return value ? (JSON.parse(value) as DeviceRecord) : null;
}

export async function setDevice(kv: KVNamespace, digest: string, record: DeviceRecord): Promise<void> {
  await kv.put(`digest:${digest}`, JSON.stringify(record));
}

export async function deleteDevice(kv: KVNamespace, digest: string): Promise<void> {
  await kv.delete(`digest:${digest}`);
}

// userDigest:{sha256hex} → string[] (list of device digests)
export async function getUserDevices(kv: KVNamespace, userDigest: string): Promise<string[]> {
  const value = await kv.get(`userDigest:${userDigest}`);
  return value ? (JSON.parse(value) as string[]) : [];
}

export async function setUserDevices(kv: KVNamespace, userDigest: string, devices: string[]): Promise<void> {
  await kv.put(`userDigest:${userDigest}`, JSON.stringify(devices));
}

export async function addDeviceToUser(kv: KVNamespace, userDigest: string, deviceDigest: string): Promise<void> {
  const devices = await getUserDevices(kv, userDigest);
  if (!devices.includes(deviceDigest)) {
    devices.push(deviceDigest);
    await setUserDevices(kv, userDigest, devices);
  }
}

export async function removeDeviceFromUser(kv: KVNamespace, userDigest: string, deviceDigest: string): Promise<void> {
  const devices = await getUserDevices(kv, userDigest);
  const updated = devices.filter((d) => d !== deviceDigest);
  if (updated.length === 0) {
    await kv.delete(`userDigest:${userDigest}`);
  } else {
    await setUserDevices(kv, userDigest, updated);
  }
}

// token:{deviceToken} → { userDigest, deviceDigest }
export interface TokenMapping {
  userDigest: string;
  deviceDigest: string;
}

export async function getTokenMapping(kv: KVNamespace, deviceToken: string): Promise<TokenMapping | null> {
  const value = await kv.get(`token:${deviceToken}`);
  return value ? (JSON.parse(value) as TokenMapping) : null;
}

export async function setTokenMapping(
  kv: KVNamespace,
  deviceToken: string,
  userDigest: string,
  deviceDigest: string
): Promise<void> {
  await kv.put(`token:${deviceToken}`, JSON.stringify({ userDigest, deviceDigest }));
}

export async function deleteTokenMapping(kv: KVNamespace, deviceToken: string): Promise<void> {
  await kv.delete(`token:${deviceToken}`);
}

// sched:{sendAt_iso}:{jobId} → ScheduledJob
// Keys sort lexicographically so the cron can list in order and stop at "now".

const SCHED_PREFIX = "sched:";
const MAX_PENDING_JOBS_PER_DIGEST = 10;
const MAX_SCHEDULE_DAYS = 30;

export function schedKey(sendAt: string, jobId: string): string {
  return `${SCHED_PREFIX}${sendAt}:${jobId}`;
}

// sched_count:{digest} → number  (per-digest pending job counter, spam guard)
async function getScheduledJobCount(kv: KVNamespace, digest: string): Promise<number> {
  const val = await kv.get(`sched_count:${digest}`);
  return val ? parseInt(val, 10) : 0;
}

export async function setScheduledJob(
  kv: KVNamespace,
  sendAt: string,
  jobId: string,
  job: ScheduledJob
): Promise<void> {
  const ttlSeconds = Math.ceil(MAX_SCHEDULE_DAYS * 24 * 60 * 60) + 3600; // 1hr grace
  await kv.put(schedKey(sendAt, jobId), JSON.stringify(job), { expirationTtl: ttlSeconds });
  // Increment per-digest counter (read-modify-write; slight race acceptable for a spam guard)
  const count = await getScheduledJobCount(kv, job.digest);
  await kv.put(`sched_count:${job.digest}`, String(count + 1));
}

export async function deleteScheduledJob(
  kv: KVNamespace,
  sendAt: string,
  jobId: string,
  digest: string
): Promise<void> {
  await kv.delete(schedKey(sendAt, jobId));
  const count = await getScheduledJobCount(kv, digest);
  const next = Math.max(0, count - 1);
  if (next === 0) {
    await kv.delete(`sched_count:${digest}`);
  } else {
    await kv.put(`sched_count:${digest}`, String(next));
  }
}

/** Returns all jobs with sendAt ≤ now, in ascending order. */
export async function listDueJobs(
  kv: KVNamespace,
  now: Date
): Promise<Array<{ sendAt: string; jobId: string; job: ScheduledJob }>> {
  const nowIso = now.toISOString();
  const results: Array<{ sendAt: string; jobId: string; job: ScheduledJob }> = [];
  let cursor: string | undefined;

  do {
    const listed = await kv.list({ prefix: SCHED_PREFIX, cursor, limit: 100 });
    for (const key of listed.keys) {
      // key.name = "sched:{sendAt}:{jobId}"
      const rest = key.name.slice(SCHED_PREFIX.length);
      const colonIdx = rest.indexOf(":");
      const sendAt = rest.slice(0, colonIdx);
      const jobId = rest.slice(colonIdx + 1);
      // Keys are in lexicographic (= chronological) order; once we reach a
      // future key no subsequent keys can be due — stop all pagination.
      if (sendAt > nowIso) return results;
      const raw = await kv.get(key.name);
      if (raw) results.push({ sendAt, jobId, job: JSON.parse(raw) as ScheduledJob });
    }
    cursor = listed.list_complete ? undefined : listed.cursor;
  } while (cursor);

  return results;
}

/** Count pending scheduled jobs for a digest (spam guard).
 *  Reads a single counter key rather than scanning the entire sched: namespace. */
export async function countPendingJobsForDigest(kv: KVNamespace, digest: string): Promise<number> {
  return getScheduledJobCount(kv, digest);
}

export { MAX_PENDING_JOBS_PER_DIGEST, MAX_SCHEDULE_DAYS };

// webhook:{webhookDigest} → WebhookRecord
// webhooks:{ownerDigest}  → string[] (list of webhookDigests owned by this device)

const MAX_NAMED_WEBHOOKS_PER_DEVICE = 10;

export async function getWebhook(kv: KVNamespace, webhookDigest: string): Promise<WebhookRecord | null> {
  const value = await kv.get(`webhook:${webhookDigest}`);
  return value ? (JSON.parse(value) as WebhookRecord) : null;
}

export async function setWebhook(kv: KVNamespace, webhookDigest: string, record: WebhookRecord): Promise<void> {
  await kv.put(`webhook:${webhookDigest}`, JSON.stringify(record));
}

export async function deleteWebhook(kv: KVNamespace, webhookDigest: string): Promise<void> {
  await kv.delete(`webhook:${webhookDigest}`);
}

export async function getOwnerWebhooks(kv: KVNamespace, ownerDigest: string): Promise<string[]> {
  const value = await kv.get(`webhooks:${ownerDigest}`);
  return value ? (JSON.parse(value) as string[]) : [];
}

export async function setOwnerWebhooks(kv: KVNamespace, ownerDigest: string, digests: string[]): Promise<void> {
  await kv.put(`webhooks:${ownerDigest}`, JSON.stringify(digests));
}

export async function addWebhookToOwner(kv: KVNamespace, ownerDigest: string, webhookDigest: string): Promise<void> {
  const existing = await getOwnerWebhooks(kv, ownerDigest);
  if (!existing.includes(webhookDigest)) {
    existing.push(webhookDigest);
    await setOwnerWebhooks(kv, ownerDigest, existing);
  }
}

export async function removeWebhookFromOwner(kv: KVNamespace, ownerDigest: string, webhookDigest: string): Promise<void> {
  const existing = await getOwnerWebhooks(kv, ownerDigest);
  const updated = existing.filter((w) => w !== webhookDigest);
  if (updated.length === 0) {
    await kv.delete(`webhooks:${ownerDigest}`);
  } else {
    await setOwnerWebhooks(kv, ownerDigest, updated);
  }
}

export { MAX_NAMED_WEBHOOKS_PER_DEVICE };

// rcUser:{rcUserId} → deviceDigest
export async function getRcUserDevice(kv: KVNamespace, rcUserId: string): Promise<string | null> {
  return kv.get(`rcUser:${rcUserId}`);
}

export async function setRcUserDevice(kv: KVNamespace, rcUserId: string, deviceDigest: string): Promise<void> {
  await kv.put(`rcUser:${rcUserId}`, deviceDigest);
}

export async function deleteRcUserDevice(kv: KVNamespace, rcUserId: string): Promise<void> {
  await kv.delete(`rcUser:${rcUserId}`);
}
