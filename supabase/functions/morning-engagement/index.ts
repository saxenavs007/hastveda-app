// 8:00 AM IST daily curiosity push for all active users who have not opted out, retried at 8:15 IST.
// The Flutter web app on Render is static, so this webhook is the timer.
// pg_cron fires at 02:30 and 02:45 UTC. See
// 20261006113000_morning_engagement_cron.sql.
// Each accepted call is recorded in public.cron_executions. See
// 20261007120000_cron_executions.sql.
//
// Deploy:
//   supabase functions deploy morning-engagement
//   supabase secrets set CRON_SECRET=... FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
// FCM_SERVER_KEY is accepted as an alias for that same service-account JSON.
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

// A 14-day rotation keeps the daily push fresh; the sequence repeats only after
// two weeks. Keep each teaser curiosity-led, not a promise or a guaranteed prediction.
const DAILY_HOOKS = [
  { title: "👁️ Someone Secretly Admires You?", teaser: "Hidden admirer or just a secret crush? Explore what your heart line may suggest...", question: "Based on my palm scan and heart line, could someone secretly admire me?" },
  { title: "💗 A Heart-Line Signal Today", teaser: "One detail in your heart line may offer a fresh perspective on your love life...", question: "What might my heart line suggest about my current love life?" },
  { title: "✨ Is Love Moving Closer?", teaser: "Curious about a new connection? Your palm reading may offer a thoughtful clue...", question: "What does my palm reading suggest about a possible new relationship?" },
  { title: "💌 A Message You Didn't Expect?", teaser: "Wondering whether someone from your circle has feelings they haven't shared?", question: "What can my palm reading suggest about unspoken feelings around me?" },
  { title: "🌙 A Secret Crush or Friendship?", teaser: "Could a familiar connection feel different lately? Explore the signs with HastVeda...", question: "What does my heart line suggest about friendship turning into romance?" },
  { title: "❤️ What Is Your Heart Line Saying?", teaser: "Take a closer look at the relationship themes in your personal palm reading...", question: "What does my heart line suggest about the kind of relationship I seek?" },
  { title: "🔮 A New Connection on the Horizon?", teaser: "Your love-life questions deserve more than guesswork. Explore your palm reading...", question: "What relationship opportunities should I stay open to, according to my palm reading?" },
  { title: "💫 Are They Thinking About You?", teaser: "If someone is on your mind, discover what palmistry can—and cannot—tell you...", question: "What can palmistry reasonably suggest about my romantic connections?" },
  { title: "🌹 Your Next Chapter in Love", teaser: "Your heart line offers a personal lens for reflecting on what you want next...", question: "What does my palm reading suggest I should focus on in my love life?" },
  { title: "💞 A Relationship Turning Point?", teaser: "A fresh perspective on your heart line could help you reflect on your next step...", question: "What does my heart line suggest about changes in my relationships?" },
  { title: "🧿 Love, Timing & Your Palm", teaser: "Thinking about timing in love? Explore a grounded interpretation of your palm lines...", question: "What does my palm reading suggest about being ready for a relationship?" },
  { title: "💖 What Makes You Magnetic?", teaser: "Your palm reading may offer clues for reflecting on your strengths in relationships...", question: "What strengths in relationships are reflected in my palm reading?" },
  { title: "🌟 A Clue About Your Love Pattern", teaser: "Notice the patterns you bring to relationships and explore them with HastVeda...", question: "What relationship patterns might my palm reading invite me to reflect on?" },
  { title: "💘 Could a Crush Become More?", teaser: "Curious about where a connection could go? Start with your personal heart-line reading...", question: "What should I consider before taking a crush toward a relationship?" },
];

function dailyHook(day: Date): (typeof DAILY_HOOKS)[number] {
  return DAILY_HOOKS[Math.abs(dayOfYear(day)) % DAILY_HOOKS.length];
}

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
  // The cron request authenticates with the anon key. Do not reuse that
  // Authorization header for database calls. service_role bypasses RLS.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${serviceKey}`,
      },
    },
    accessToken: async () => serviceKey,
  });
  const day = istDate(new Date());
  const istKey = day.toISOString().slice(0, 10);
  const dayStart = new Date(day.getTime() - (5 * 60 + 30) * 60 * 1000).toISOString();
  console.log("[morning-engagement] started", { ist_date: istKey, dry_run: dryRun });
  const runId = await startCronLog(admin, istKey, dryRun);

  async function complete(
    status: "succeeded" | "failed" | "dry_run",
    httpStatus: number,
    body: Record<string, unknown>,
    detail?: string,
  ) {
    await finishCronLog(admin, runId, status, httpStatus, body, detail);
    return json(body, httpStatus);
  }

  try {
    const subscriberIds = await activeSubscriberIds(admin);
    const activeIds = await filterActiveProfiles(admin, subscriberIds);
    const allowed = await filterOptIn(admin, activeIds);
    const notices = await morningNotices(admin, dayStart);
    const missing = allowed.filter((id) => !notices.has(id));
    const hook = dailyHook(day);
    const title = hook.title;
    const serviceAccount = readServiceAccount();

    if (!dryRun) {
      const snippets = await loveSnippets(admin, missing);
      await writeInbox(admin, missing, notices, snippets, hook, istKey, dayStart);
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
      return await complete("dry_run", 200, {
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
      return await complete("failed", 503, {
        ok: false,
        error: "Push delivery failed",
        detail: "FIREBASE_SERVICE_ACCOUNT or FCM_SERVER_KEY is missing or invalid",
        ist_date: istKey,
        subscribers: allowed.length,
        inbox_written: missing.length,
        push_sent: 0,
        push_failed: 0,
        push_pending: pendingPush.length,
        fcm_configured: false,
      }, "FIREBASE_SERVICE_ACCOUNT or FCM_SERVER_KEY is missing or invalid");
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
      return await complete("failed", 502, {
        ...result,
        error: "Push delivery failed",
        detail: "One or more FCM sends failed and will be retried",
      }, "One or more FCM sends failed and will be retried");
    }
    return await complete("succeeded", 200, result);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Morning engagement failed";
    console.error("[morning-engagement] failed", detail);
    return await complete("failed", 500, {
      error: "Morning engagement failed",
      detail,
    }, detail);
  }
});

