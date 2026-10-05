// 8:00 AM IST curiosity push for active subscribers.
//
// Deploy:
//   supabase functions deploy morning-engagement
//   supabase secrets set CRON_SECRET=... FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
//
// Ping (02:30 UTC = 08:00 Asia/Kolkata). Render sleeping does not matter;
// this runs on Supabase, not on the static site.
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
  if (!cronSecret) {
    return json({ error: "CRON_SECRET is not configured" }, 503);
  }
  // Gateway JWT is disabled (--no-verify-jwt). The cron secret is the
  // only credential. Accept it as x-cron-secret or as Authorization: Bearer.
  const headerSecret = req.headers.get("x-cron-secret") ?? "";
  const authorization = req.headers.get("Authorization") ?? "";
  const bearer = authorization.replace(/^Bearer\s+/i, "").trim();
  const provided = headerSecret || bearer;
  if (!safeEqual(provided, cronSecret)) {
    return json({ error: "Unauthorized", code: "CRON_SECRET" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Supabase service credentials are missing" }, 503);
  }

  const url = new URL(req.url);
  const dryRun = url.searchParams.get("dry_run") === "1";
  const admin = createClient(supabaseUrl, serviceKey);
  const day = istDate(new Date());
  const istKey = day.toISOString().slice(0, 10);
  const dayStart = new Date(day.getTime() - (5 * 60 + 30) * 60 * 1000).toISOString();

  try {
    const subscriberIds = await activeSubscriberIds(admin);
    const activeIds = await filterActiveProfiles(admin, subscriberIds);
    const allowed = await filterOptIn(admin, activeIds);
    const already = await alreadySent(admin, dayStart);
    const pending = allowed.filter((id) => !already.has(id));
    const tokens = await tokensFor(admin, pending);
    const snippets = await loveSnippets(admin, pending);
    const title = TITLES[Math.abs(dayOfYear(day)) % TITLES.length];
    const serviceAccount = readServiceAccount();

    if (dryRun) {
      return json({
        ok: true,
        dry_run: true,
        ist_date: istKey,
        subscribers: allowed.length,
        already_sent: already.size,
        pending: pending.length,
        with_token: [...tokens.values()].filter(Boolean).length,
        fcm_configured: serviceAccount != null,
        title,
      });
    }

    let inboxWritten = 0;
    const rows = pending.map((userId) => {
      const snippet = snippets.get(userId) ?? "";
      const body = snippet
        ? `From your saved heart line: ${snippet}`
        : TEASER;
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
        },
      };
    });
    for (const chunk of chunks(rows, 100)) {
      const { error } = await admin.from("notifications").insert(chunk);
      if (error) throw error;
      inboxWritten += chunk.length;
    }

    let pushSent = 0;
    let pushFailed = 0;
    let pushSkipped = 0;
    let tokensCleared = 0;
    if (serviceAccount) {
      const accessToken = await firebaseAccessToken(serviceAccount);
      for (const userId of pending) {
        const token = tokens.get(userId);
        if (!token) {
          pushSkipped++;
          continue;
        }
        const row = rows.find((item) => item.user_id === userId)!;
        const result = await sendFcm(serviceAccount.project_id, accessToken, token, {
          title: row.title,
          body: row.body,
          data: {
            type: "morning_curiosity",
            route: "/notifications",
            ist_date: istKey,
          },
        });
        if (result.ok) {
          pushSent++;
        } else {
          pushFailed++;
          if (result.dropToken) {
            await admin.from("users").update({ fcm_token: null }).eq("id", userId);
            tokensCleared++;
          }
        }
      }
    } else {
      pushSkipped = pending.length;
    }

    return json({
      ok: true,
      ist_date: istKey,
      subscribers: allowed.length,
      already_sent: allowed.length - pending.length,
      inbox_written: inboxWritten,
      push_sent: pushSent,
      push_failed: pushFailed,
      push_skipped_no_token: pushSkipped,
      tokens_cleared: tokensCleared,
      fcm_configured: serviceAccount != null,
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Morning engagement failed";
    console.error("[morning-engagement]", detail);
    return json({ error: "Morning engagement failed", detail }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

async function activeSubscriberIds(admin: ReturnType<typeof createClient>) {
  const ids = new Set<string>();
  const profiles = await pages<{ id: string }>((from, to) =>
    admin.from("user_profiles").select("id").eq("tier", "premium").eq("is_active", true).range(from, to)
  );
  for (const row of profiles) ids.add(row.id);

  const subs = await pages<{ user_id: string; expires_at: string | null }>((from, to) =>
    admin
      .from("subscriptions")
      .select("user_id, expires_at")
      .in("status", ["active", "grace_period"])
      .range(from, to)
  );
  for (const row of subs) {
    if (stillActive(row.expires_at)) ids.add(row.user_id);
  }

  const ents = await pages<{ user_id: string; expires_at: string | null }>((from, to) =>
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

async function filterActiveProfiles(
  admin: ReturnType<typeof createClient>,
  ids: string[],
) {
  const active = new Set<string>();
  for (const group of chunks(ids, 100)) {
    const { data, error } = await admin
      .from("user_profiles")
      .select("id")
      .in("id", group)
      .eq("is_active", true);
    if (error) throw error;
    for (const row of data ?? []) active.add(row.id as string);
  }
  return [...active];
}

async function filterOptIn(admin: ReturnType<typeof createClient>, ids: string[]) {
  const blocked = new Set<string>();
  for (const group of chunks(ids, 100)) {
    const { data, error } = await admin
      .from("notification_preferences")
      .select("user_id, push_enabled, new_predictions")
      .in("user_id", group);
    if (error) throw error;
    for (const row of data ?? []) {
      if (row.push_enabled === false || row.new_predictions === false) {
        blocked.add(row.user_id as string);
      }
    }
  }
  return ids.filter((id) => !blocked.has(id));
}

async function alreadySent(admin: ReturnType<typeof createClient>, dayStart: string) {
  const sent = new Set<string>();
  const rows = await pages<{ user_id: string; data: { kind?: string } | null }>((from, to) =>
    admin
      .from("notifications")
      .select("user_id, data")
      .eq("notification_type", "new_prediction")
      .gte("sent_at", dayStart)
      .range(from, to)
  );
  for (const row of rows) {
    if (row.data?.kind === "morning_curiosity") sent.add(row.user_id);
  }
  return sent;
}

async function tokensFor(admin: ReturnType<typeof createClient>, ids: string[]) {
  const tokens = new Map<string, string>();
  for (const group of chunks(ids, 100)) {
    const { data, error } = await admin
      .from("users")
      .select("id, fcm_token")
      .in("id", group)
      .not("fcm_token", "is", null);
    if (error) throw error;
    for (const row of data ?? []) {
      const token = (row.fcm_token as string | null)?.trim();
      if (token) tokens.set(row.id as string, token);
    }
  }
  return tokens;
}

async function loveSnippets(admin: ReturnType<typeof createClient>, ids: string[]) {
  const snippets = new Map<string, string>();
  for (const group of chunks(ids, 100)) {
    const { data, error } = await admin
      .from("palm_analysis")
      .select("user_id, love_analysis, created_at")
      .in("user_id", group)
      .order("created_at", { ascending: false });
    if (error) throw error;
    for (const row of data ?? []) {
      const userId = row.user_id as string;
      if (snippets.has(userId)) continue;
      const snippet = snippetOf(row.love_analysis);
      if (snippet) snippets.set(userId, snippet);
    }
  }
  return snippets;
}

function snippetOf(analysis: unknown) {
  if (!analysis || typeof analysis !== "object") return "";
  const map = analysis as Record<string, unknown>;
  const raw = String(map.interpretation_en ?? map.summary_en ?? "").trim();
  if (!raw) return "";
  const sentence = raw.split(/(?<=[.!?])\s+/)[0]?.trim() ?? raw;
  return sentence.length <= 160 ? sentence : `${sentence.slice(0, 157)}...`;
}

async function pages<T>(
  load: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
) {
  const size = 500;
  const rows: T[] = [];
  for (let from = 0; ; from += size) {
    const { data, error } = await load(from, from + size - 1);
    if (error) throw new Error(error.message);
    const page = data ?? [];
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
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) return null;
    return parsed;
  } catch {
    console.error("[morning-engagement] FIREBASE_SERVICE_ACCOUNT is not valid JSON");
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
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
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
  const body = await response.json();
  if (!response.ok || !body.access_token) {
    throw new Error("Firebase access token request failed");
  }
  return body.access_token as string;
}

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  message: { title: string; body: string; data: Record<string, string> },
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
          android: { priority: "HIGH" },
        },
      }),
    },
  );
  if (response.ok) return { ok: true, dropToken: false };
  const body = await response.json().catch(() => ({}));
  const status = body?.error?.status as string | undefined;
  const codes = JSON.stringify(body?.error?.details ?? []);
  const dropToken = status === "NOT_FOUND" || codes.includes("UNREGISTERED");
  console.error("[morning-engagement] FCM rejected a token", status ?? response.status);
  return { ok: false, dropToken };
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
