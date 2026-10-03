// Generates daily, weekly, monthly, and yearly horoscopes from the user's
// stored palm scan and caches one set per period in public.predictions.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PERIODS = ["daily", "weekly", "monthly", "yearly"] as const;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return json({ error: "Sign in required" }, 401);
    }
    const userId = authData.user.id;
    const admin = createClient(supabaseUrl, serviceKey);

    const { data: analysis } = await admin
      .from("palm_analysis")
      .select(
        "id, summary, life_analysis, love_analysis, career_analysis, health_analysis, wealth_analysis, personality_analysis",
      )
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!analysis) {
      return json({ personalized: false, needs_scan: true, insights: emptyInsights() });
    }

    const { data: features } = await admin
      .from("palm_features")
      .select("life_line, heart_line, head_line, fate_line, mercury_line, mounts")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const bounds = periodBounds();
    const insights: Record<string, Insight[]> = emptyInsights();
    const missing: string[] = [];

    for (const period of PERIODS) {
      const { data: cached } = await admin
        .from("predictions")
        .select("title, content, category, confidence_score, metadata")
        .eq("user_id", userId)
        .eq("time_period", period)
        .eq("period_start", bounds[period].start)
        .order("created_at", { ascending: true });

      if (cached && cached.length > 0) {
        insights[period] = cached.map(rowToInsight);
      } else {
        missing.push(period);
      }
    }

    if (missing.length > 0) {
      const dossier = buildDossier(analysis, features);
      const generated = await generateAll(missing, dossier);
      for (const period of missing) {
        const items = generated[period] ?? fallback(period, dossier);
        insights[period] = items;
        if (items.length === 0) continue;
        const rows = items.map((item) => ({
          user_id: userId,
          analysis_id: analysis.id,
          prediction_type: "horoscope",
          time_period: period,
          period_start: bounds[period].start,
          period_end: bounds[period].end,
          title: item.category,
          content: item.content,
          short_summary: item.content.slice(0, 140),
          category: item.category,
          confidence_score: item.confidence,
          is_premium: period !== "daily",
          metadata: {
            content_hi: item.content_hi,
            category_hi: item.category_hi,
            icon: item.icon,
            source: item.source,
          },
        }));
        const { error: insertError } = await admin.from("predictions").insert(rows);
        if (insertError) {
          console.error(`[horoscope-insights] cache insert failed for ${period}`, insertError);
        }
      }
    }

    return json({ personalized: true, insights });
  } catch (error) {
    console.error("[horoscope-insights]", error);
    return json({ error: "Could not build horoscope" }, 500);
  }
});

type Insight = {
  category: string;
  category_hi: string;
  content: string;
  content_hi: string;
  icon: string;
  confidence: number;
  is_major: boolean;
  source: string;
};

function emptyInsights(): Record<string, Insight[]> {
  return { daily: [], weekly: [], monthly: [], yearly: [] };
}

function rowToInsight(row: Record<string, unknown>): Insight {
  const meta = (row.metadata ?? {}) as Record<string, unknown>;
  return {
    category: String(row.category ?? row.title ?? "Insight"),
    category_hi: String(meta.category_hi ?? row.category ?? "Insight"),
    content: String(row.content ?? ""),
    content_hi: String(meta.content_hi ?? row.content ?? ""),
    icon: String(meta.icon ?? "auto_awesome"),
    confidence: Number(row.confidence_score ?? 75),
    is_major: Number(row.confidence_score ?? 0) >= 85,
    source: String(meta.source ?? "cache"),
  };
}

async function generateAll(
  periods: string[],
  dossier: ReturnType<typeof buildDossier>,
): Promise<Record<string, Insight[]>> {
  const result: Record<string, Insight[]> = {};
  try {
    const ai = await callGemini(periods, dossier);
    const grouped = ai && typeof ai === "object"
      ? (ai as Record<string, unknown>)
      : {};
    for (const period of periods) {
      const parsed = normalize(grouped[period], period);
      result[period] = parsed.length > 0 ? parsed : fallback(period, dossier);
    }
    return result;
  } catch (error) {
    console.error("[horoscope-insights] gemini failed", error);
    for (const period of periods) result[period] = fallback(period, dossier);
    return result;
  }
}

async function callGemini(
  periods: string[],
  dossier: ReturnType<typeof buildDossier>,
): Promise<unknown> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");
  const model = Deno.env.get("GEMINI_MODEL") || "gemini-2.0-flash";
  const prompt = `You write HastVeda horoscopes for these periods: ${periods.join(", ")}.
Use ONLY the stored palm-scan facts below. Every sentence must name a stored line or a phrase from the saved interpretation.
Do not invent line length, breaks, mounts, death, disease, or guaranteed money.
For each period write 3 insights. Daily is about today, weekly about this week, monthly about this month, yearly about this year.
English and Hindi should be similar in length.
Return JSON with a key per period:
{"daily":[{"category":"Love","category_hi":"प्रेम","content":"...","content_hi":"...","icon":"favorite_outline","confidence":80,"is_major":false}]}
Stored scan:
${JSON.stringify(dossier)}`;

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 4096,
          responseMimeType: "application/json",
        },
      }),
    },
  );
  if (!res.ok) {
    throw new Error(`Gemini ${res.status}: ${await res.text()}`);
  }
  const body = await res.json();
  const text = body?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return JSON.parse(extractJson(text));
}