async function startCronLog(admin: Admin, istDate: string, dryRun: boolean) {
  try {
    const { data, error } = await admin
      .from("cron_executions")
      .insert({
        job_name: "morning-engagement",
        status: "running",
        ist_date: istDate,
        result: { dry_run: dryRun },
      })
      .select("id")
      .single();
    if (error) {
      console.error("[morning-engagement] could not open cron log", error.message);
      return null;
    }
    return (data?.id as string | undefined) ?? null;
  } catch (error) {
    console.error(
      "[morning-engagement] could not open cron log",
      error instanceof Error ? error.message : "insert failed",
    );
    return null;
  }
}

async function finishCronLog(
  admin: Admin,
  runId: string | null,
  status: "succeeded" | "failed" | "dry_run",
  httpStatus: number,
  result: Record<string, unknown>,
  detail?: string,
) {
  if (!runId) return;
  try {
    const { error } = await admin
      .from("cron_executions")
      .update({
        status,
        finished_at: new Date().toISOString(),
        http_status: httpStatus,
        detail: detail ? detail.slice(0, 500) : null,
        result,
      })
      .eq("id", runId);
    if (error) {
      console.error("[morning-engagement] could not finish cron log", error.message);
    }
  } catch (error) {
    console.error(
      "[morning-engagement] could not finish cron log",
      error instanceof Error ? error.message : "update failed",
    );
  }
}

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
  // Daily notifications are for all active registered accounts, not just Premium.
  // Notification opt-outs are still respected by filterOptIn() before delivery.
  // palm_profiles stores palm traits only and has no FCM token column.
  const accounts = await pages<{ id: string }>("user_profiles", (from, to) =>
    admin.from("user_profiles").select("id").eq("is_active", true).range(from, to)
  );
  return [...new Set(accounts.map((row) => row.id))];
}

