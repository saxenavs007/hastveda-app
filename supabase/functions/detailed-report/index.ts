// HastVeda Detailed Report Edge Function
// Generates a comprehensive 19-section detailed palm reading report
// from EXISTING saved palm_analysis + palm_features data.
// No new image analysis — reuses stored Gemini results.
//
// Security: GEMINI_API_KEY is stored server-side only, never exposed to client.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── JSON extraction helper ────────────────────────────────────────────────────
function extractJson(raw: string): string {
  let text = raw.trim();
  const fenceMatch = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  if (fenceMatch) text = fenceMatch[1].trim();
  const first = text.indexOf("{");
  const last = text.lastIndexOf("}");
  if (first !== -1 && last > first) text = text.slice(first, last + 1);
  return text;
}

const MAX_JSON_ATTEMPTS = 3;

async function callGeminiJson(
  label: string,
  prompt: string,
  temperature = 0.5,
  maxTokens = 20000
): Promise<any> {
  let lastParseError = "";

  for (let attempt = 1; attempt <= MAX_JSON_ATTEMPTS; attempt++) {
    const raw = await callGemini(prompt, temperature, maxTokens);
    try {
      return JSON.parse(extractJson(raw));
    } catch (e: any) {
      lastParseError = e?.message ?? String(e);
      const pos = Number(/position (\d+)/.exec(lastParseError)?.[1] ?? -1);
      console.error(
        `[detailed-report] ${label} returned unparseable JSON (attempt ${attempt}/${MAX_JSON_ATTEMPTS})`,
        {
          error: lastParseError,
          responseLength: raw.length,
          nearError:
            pos >= 0 ? raw.slice(Math.max(0, pos - 80), pos + 80) : undefined,
        }
      );
    }
  }

  throw new Error(
    `${label} returned malformed JSON after ${MAX_JSON_ATTEMPTS} attempts: ${lastParseError}`
  );
}

// ── Gemini model selection ────────────────────────────────────────────────────
const GEMINI_MODELS: string[] = [
  ...new Set(
    [
      Deno.env.get("GEMINI_MODEL"),
      "gemini-3.5-flash",
      "gemini-3.6-flash",
      "gemini-3.5-flash-lite",
    ].filter((m): m is string => !!m && m.trim().length > 0)
  ),
];

const CALL_BUDGET_MS = 110_000;
const MIN_ATTEMPT_MS = 12_000;

let thinkingSupported = true;
let activeModel: string | null = null;

function currentModel(): string {
  return activeModel ?? GEMINI_MODELS[0];
}

function isModelUnavailable(status: number, body: string): boolean {
  return status === 404 || (status === 400 && /not found|not supported/i.test(body));
}

const TRANSIENT_STATUSES = new Set([429, 500, 502, 503, 504]);
const MAX_ATTEMPTS_PER_MODEL = 3;

function backoffMs(attempt: number): number {
  return 700 * Math.pow(2, attempt);
}

const delay = (ms: number) => new Promise((r) => setTimeout(r, ms));

function modelCandidates(): string[] {
  if (!activeModel) return GEMINI_MODELS;
  return [activeModel, ...GEMINI_MODELS.filter((m) => m !== activeModel)];
}

