export interface Env {
  NTF_KV: KVNamespace;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_KEY_P8: string;
  APNS_BUNDLE_ID: string;
  APNS_ENV: string;
  RC_WEBHOOK_SECRET: string;
}

export type NotificationCategory = "YES_NO" | "APPROVE_DISMISS" | "CONFIRM";

export interface NotificationPayload {
  message: string;
  title?: string;
  subtitle?: string;
  sound?: string;
  open_url?: string;
  image_url?: string;
  expiration_date?: string;
  thread_id?: string;
  "filter-criteria"?: string;
  "interruption-level"?: "passive" | "active" | "time-sensitive";
  category?: NotificationCategory;
  callback_url?: string;
}

export interface ScheduledJob {
  digest: string;
  payload: NotificationPayload;
  createdAt: string;
}

export interface DeviceRecord {
  deviceToken: string;
  label?: string;
  createdAt: string;
  isPro?: boolean;
  rcUserId?: string;
}

export interface UpdateStatusBody {
  deviceDigest: string;
  deviceToken: string;
  isPro: boolean;
}

export interface RegisterBody {
  deviceToken: string;
  deviceDigest: string;
  userDigest: string;
  label?: string;
  rcUserId?: string;
}

export interface RcWebhookPayload {
  api_version: string;
  event: {
    type: string;
    app_user_id: string;
    entitlement_ids?: string[];
  };
}

export interface RotateBody {
  oldDigest: string;
  newDigest: string;
  deviceToken: string;
}

export interface RotateUserBody {
  oldUserDigest: string;
  newUserDigest: string;
  deviceDigest: string;
  deviceToken: string;
}

export interface UnregisterBody {
  deviceDigest: string;
  deviceToken: string;
}

export interface WebhookRecord {
  ownerDigest: string;
  label: string;
  scope: "device" | "user";
  createdAt: string;
}

export interface CreateWebhookBody {
  deviceDigest: string;
  deviceToken: string;
  webhookDigest: string;
  label: string;
  scope?: "device" | "user";
}

export interface DeleteWebhookBody {
  deviceDigest: string;
  deviceToken: string;
}
