// 8:00 AM IST curiosity push for active subscribers, retried at 8:15 IST.
// pg_cron fires at 02:30 and 02:45 UTC. See
// 20261006113000_morning_engagement_cron.sql.
//
// Deploy:
//   supabase functions deploy morning-engagement
//   supabase secrets set CRON_SECRET=... FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
// Store the same CRON_SECRET in vault as cron_secret, and the anon or
// publishable key as anon_key, so the scheduled call can authenticate.
//
// Manual ping:
//   curl -X POST \
//     -H "apikey: $SUPABASE_ANON_KEY" \
//     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
//     -H "x-cron-secret: $CRON_SECRET" \
//     https://<project>.supabase.co/functions/v1/morning-engagement

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const TITLES = [
  "Someone Falling For You...",
  "A Heart-Line Signal Today",
  "Love Is Moving Closer",
];

const TEASER =
  "A quiet change in your heart line suggests someone is moving closer than you think...";

const QUESTION =
  "Based on my heart line from my palm scan, is someone falling for me?";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type MorningNotice = {
  id: string;
  userId: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  pushSent: boolean;
};

type Admin = ReturnType<typeof createClient>;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const cronSecret = cleanSecret(Deno.env.get("CRON_SECRET") ?? "");
  if (!cronSecret) {
    console.error("[morning-engagement] CRON_SECRET is not configured");
    return json({ error: "CRON_SECRET is not configured" }, 503);
  }

  const presented = await presentedSecrets(req);
  if (!presented.some((value) => safeEqual(value, cronSecret))) {
    console.error("[morning-engagement] rejected cron request", {
      cron_header: headerPresent(req, "x-cron-secret") ? "present" : "missing",
      authorization: headerPresent(req, "authorization") ? "present" : "missing",
    });
    return json({ error: "Unauthorized", code: "CRON_SECRET" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    console.error("[morning-engagement] Supabase service credentials are missing");
    return json({ error: "Supabase service credentials are missing" }, 503);
  }

  const url = new URL(req.url);
  const dryRun = url.searchParams.get("dry_run") === "1";
  const admin = createClient(supabaseUrl, serviceKey);
  const day = istDate(new Date());
  const istKey = day.toISOString().slice(0, 10);
  const dayStart = new Date(day.getTime() - (5 * 60 + 30) * 60 * 1000).toISOString();
  console.log("[morning-engagement] started", { ist_date: istKey, dry_run: dryRun });

  try {
    const subscriberIds = await activeSubscriberIds(admin);
    const activeIds = await filterActiveProfiles(admin, subscriberIds);
    const allowed = await filterOptIn(admin, activeIds);
    const notices = await morningNotices(admin, dayStart);
    const missing = allowed.filter((id) => !notices.has(id));
    const title = TITLES[Math.abs(dayOfYear(day)) % TITLES.length];
    const serviceAccount = readServiceAccount();

    if (!dryRun) {
      const snippets = await loveSnippets(admin, missing);
      await writeInbox(admin, missing, notices, snippets, title, istKey, dayStart);
    }

    const tokens = await tokensFor(
      admin,
      allowed.filter((id) => !notices.get(id)?.pushSent),
    );
    const pendingPush = [...tokens.keys()];
    console.log("[morning-engagement] audience", {
      ist_date: istKey,
      subscribers: allowed.length,
      already_inbox: allowed.length - missing.length,
      inbox_missing: missing.length,
      pending_push: pendingPush.length,
      fcm_configured: serviceAccount != null,
    });

    if (dryRun) {
      return json({
        ok: true,
        dry_run: true,
        ist_date: istKey,
        subscribers: allowed.length,
        already_sent: allowed.length - missing.length,
        pending: missing.length,
        pending_push: pendingPush.length,
        with_token: pendingPush.length,
        fcm_configured: serviceAccount != null,
        title,
      });
    }

    if (pendingPush.length > 0 && !serviceAccount) {
      console.error(
        "[morning-engagement] FIREBASE_SERVICE_ACCOUNT is missing or invalid; push not sent",
        { pending_push: pendingPush.length },
      );
      return json({
        ok: false,
        error: "Push delivery failed",
        detail: "FIREBASE_SERVICE_ACCOUNT is missing or invalid",
        ist_date: istKey,
        subscribers: allowed.length,
        inbox_written: missing.length,
        push_sent: 0,
        push_failed: 0,
        push_pending: pendingPush.length,
        fcm_configured: false,
      }, 503);
    }

    const delivery = serviceAccount
      ? await deliverPushes(admin, serviceAccount, pendingPush, tokens, notices, istKey)
      : { pushSent: 0, pushFailed: 0, pushRetryable: 0, tokensCleared: 0 };

    const result = {
      ok: delivery.pushRetryable === 0,
      ist_date: istKey,
      subscribers: allowed.length,
      already_sent: allowed.length - missing.length,
      inbox_written: missing.length,
      push_sent: delivery.pushSent,
      push_failed: delivery.pushFailed,
      push_pending: delivery.pushRetryable,
      push_skipped_no_token: allowed.filter((id) => !notices.get(id)?.pushSent && !tokens.has(id)).length,
      tokens_cleared: delivery.tokensCleared,
      fcm_configured: serviceAccount != null,
    };
    console.log("[morning-engagement] finished", result);
    if (delivery.pushRetryable > 0) {
      console.error("[morning-engagement] retryable FCM failures remain", {
        push_pending: delivery.pushRetryable,
      });
      return json({
        ...result,
        error: "Push delivery failed",
        detail: "One or more FCM sends failed and will be retried",
      }, 502);
    }
    return json(result);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Morning engagement failed";
    console.error("[morning-engagement] failed", detail);
    return json({ error: "Morning engagement failed", detail }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function cleanSecret(value: string) {
  let secret = value.trim();
  if (secret.length >= 2 && secret.startsWith('"') && secret.endsWith('"')) {
    secret = secret.slice(1, -1).trim();
  }
  return secret;
}

function headerPresent(req: Request, name: string) {
  return (req.headers.get(name) ?? "").trim().length > 0;
}

async function presentedSecrets(req: Request) {
  const secrets: string[] = [];
  const headerSecret = cleanSecret(req.headers.get("x-cron-secret") ?? "");
  if (headerSecret) secrets.push(headerSecret);
  const bearer = cleanSecret(
    (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, ""),
  );
  if (bearer) secrets.push(bearer);
  if (req.method !== "POST") return secrets;
  const text = await req.text().catch(() => "");
  if (!text.trim()) return secrets;
  try {
    const body = JSON.parse(text) as { cron_secret?: unknown };
    if (typeof body.cron_secret === "string") {
      const fromBody = cleanSecret(body.cron_secret);
      if (fromBody) secrets.push(fromBody);
    }
  } catch (error) {
    console.error(
      "[morning-engagement] cron body was not JSON",
      error instanceof Error ? error.message : "invalid JSON",
    );
  }
  return secrets;
}

function safeEqual(left: string, right: string) {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  const length = Math.max(a.length, b.length);
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < length; i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

function istDate(now: Date) {
  const shifted = new Date(now.getTime() + (5 * 60 + 30) * 60 * 1000);
  return new Date(Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  ));
}

function dayOfYear(day: Date) {
  const start = Date.UTC(day.getUTCFullYear(), 0, 1);
  return Math.floor((day.getTime() - start) / 86_400_000);
}

function stillActive(expires: string | null) {
  if (!expires) return true;
  return new Date(expires).getTime() > Date.now();
}

function chunks<T>(items: T[], size: number) {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "string") {
    try {
      return asRecord(JSON.parse(value));
    } catch {
      return {};
    }
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

async function activeSubscriberIds(admin: Admin) {
  const ids = new Set<string>();
  const profiles = await pages<{ id: string }>("user_profiles", (from, to) =>
    admin.from("user_profiles").select("id").eq("tier", "premium").eq("is_active", true).range(from, to)
  );
  for (const row of profiles) ids.add(row.id);

  const subs = await pages<{ user_id: string; expires_at: string | null }>("subscriptions", (from, to) =>
    admin
      .from("subscriptions")
      .select("user_id, expires_at")
      .in("status", ["active", "grace_period"])
      .range(from, to)
  );
  for (const row of subs) {
    if (stillActive(row.expires_at)) ids.add(row.user_id);
  }

  const ents = await pages<{ user_id: string; expires_at: string | null }>("entitlements", (from, to) =>
    admin
      .from("entitlements")
      .select("user_id, expires_at")
      .eq("entitlement_type", "PREMIUM")
      .eq("is_active", true)
      .range(from, to)
  );
  for (const row of ents) {
    if (stillActive(row.expires_at)) ids.add(row.user_id);
  }
  return [...ids];
}

async function filterActiveProfiles(admin: Admin, ids: string[]) {
  const active = new Set<string>();
  for (const group of chunks(ids, 100)) {
    const data = await query<{ id: string }>(
      "active profiles",
      admin.from("user_profiles").select("id").in("id", group).eq("is_active", true),
    );
    for (const row of data) active.add(row.id);
  }
  return [...active];
}

async function filterOptIn(admin: Admin, ids: string[]) {
  const blocked = new Set<string>();
  for (const group of chunks(ids, 100)) {
    const data = await query<{
      user_id: string;
      push_enabled: boolean | null;
      new_predictions: boolean | null;
    }>(
      "notification preferences",
      admin
        .from("notification_preferences")
        .select("user_id, push_enabled, new_predictions")
        .in("user_id", group),
    );
    for (const row of data) {
      if (row.push_enabled === false || row.new_predictions === false) {
        blocked.add(row.user_id);
      }
    }
  }
  return ids.filter((id) => !blocked.has(id));
}

async function morningNotices(admin: Admin, dayStart: string) {
  const notices = new Map<string, MorningNotice>();
  const rows = await pages<{
    id: string;
    user_id: string;
    title: string;
    body: string;
    data: unknown;
  }>("morning notifications", (from, to) =>
    admin
      .from("notifications")
      .select("id, user_id, title, body, data")
      .eq("notification_type", "new_prediction")
      .gte("sent_at", dayStart)
      .contains("data", { kind: "morning_curiosity" })
      .order("sent_at", { ascending: true })
      .range(from, to)
  );
  for (const row of rows) {
    const data = asRecord(row.data);
    if (data.kind !== "morning_curiosity") continue;
    if (notices.has(row.user_id)) continue;
    notices.set(row.user_id, {
      id: row.id,
      userId: row.user_id,
      title: row.title,
      body: row.body,
      data,
      pushSent: data.push_sent === true,
    });
  }
  return notices;
}

type InboxRow = {
  user_id: string;
  notification_type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
};

async function writeInbox(
  admin: Admin,
  userIds: string[],
  notices: Map<string, MorningNotice>,
  snippets: Map<string, string>,
  title: string,
  istKey: string,
  dayStart: string,
) {
  const rows: InboxRow[] = userIds.map((userId) => {
    const snippet = snippets.get(userId) ?? "";
    const body = snippet ? `From your saved heart line: ${snippet}` : TEASER;
    return {
      user_id: userId,
      notification_type: "new_prediction",
      title,
      body,
      data: {
        kind: "morning_curiosity",
        type: "morning_curiosity",
        route: "/notifications",
        ist_date: istKey,
        teaser: TEASER,
        question: QUESTION,
        push_sent: false,
      },
    };
  });
  for (const chunk of chunks(rows, 100)) {
    const { data, error } = await admin
      .from("notifications")
      .insert(chunk)
      .select("id, user_id");
    if (error?.code === "23505") {
      console.error("[morning-engagement] morning inbox already exists; keeping the saved row");
      const fresh = await morningNotices(admin, dayStart);
      for (const [userId, notice] of fresh) notices.set(userId, notice);
      for (const row of chunk) {
        if (!notices.has(row.user_id)) await insertMorningRow(admin, notices, row);
      }
      continue;
    }
    if (error) {
      console.error("[morning-engagement] query failed", "insert notifications", error.message);
      throw new Error(`insert notifications: ${error.message}`);
    }
    rememberNotices(notices, data ?? [], chunk);
  }
}

function rememberNotices(
  notices: Map<string, MorningNotice>,
  inserted: { id: string; user_id: string }[],
  source: InboxRow[],
) {
  for (const row of inserted) {
    const item = source.find((entry) => entry.user_id === row.user_id);
    if (!item || notices.has(row.user_id)) continue;
    notices.set(row.user_id, {
      id: row.id,
      userId: row.user_id,
      title: item.title,
      body: item.body,
      data: item.data,
      pushSent: false,
    });
  }
}

async function insertMorningRow(
  admin: Admin,
  notices: Map<string, MorningNotice>,
  row: InboxRow,
) {
  const { data, error } = await admin
    .from("notifications")
    .insert(row)
    .select("id, user_id")
    .maybeSingle();
  if (error?.code === "23505") return;
  if (error) {
    console.error("[morning-engagement] query failed", "insert notifications", error.message);
    throw new Error(`insert notifications: ${error.message}`);
  }
  if (data) rememberNotices(notices, [data], [row]);
}

async function tokensFor(admin: Admin, ids: string[]) {
  const tokens = new Map<string, string>();
  for (const group of chunks(ids, 100)) {
    const data = await query<{ id: string; fcm_token: string | null }>(
      "fcm tokens",
      admin.from("users").select("id, fcm_token").in("id", group).not("fcm_token", "is", null),
    );
    for (const row of data) {
      const token = row.fcm_token?.trim();
      if (token) tokens.set(row.id, token);
    }
  }
  return tokens;
}

async function loveSnippets(admin: Admin, ids: string[]) {
  const snippets = new Map<string, string>();
  for (const group of chunks(ids, 100)) {
    const rows = await pages<{
      user_id: string;
      love_analysis: unknown;
      created_at: string;
    }>("palm love snippets", (from, to) =>
      admin
        .from("palm_analysis")
        .select("user_id, love_analysis, created_at")
        .in("user_id", group)
        .order("created_at", { ascending: false })
        .range(from, to)
    );
    for (const row of rows) {
      if (snippets.has(row.user_id)) continue;
      const snippet = snippetOf(row.love_analysis);
      if (snippet) snippets.set(row.user_id, snippet);
    }
  }
  return snippets;
}

function snippetOf(analysis: unknown) {
  const map = asRecord(analysis);
  const raw = String(map.interpretation_en ?? map.summary_en ?? "").trim();
  if (!raw) return "";
  const sentence = raw.split(/(?<=[.!?])\s+/)[0]?.trim() ?? raw;
  return sentence.length <= 160 ? sentence : `${sentence.slice(0, 157)}...`;
}

async function deliverPushes(
  admin: Admin,
  serviceAccount: ServiceAccount,
  userIds: string[],
  tokens: Map<string, string>,
  notices: Map<string, MorningNotice>,
  istKey: string,
) {
  let pushSent = 0;
  let pushFailed = 0;
  let pushRetryable = 0;
  let tokensCleared = 0;
  const accessToken = await firebaseAccessToken(serviceAccount);
  for (const userId of userIds) {
    const token = tokens.get(userId);
    const notice = notices.get(userId);
    if (!token || !notice) {
      if (!notice) {
        pushRetryable++;
        console.error("[morning-engagement] push skipped because the inbox row was not saved");
      }
      continue;
    }
    const result = await sendFcm(serviceAccount.project_id, accessToken, token, {
      title: notice.title,
      body: notice.body,
      collapseKey: `morning_${istKey}`,
      data: {
        type: "morning_curiosity",
        route: "/notifications",
        ist_date: istKey,
      },
    });
    if (result.ok) {
      pushSent++;
      notice.pushSent = true;
      await markPush(admin, notice, { push_sent: true, push_error: null });
      continue;
    }
    pushFailed++;
    if (result.dropToken) {
      const { error } = await admin.from("users").update({ fcm_token: null }).eq("id", userId);
      if (error) {
        console.error("[morning-engagement] could not clear a rejected FCM token", error.message);
        pushRetryable++;
      } else {
        tokensCleared++;
        await markPush(admin, notice, { push_sent: false, push_error: result.status });
      }
      continue;
    }
    pushRetryable++;
    await markPush(admin, notice, { push_sent: false, push_error: result.status });
  }
  return { pushSent, pushFailed, pushRetryable, tokensCleared };
}

async function markPush(
  admin: Admin,
  notice: MorningNotice,
  patch: { push_sent: boolean; push_error: string | null },
) {
  const data = { ...notice.data, ...patch };
  const { error } = await admin.from("notifications").update({ data }).eq("id", notice.id);
  if (error) {
    console.error("[morning-engagement] could not record push status", error.message);
    return false;
  }
  notice.data = data;
  return true;
}

async function query<T>(
  label: string,
  request: PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
) {
  const { data, error } = await request;
  if (error) {
    console.error("[morning-engagement] query failed", label, error.message);
    throw new Error(`${label}: ${error.message}`);
  }
  return data ?? [];
}

async function pages<T>(
  label: string,
  load: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
) {
  const size = 500;
  const rows: T[] = [];
  for (let from = 0; ; from += size) {
    const page = await query(label, load(from, from + size - 1));
    rows.push(...page);
    if (page.length < size) break;
  }
  return rows;
}

function readServiceAccount(): ServiceAccount | null {
  const raw = (Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "").trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      console.error("[morning-engagement] FIREBASE_SERVICE_ACCOUNT is missing required fields");
      return null;
    }
    parsed.private_key = parsed.private_key.replace(/\\n/g, "\n");
    return parsed;
  } catch (error) {
    console.error(
      "[morning-engagement] FIREBASE_SERVICE_ACCOUNT is not valid JSON",
      error instanceof Error ? error.message : "invalid JSON",
    );
    return null;
  }
}

async function firebaseAccessToken(account: ServiceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      "pkcs8",
      pemToDer(account.private_key),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
  } catch (error) {
    console.error(
      "[morning-engagement] Firebase private key could not be parsed",
      error instanceof Error ? error.message : "invalid key",
    );
    throw new Error("Firebase private key could not be parsed");
  }
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const jwt = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token) {
    console.error(
      "[morning-engagement] Firebase access token request failed",
      body?.error ?? response.status,
    );
    throw new Error("Firebase access token request failed");
  }
  return body.access_token as string;
}

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  message: {
    title: string;
    body: string;
    collapseKey: string;
    data: Record<string, string>;
  },
) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: message.title, body: message.body },
          data: message.data,
          android: {
            priority: "HIGH",
            collapse_key: message.collapseKey,
            notification: {
              channel_id: "hastveda_daily_horoscope",
              tag: message.collapseKey,
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );
  if (response.ok) return { ok: true, dropToken: false, status: "OK" };
  const body = await response.json().catch(() => ({}));
  const status = (body?.error?.status as string | undefined) ?? String(response.status);
  const codes = JSON.stringify(body?.error?.details ?? []);
  const message = String(body?.error?.message ?? "");
  const dropToken = status === "NOT_FOUND" ||
    codes.includes("UNREGISTERED") ||
    message.includes("NotRegistered") ||
    message.includes("registration token is not a valid");
  console.error("[morning-engagement] FCM rejected a token", status);
  return { ok: false, dropToken, status };
}

function pemToDer(pem: string) {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

function base64Url(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}