// ── Gemini API helper ─────────────────────────────────────────────────────────
async function callGemini(
  prompt: string,
  temperature = 0.5,
  maxTokens = 20000
): Promise<string> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const buildBody = () => ({
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature,
      maxOutputTokens: maxTokens,
      responseMimeType: "application/json",
      ...(thinkingSupported ? { thinkingLevel: "low" } : {}),
    },
    safetySettings: [
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
    ],
  });

  let lastError = "";
  const startedAt = Date.now();
  const remainingMs = () => CALL_BUDGET_MS - (Date.now() - startedAt);

  for (const model of modelCandidates()) {
    let transientRetries = 0;

    while (true) {
      if (remainingMs() < MIN_ATTEMPT_MS) {
        console.warn(`[detailed-report] time budget exhausted before trying ${model}`);
        break;
      }

      const controller = new AbortController();
      const attemptMs = Math.min(90000, remainingMs());
      const timeoutId = setTimeout(() => controller.abort(), attemptMs);

      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(buildBody()),
            signal: controller.signal,
          }
        );

        if (!res.ok) {
          const errText = await res.text();
          lastError = `Gemini API error ${res.status}: ${errText}`;

          if (res.status === 400 && thinkingSupported && /thinking/i.test(errText)) {
            console.warn(`[detailed-report] ${model} rejected thinkingLevel, retrying without it`);
            thinkingSupported = false;
            continue;
          }

          if (isModelUnavailable(res.status, errText)) {
            console.warn(`[detailed-report] model ${model} unavailable (${res.status}), trying next`);
            break;
          }

          if (TRANSIENT_STATUSES.has(res.status) && transientRetries < MAX_ATTEMPTS_PER_MODEL - 1) {
            const wait = backoffMs(transientRetries);
            transientRetries++;
            console.warn(`[detailed-report] model ${model} transient ${res.status}, retry ${transientRetries}/${MAX_ATTEMPTS_PER_MODEL - 1} in ${wait}ms`);
            await delay(wait);
            continue;
          }

          if (TRANSIENT_STATUSES.has(res.status)) {
            console.warn(`[detailed-report] model ${model} still ${res.status} after retries, trying next`);
            break;
          }

          throw new Error(lastError);
        }

        const data = await res.json();
        const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        const finishReason =
          data?.candidates?.[0]?.finishReason ??
          data?.promptFeedback?.blockReason ??
          "unknown";

        if (!text) {
          throw new Error(`Empty response from Gemini (${model}, finishReason=${finishReason})`);
        }

        if (finishReason === "MAX_TOKENS") {
          throw new Error(
            `Gemini response truncated (${model}, maxOutputTokens=${maxTokens}) — raise the token budget`
          );
        }

        if (activeModel !== model) {
          console.log(`[detailed-report] using Gemini model ${model}`);
          activeModel = model;
        }
        return text;
      } catch (e: any) {
        const aborted = e?.name === "AbortError" || /abort/i.test(e?.message ?? "");
        if (aborted) {
          lastError = `Gemini request to ${model} timed out after ${attemptMs}ms`;
          console.warn(`[detailed-report] ${lastError}, trying next model`);
          break;
        }
        throw e;
      } finally {
        clearTimeout(timeoutId);
      }
    }
  }

  throw new Error(
    `No available Gemini model. Tried: ${modelCandidates().join(", ")}. Last error: ${lastError}`
  );
}