function buildDossier(
  analysis: Record<string, unknown>,
  features: Record<string, unknown> | null,
) {
  const section = (key: string) => {
    const value = analysis[key];
    if (!value || typeof value !== "object") return "";
    const map = value as Record<string, unknown>;
    return clip(map.interpretation_en || map.summary_en || "");
  };
  const trait = (key: string) => lineBrief(features?.[key]);
  return {
    heart_line: trait("heart_line"),
    fate_line: trait("fate_line"),
    life_line: trait("life_line"),
    head_line: trait("head_line"),
    mercury_line: trait("mercury_line"),
    mounts: lineBrief(features?.mounts),
    love: section("love_analysis"),
    career: section("career_analysis"),
    wealth: section("wealth_analysis"),
    health: section("health_analysis"),
    life: section("life_analysis"),
    personality: section("personality_analysis"),
    summary: clip(analysis.summary),
  };
}

function fallback(
  period: string,
  dossier: ReturnType<typeof buildDossier>,
): Insight[] {
  const lead = period === "daily"
    ? "Today"
    : period === "weekly"
    ? "This week"
    : period === "monthly"
    ? "This month"
    : "This year";
  const items: Array<[string, string, string, string, string, string]> = [
    ["Love", "प्रेम", "favorite_outline", dossier.heart_line, "heart line", dossier.love],
    ["Career", "करियर", "work_outline", dossier.fate_line, "fate line", dossier.career],
    ["Wealth", "धन", "currency_rupee", dossier.mercury_line, "mercury line", dossier.wealth],
    ["Health", "स्वास्थ्य", "self_improvement", dossier.life_line, "life line", dossier.health || dossier.life],
    ["Mind", "मन", "auto_awesome", dossier.head_line, "head line", dossier.personality],
  ];
  return items
    .filter((item) => item[3] || item[5])
    .map((item) => {
      const trait = item[3] || item[4];
      const saved = item[5] || "The scan stored this line without a longer note.";
      const content = `${lead}, your ${trait} from your saved palm scan guides this ${period} reading. ${saved}`;
      return {
        category: item[0],
        category_hi: item[1],
        content,
        content_hi: content,
        icon: item[2],
        confidence: 76,
        is_major: false,
        source: "scan_traits",
      };
    });
}

function normalize(raw: unknown, period: string): Insight[] {
  const list = Array.isArray(raw)
    ? raw
    : raw && typeof raw === "object" && Array.isArray((raw as { insights?: unknown }).insights)
    ? (raw as { insights: unknown[] }).insights
    : [];
  return list
    .filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
    .map((item) => ({
      category: String(item.category ?? "Insight"),
      category_hi: String(item.category_hi ?? item.category ?? "Insight"),
      content: String(item.content ?? ""),
      content_hi: String(item.content_hi ?? item.content ?? ""),
      icon: String(item.icon ?? "auto_awesome"),
      confidence: Number(item.confidence ?? 75),
      is_major: item.is_major === true,
      source: "gemini",
    }))
    .filter((item) => item.content.trim().length > 40)
    .slice(0, 5);
}

function extractJson(text: string): string {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) return text.slice(start, end + 1);
  return text;
}

function clip(value: unknown, max = 380): string {
  const text = typeof value === "string" ? value.trim() : "";
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

function lineBrief(line: unknown): string {
  if (!line || typeof line !== "object" || Array.isArray(line)) return "";
  const map = line as Record<string, unknown>;
  const keys = ["length", "depth", "curve", "quality", "clarity", "shape", "strength"];
  return keys
    .filter((key) => map[key] != null && typeof map[key] !== "object" && String(map[key]).trim())
    .slice(0, 4)
    .map((key) => `${key} ${map[key]}`)
    .join(", ");
}

function periodBounds(): Record<string, { start: string; end: string }> {
  const shifted = new Date(Date.now() + 330 * 60 * 1000);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth();
  const day = shifted.getUTCDate();
  const weekday = shifted.getUTCDay();
  const mondayOffset = weekday === 0 ? 6 : weekday - 1;
  const monday = new Date(Date.UTC(year, month, day - mondayOffset));
  const sunday = new Date(Date.UTC(year, month, day - mondayOffset + 6));
  const monthEnd = new Date(Date.UTC(year, month + 1, 0));
  return {
    daily: { start: iso(year, month, day), end: iso(year, month, day) },
    weekly: {
      start: iso(monday.getUTCFullYear(), monday.getUTCMonth(), monday.getUTCDate()),
      end: iso(sunday.getUTCFullYear(), sunday.getUTCMonth(), sunday.getUTCDate()),
    },
    monthly: {
      start: iso(year, month, 1),
      end: iso(year, month, monthEnd.getUTCDate()),
    },
    yearly: { start: iso(year, 0, 1), end: iso(year, 11, 31) },
  };
}

function iso(year: number, month: number, day: number): string {
  return `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