async function filterActiveProfiles(admin: Admin, ids: string[]) {
  const active = new Set<string>();
  for (const group of chunks(ids, 100)) {
    const data = await query<{ id: string }>(
      "user_profiles",
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
  hook: (typeof DAILY_HOOKS)[number],
  istKey: string,
  dayStart: string,
) {
  const rows: InboxRow[] = userIds.map((userId) => {
    const snippet = snippets.get(userId) ?? "";
    const body = snippet ? `From your saved heart line: ${snippet}` : hook.teaser;
    return {
      user_id: userId,
      notification_type: "new_prediction",
      title: hook.title,
      body,
      data: {
        kind: "morning_curiosity",
        type: "morning_curiosity",
        route: "/notifications",
        ist_date: istKey,
        teaser: hook.teaser,
        question: hook.question,
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
  // fcm_token lives on public.users. public.profiles has no token column and
  // is what produced "permission denied for table profiles".
  for (const group of chunks(ids, 100)) {
    const data = await query<{ id: string; fcm_token: string | null }>(
      "users.fcm_token",
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
  try {
    for (const group of chunks(ids, 100)) {
      const rows = await pages<{
        user_id: string;
        love_analysis: unknown;
        created_at: string;
      }>("palm_analysis", (from, to) =>
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
  } catch (error) {
    console.error(
      "[morning-engagement] palm_analysis lookup failed; using the default teaser",
      error instanceof Error ? error.message : "query failed",
    );
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
  let accessToken: string;
  try {
    accessToken = await firebaseAccessToken(serviceAccount);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Firebase access token request failed";
    console.error("[morning-engagement] Firebase access token request failed", detail);
    throw new Error(detail);
  }
  for (const group of chunks(userIds, 20)) {
    const outcomes = await Promise.all(group.map(async (userId) => {
      const token = tokens.get(userId);
      const notice = notices.get(userId);
      if (!token || !notice) {
        if (!notice) {
          console.error("[morning-engagement] push skipped because the inbox row was not saved");
          return { pushSent: 0, pushFailed: 0, pushRetryable: 1, tokensCleared: 0 };
        }
        return { pushSent: 0, pushFailed: 0, pushRetryable: 0, tokensCleared: 0 };
      }
      let result: { ok: boolean; dropToken: boolean; status: string };
      try {
        result = await sendFcm(serviceAccount.project_id, accessToken, token, {
          title: notice.title,
          body: notice.body,
          collapseKey: `morning_${istKey}`,
          data: {
            type: "morning_curiosity",
            route: "/notifications",
            ist_date: istKey,
          },
        });
      } catch (error) {
        const detail = error instanceof Error ? error.message : "FCM send failed";
        console.error("[morning-engagement] FCM send failed", detail);
        await markPush(admin, notice, { push_sent: false, push_error: detail.slice(0, 180) });
        return { pushSent: 0, pushFailed: 1, pushRetryable: 1, tokensCleared: 0 };
      }
      if (result.ok) {
        notice.pushSent = true;
        await markPush(admin, notice, { push_sent: true, push_error: null });
        return { pushSent: 1, pushFailed: 0, pushRetryable: 0, tokensCleared: 0 };
      }
      if (result.dropToken) {
        const { error } = await admin.from("users").update({ fcm_token: null }).eq("id", userId);
        if (error) {
          console.error("[morning-engagement] could not clear a rejected FCM token", error.message);
          return { pushSent: 0, pushFailed: 1, pushRetryable: 1, tokensCleared: 0 };
        }
        await markPush(admin, notice, { push_sent: false, push_error: result.status });
        return { pushSent: 0, pushFailed: 1, pushRetryable: 0, tokensCleared: 1 };
      }
      await markPush(admin, notice, { push_sent: false, push_error: result.status });
      return { pushSent: 0, pushFailed: 1, pushRetryable: 1, tokensCleared: 0 };
    }));
    for (const outcome of outcomes) {
      pushSent += outcome.pushSent;
      pushFailed += outcome.pushFailed;
      pushRetryable += outcome.pushRetryable;
      tokensCleared += outcome.tokensCleared;
    }
  }
  return { pushSent, pushFailed, pushRetryable, tokensCleared };
}

async function markPush(
  admin: Admin,
  notice: MorningNotice,
  patch: { push_sent: boolean; push_error: string | null },
) {
  try {
    const data = { ...notice.data, ...patch };
    const { error } = await admin.from("notifications").update({ data }).eq("id", notice.id);
    if (error) {
      console.error("[morning-engagement] could not record push status", error.message);
      return false;
    }
    notice.data = data;
    return true;
  } catch (error) {
    console.error(
      "[morning-engagement] could not record push status",
      error instanceof Error ? error.message : "update failed",
    );
    return false;
  }
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
  const raw = (
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ??
    Deno.env.get("FCM_SERVER_KEY") ??
    ""
  ).trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      console.error("[morning-engagement] Firebase service account is missing required fields");
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
  let response: Response;
  try {
    response = await fetch(
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
            notification: {
              title: message.title,
              body: message.body,
            },
            data: fcmData(message.data, message.title, message.body),
            android: {
              priority: "HIGH",
              collapse_key: message.collapseKey,
              notification: {
                title: message.title,
                body: message.body,
                channel_id: "hastveda_daily_horoscope",
                tag: message.collapseKey,
                sound: "default",
                visibility: "PUBLIC",
                notification_priority: "PRIORITY_HIGH",
                default_sound: true,
                default_vibrate_timings: true,
              },
            },
            apns: {
              headers: {
                "apns-priority": "10",
                "apns-push-type": "alert",
              },
              payload: {
                aps: {
                  alert: {
                    title: message.title,
                    body: message.body,
                  },
                  sound: "default",
                },
              },
            },
          },
        }),
      },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "FCM request failed";
    console.error("[morning-engagement] FCM request failed", detail);
    return { ok: false, dropToken: false, status: "NETWORK" };
  }
  if (response.ok) return { ok: true, dropToken: false, status: "OK" };
  const body = await response.json().catch(() => ({}));
  const status = (body?.error?.status as string | undefined) ?? String(response.status);
  const codes = JSON.stringify(body?.error?.details ?? []);
  const detail = String(body?.error?.message ?? "");
  const dropToken = status === "NOT_FOUND" ||
    codes.includes("UNREGISTERED") ||
    detail.includes("NotRegistered") ||
    detail.includes("registration token is not a valid");
  console.error("[morning-engagement] FCM rejected a token", status);
  return { ok: false, dropToken, status };
}

function fcmData(
  data: Record<string, string>,
  title: string,
  body: string,
) {
  const payload: Record<string, string> = { title, body };
  for (const [key, value] of Object.entries(data)) {
    payload[key] = String(value);
  }
  return payload;
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