// ── Build comprehensive 19-section detailed report prompt ─────────────────────
function buildDetailedReportPrompt(
  analysisData: any,
  featuresData: any,
  language: string,
  isPremium: boolean,
  userName: string
): string {
  const isHindi = language === "hi";
  const langInstruction = isHindi
    ? "Generate ALL content (titles, descriptions, summaries, observations, strengths, challenges, recommendations) in Hindi (Devanagari script). Only keep technical palmistry terms in English if they have no standard Hindi equivalent."
    : "Generate ALL content in English.";

  const analysisJson = JSON.stringify({
    personality_analysis: analysisData.personality_analysis || {},
    life_analysis: analysisData.life_analysis || {},
    love_analysis: analysisData.love_analysis || {},
    career_analysis: analysisData.career_analysis || {},
    wealth_analysis: analysisData.wealth_analysis || {},
    health_analysis: analysisData.health_analysis || {},
    summary: analysisData.summary || "",
    summary_hi: analysisData.summary_hi || "",
    overall_score: analysisData.overall_score || 75,
    confidence_score: analysisData.confidence_score || 70,
  }, null, 2);

  const featuresJson = JSON.stringify({
    life_line: featuresData?.life_line || {},
    heart_line: featuresData?.heart_line || {},
    head_line: featuresData?.head_line || {},
    fate_line: featuresData?.fate_line || {},
    sun_line: featuresData?.sun_line || {},
    mercury_line: featuresData?.mercury_line || {},
    mounts: featuresData?.mounts || {},
    special_marks: featuresData?.special_marks || [],
    hand_type: featuresData?.hand_type || "",
    dominant_hand: featuresData?.dominant_hand || "",
  }, null, 2);

  const userNameStr = userName || "the individual";

  return `You are HastVeda's expert palmistry report generator. You are creating a COMPREHENSIVE, PREMIUM Detailed Palm Reading Report for ${userNameStr}.

LANGUAGE INSTRUCTION: ${langInstruction}

CRITICAL SAFETY RULES (MANDATORY):
- Never claim to predict death, disease, exact lifespan, pregnancy, fertility, criminal behavior, guaranteed financial returns, or legal outcomes.
- Always use language like "may suggest", "traditionally associated with", "can indicate", "your reading suggests", "palmistry tradition holds".
- Clearly frame all content as traditional palmistry interpretation, not scientific fact.
- Do not generate fear-based predictions.
- Only interpret features that are marked as visible:true in the palm features data.
- If a feature is not visible or has low confidence, acknowledge the limitation gracefully.
- NEVER invent palm features, lines, mounts, or predictions not supported by the existing analysis data.
- Where information is unavailable, provide a brief graceful acknowledgment rather than fabricating content.

IMPORTANT: This must be a GENUINELY COMPREHENSIVE report. Each section should contain 3-5 meaningful paragraphs of explanatory content, not just 1-2 sentences. Use the palm analysis data to provide rich, personalized interpretation. The report should feel like a genuine personalized reading from an expert palmist.

EXISTING PALM ANALYSIS DATA (use this as the primary source — do NOT invent new observations):
${analysisJson}

EXISTING PALM FEATURES DATA (raw observations from the palm image):
${featuresJson}

PREMIUM ACCESS: ${isPremium ? "Full premium report — include all 19 sections with comprehensive content" : "Free tier — include basic sections only"}

Generate a COMPREHENSIVE 19-section Detailed Palm Reading Report. Return ONLY valid JSON (no markdown fences) matching this EXACT structure:

{
  "executive_summary": {
    "title": <string>,
    "content": <string, 4-5 sentences synthesizing the most important insights from the entire reading — this is the first thing the user reads, make it compelling and personalized>,
    "key_highlights": <array of 4-5 short highlight strings>,
    "overall_score": <integer 60-95>
  },
  "overall_palm_overview": {
    "title": <string>,
    "content": <string, 4-5 sentences describing the overall palm — hand type, general characteristics, dominant features observed, what this suggests about the person's nature>,
    "hand_type": <string, describe the hand type if available>,
    "key_observations": <array of 3-5 notable overall observations>,
    "score": <integer 60-95>
  },
  "personality_character": {
    "title": <string>,
    "content": <string, 4-5 sentences about personality traits derived from the palm — be specific and personalized based on the analysis data>,
    "traits": <array of 5-7 personality trait strings>,
    "score": <integer 60-95>
  },
  "head_line_analysis": {
    "title": <string>,
    "content": <string, 4-5 sentences about the head line — its length, depth, curve, what it says about thinking style, decision-making, intellectual tendencies>,
    "observations": <array of 3-4 specific observations from head line>,
    "score": <integer 60-95>
  },
  "heart_line_analysis": {
    "title": <string>,
    "content": <string, 4-5 sentences about the heart line — its characteristics, what it reveals about emotional nature, love style, relationship approach>,
    "observations": <array of 3-4 specific observations from heart line>,
    "score": <integer 60-95>
  },
  "life_line_analysis": {
    "title": <string>,
    "content": <string, 4-5 sentences about the life line — its length, depth, curve, what it traditionally suggests about vitality, energy levels, life journey>,
    "observations": <array of 3-4 specific observations from life line>,
    "score": <integer 60-95>
  },
  "fate_career_line": {
    "title": <string>,
    "content": <string, 4-5 sentences about the fate/career line — its presence, characteristics, what it suggests about career path, ambition, life direction. If not clearly visible, acknowledge gracefully>,
    "observations": <array of 2-4 specific observations>,
    "score": <integer 60-95>
  },
  "major_palm_features": {
    "title": <string>,
    "content": <string, 3-4 sentences overview of notable mounts, marks, and special features observed>,
    "lines": [
      {
        "name": <string, line/feature name>,
        "visible": <boolean>,
        "description": <string, 2-3 sentences about this specific feature if visible, or brief acknowledgment if not>
      }
    ]
  },
  "career_professional": {
    "title": <string>,
    "content": <string, 4-5 sentences about career tendencies, professional strengths, suitable fields, work style — derived from fate line, sun line, head line, and mounts data>,
    "observations": <array of 3-5 specific career observations>,
    "score": <integer 60-95>
  },
  "financial_wealth": {
    "title": <string>,
    "content": <string, 4-5 sentences about financial tendencies, wealth indicators, money management style, financial strengths and cautions — based on available analysis data>,
    "observations": <array of 3-4 specific financial observations>,
    "score": <integer 60-95>
  },
  "love_relationships": {
    "title": <string>,
    "content": <string, 4-5 sentences about love style, relationship approach, emotional needs, compatibility tendencies — derived from heart line and love analysis data>,
    "observations": <array of 3-4 specific relationship observations>,
    "score": <integer 60-95>
  },
  "marriage_partnership": {
    "title": <string>,
    "content": <string, 3-5 sentences about marriage/partnership indicators — what the palm traditionally suggests about long-term partnerships, commitment style. Frame carefully as traditional interpretation>,
    "observations": <array of 2-4 specific observations>
  },
  "health_vitality": {
    "title": <string>,
    "content": <string, 4-5 sentences about health tendencies, vitality indicators, energy patterns — derived from life line and health analysis. Always frame as tendencies, never diagnoses>,
    "observations": <array of 3-4 specific health tendency observations>,
    "score": <integer 60-95>
  },
  "family_social": {
    "title": <string>,
    "content": <string, 3-4 sentences about family orientation, social nature, community connections — derived from available analysis data>,
    "observations": <array of 2-4 specific observations>
  },
  "key_strengths": {
    "title": <string>,
    "content": <string, 3-4 sentences about the person's key strengths as indicated by the palm — be specific and encouraging>,
    "strengths": <array of 5-7 strength strings>
  },
  "challenges_growth": {
    "title": <string>,
    "content": <string, 3-4 sentences about areas requiring attention or growth — frame positively as opportunities for development, not as warnings>,
    "areas": <array of 4-6 area strings, framed as growth opportunities>
  },
  "future_tendencies": {
    "title": <string>,
    "content": <string, 4-5 sentences about future tendencies and important life periods — frame carefully as traditional palmistry interpretation of potential tendencies, not predictions. Use language like "the palm may suggest", "traditionally associated with">,
    "observations": <array of 3-5 future tendency observations>
  },
  "practical_guidance": {
    "title": <string>,
    "content": <string, 4-5 sentences of practical guidance and remedies based on the reading — actionable suggestions for personal development, areas to focus on, how to leverage strengths>,
    "guidance_points": <array of 4-6 specific practical guidance strings>
  },
  "final_guidance": {
    "title": <string>,
    "content": <string, 4-5 sentences of overall final guidance — synthesize the reading into meaningful life wisdom, encourage self-reflection and personal growth>,
    "closing_note": <string, 2-3 sentences of warm, encouraging closing message>,
    "disclaimer": <string, comprehensive disclaimer stating this is AI-generated traditional palmistry interpretation, not medical/financial/legal/professional advice, for self-reflection and entertainment only>
  },
  "metadata": {
    "language": "${language}",
    "is_premium": ${isPremium},
    "confidence_score": ${analysisData.confidence_score || 70},
    "generated_at": "${new Date().toISOString()}",
    "section_count": 19
  }
}`;
}

// Sends the PDF via email-report after the HTTP response is returned.
// email-report builds the PDF and delivers it with Resend to the account email.
function queueDetailedReportEmail(
  supabaseUrl: string,
  anonKey: string,
  authHeader: string,
  reportId: string,
  locale: string,
): boolean {
  const task = fetch(`${supabaseUrl}/functions/v1/email-report`, {
    method: "POST",
    headers: {
      Authorization: authHeader,
      apikey: anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ report_id: reportId, locale }),
  })
    .then(async (res) => {
      if (!res.ok) {
        const text = await res.text();
        console.error(
          `[detailed-report] async email-report failed status=${res.status} body=${text}`,
        );
        return;
      }
      console.log(
        `[detailed-report] async email-report accepted for report=${reportId}`,
      );
    })
    .catch((err) => {
      console.error("[detailed-report] async email-report trigger error:", err);
    });

  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil: (promise: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(task);
  } else {
    console.warn(
      "[detailed-report] EdgeRuntime.waitUntil unavailable; email task may be cancelled",
    );
  }
  return true;
}

// ── Main handler ──────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    // ── Auth ────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "AUTH_REQUIRED" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "INVALID_TOKEN" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = user.id;

    // ── Parse request ───────────────────────────────────────────────────────
    const body = await req.json();
    const {
      analysis_id,
      reading_id,
      language = "en",
      force_regenerate = false,
    } = body;

    if (!analysis_id && !reading_id) {
      return new Response(
        JSON.stringify({ error: "analysis_id or reading_id is required", code: "MISSING_ID" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Resolve analysis_id from reading_id if needed ───────────────────────
    let resolvedAnalysisId = analysis_id;
    let resolvedReadingId = reading_id;

    if (!resolvedAnalysisId && resolvedReadingId) {
      const { data: historyRecord } = await userClient
        .from("reading_history")
        .select("analysis_id, id")
        .eq("id", resolvedReadingId)
        .eq("user_id", userId)
        .maybeSingle();

      if (!historyRecord?.analysis_id) {
        return new Response(
          JSON.stringify({ error: "No palm analysis found for this reading", code: "NO_ANALYSIS" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      resolvedAnalysisId = historyRecord.analysis_id;
    }

    // ── Check entitlements ──────────────────────────────────────────────────
    const { data: entitlements } = await userClient
      .from("entitlements")
      .select("entitlement_type, is_active, expires_at")
      .eq("user_id", userId)
      .eq("is_active", true);

    const now = new Date();
    const isPremium = (entitlements || []).some((e: any) => {
      if (e.entitlement_type !== "PREMIUM") return false;
      if (!e.expires_at) return true;
      return new Date(e.expires_at) > now;
    });

    const hasDetailedReportEntitlement = (entitlements || []).some((e: any) => {
      if (!["PREMIUM", "DETAILED_REPORT"].includes(e.entitlement_type)) return false;
      if (!e.is_active) return false;
      if (!e.expires_at) return true;
      return new Date(e.expires_at) > now;
    });

    if (!hasDetailedReportEntitlement) {
      return new Response(
        JSON.stringify({
          error: "Detailed Report requires Premium or Detailed Report entitlement",
          code: "ENTITLEMENT_REQUIRED",
          required_entitlement: "DETAILED_REPORT",
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Check for existing saved report (cache) ─────────────────────────────
    if (!force_regenerate) {
      const { data: existingReport } = await userClient
        .from("reports")
        .select("id, content, generated_at, created_at")
        .eq("analysis_id", resolvedAnalysisId)
        .eq("user_id", userId)
        .eq("report_type", "detailed_analysis")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existingReport?.content && Object.keys(existingReport.content).length > 0) {
        // Check if this is the new 19-section format
        const content = existingReport.content as any;
        const hasNewFormat = content.executive_summary || content.head_line_analysis;
        if (hasNewFormat) {
          const emailQueued = Boolean(user.email) &&
            queueDetailedReportEmail(
              supabaseUrl,
              supabaseAnonKey,
              authHeader,
              existingReport.id,
              language,
            );
          return new Response(
            JSON.stringify({
              success: true,
              report_id: existingReport.id,
              cached: true,
              report: existingReport.content,
              generated_at: existingReport.generated_at || existingReport.created_at,
              email_queued: emailQueued,
              email: user.email ?? null,
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        // Old format — regenerate with new 19-section format
        console.log("[detailed-report] Old format detected, regenerating with 19-section format");
      }
    }

    // ── Fetch palm analysis data ────────────────────────────────────────────
    const { data: analysisData, error: analysisError } = await userClient
      .from("palm_analysis")
      .select("*")
      .eq("id", resolvedAnalysisId)
      .eq("user_id", userId)
      .eq("status", "completed")
      .maybeSingle();

    if (analysisError || !analysisData) {
      return new Response(
        JSON.stringify({
          error: "Palm analysis not found or not completed yet",
          code: "ANALYSIS_NOT_FOUND",
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Fetch palm features data ────────────────────────────────────────────
    let featuresData: any = null;
    if (analysisData.features_id) {
      const { data: features } = await userClient
        .from("palm_features")
        .select("*")
        .eq("id", analysisData.features_id)
        .maybeSingle();
      featuresData = features;
    }

    if (!featuresData && analysisData.scan_id) {
      const { data: features } = await userClient
        .from("palm_features")
        .select("*")
        .eq("scan_id", analysisData.scan_id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      featuresData = features;
    }

    // ── Fetch user profile for personalization ──────────────────────────────
    let userName = "";
    try {
      const { data: profile } = await userClient
        .from("user_profiles")
        .select("full_name")
        .eq("id", userId)
        .maybeSingle();
      userName = profile?.full_name || "";
    } catch (_) {}

    // ── Generate detailed report via Gemini ─────────────────────────────────
    let reportContent: any;
    try {
      const prompt = buildDetailedReportPrompt(analysisData, featuresData, language, isPremium, userName);
      reportContent = await callGeminiJson("Report", prompt, 0.5, 20000);
    } catch (e: any) {
      console.error("Gemini report generation error:", e);
      return new Response(
        JSON.stringify({
          error: "Report generation failed. Please try again.",
          code: "GENERATION_FAILED",
          details: e.message,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const processingTimeMs = Date.now() - startTime;

    // Add metadata to report content
    reportContent.metadata = {
      ...reportContent.metadata,
      language,
      is_premium: isPremium,
      analysis_id: resolvedAnalysisId,
      processing_time_ms: processingTimeMs,
      generated_at: new Date().toISOString(),
      user_name: userName,
      section_count: 19,
    };

    // ── Save report to reports table ────────────────────────────────────────
    const { data: savedReport, error: saveError } = await serviceClient
      .from("reports")
      .insert({
        user_id: userId,
        analysis_id: resolvedAnalysisId,
        report_type: "detailed_analysis",
        title: language === "hi" ? "विस्तृत हस्तरेखा रिपोर्ट" : "Detailed Palm Reading Report",
        content: reportContent,
        is_premium: isPremium,
        generated_at: new Date().toISOString(),
        metadata: {
          language,
          reading_id: resolvedReadingId || null,
          analysis_id: resolvedAnalysisId,
          section_count: 19,
        },
      })
      .select("id")
      .single();

    if (saveError) {
      console.error("Report save error:", saveError);
    }

    // ── Update reading_history metadata with report_id ──────────────────────
    if (savedReport?.id && resolvedReadingId) {
      await serviceClient
        .from("reading_history")
        .update({
          metadata: {
            detailed_report_id: savedReport.id,
            analysis_id: resolvedAnalysisId,
          },
        })
        .eq("id", resolvedReadingId)
        .eq("user_id", userId);
    } else if (savedReport?.id && resolvedAnalysisId) {
      await serviceClient
        .from("reading_history")
        .update({
          metadata: {
            detailed_report_id: savedReport.id,
            analysis_id: resolvedAnalysisId,
          },
        })
        .eq("analysis_id", resolvedAnalysisId)
        .eq("user_id", userId);
    }

    // ── Log AI usage ─────────────────────────────────────────────────────────
    await serviceClient.from("ai_usage").insert({
      user_id: userId,
      analysis_id: resolvedAnalysisId,
      ai_provider: "google",
      ai_model: currentModel(),
      operation_type: "detailed_report",
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      latency_ms: processingTimeMs,
      success: true,
    });

    let emailQueued = false;
    if (savedReport?.id && user.email) {
      emailQueued = queueDetailedReportEmail(
        supabaseUrl,
        supabaseAnonKey,
        authHeader,
        savedReport.id,
        language,
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        report_id: savedReport?.id || null,
        cached: false,
        report: reportContent,
        generated_at: new Date().toISOString(),
        email_queued: emailQueued,
        email: user.email ?? null,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Detailed report error:", error);
    return new Response(
      JSON.stringify({
        error: "An unexpected error occurred. Please try again.",
        code: "INTERNAL_ERROR",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
