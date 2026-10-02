// HastVeda Palm Analysis Edge Function — V2 Phase 1
// Two-stage Gemini vision pipeline:
//   Stage A: Image quality validation + structured palm feature extraction
//            → builds a Palm Intelligence Profile (signals → observations → interpretations → life areas)
//   Stage B: Personalized reading narrative generated FROM the Palm Intelligence Profile
//            (not from a generic prompt), so two different palms produce different readings.
//
// Languages: English (en) | Hindi (hi) | Hinglish (hi-Latn)
// Security: GEMINI_API_KEY is stored server-side only, never exposed to client.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── JSON extraction helper (strips markdown code fences if present) ────────────
function extractJson(raw: string): string {
  let text = raw.trim();
  const fenceMatch = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  if (fenceMatch) text = fenceMatch[1].trim();
  const first = text.indexOf("{");
  const last = text.lastIndexOf("}");
  if (first !== -1 && last > first) text = text.slice(first, last + 1);
  return text;
}

// ── Guarded writes ────────────────────────────────────────────────────────────
async function writeAnalysis(
  client: any,
  analysisId: string,
  updates: Record<string, unknown>,
  label: string
): Promise<boolean> {
  const { error } = await client
    .from("palm_analysis")
    .update(updates)
    .eq("id", analysisId);
  if (error) {
    console.error(`[palm-analysis] ${label} update FAILED`, {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });
    return false;
  }
  return true;
}

async function writeSideEffect(
  op: PromiseLike<{ error: unknown | null }>,
  label: string
): Promise<void> {
  const { error } = await op;
  if (error) {
    const e = error as { code?: string; message?: string };
    console.error(`[palm-analysis] ${label} FAILED`, {
      code: e?.code,
      message: e?.message,
    });
  }
}

// ── Failure logging ───────────────────────────────────────────────────────────
// Every failure path writes exactly one row to palm_analysis_failures so a
// failed attempt stays diagnosable long after the device log has rotated.
// Logging must never mask the original error: all writes are best-effort.

/** Closed set of reasons. The client maps these to a specific user-facing message. */
type FailureCode =
  | "NO_PALM_DETECTED"
  | "PARTIAL_PALM"
  | "TOO_BLURRY"
  | "TOO_DARK"
  | "TOO_BRIGHT"
  | "TOO_FAR"
  | "TOO_CLOSE"
  | "OBSTRUCTED"
  | "WRONG_SIDE"
  | "LOW_QUALITY_IMAGE"
  | "AI_SERVICE_BUSY"
  | "AI_TIMEOUT"
  | "AI_RESPONSE_TRUNCATED"
  | "STAGE_A_FAILED"
  | "STAGE_B_FAILED"
  | "FREE_LIMIT_REACHED"
  | "PERSIST_FAILED"
  | "UNKNOWN";

/** Strips anything key-shaped before an upstream message is persisted. */
function sanitizeMessage(input: string): string {
  return (input || "")
    .replace(/[A-Za-z0-9_\-]{32,}/g, "[REDACTED]")
    .replace(/Bearer\s+\S+/gi, "Bearer [REDACTED]")
    .replace(/(key|token|secret)[=:]\s*\S+/gi, "$1=[REDACTED]")
    .slice(0, 2000);
}

interface FailureLogInput {
  userId?: string;
  scanId?: string;
  analysisId?: string;
  handSide?: string;
  language?: string;
  stage: "quota" | "stage_a" | "quality_gate" | "stage_b" | "persist" | "unknown";
  failureCode: FailureCode;
  reason: string;
  qualityScore?: number | null;
  palmDetected?: boolean | null;
  suitableForAnalysis?: boolean | null;
  qualityIssues?: unknown[];
  httpStatus?: number;
  imagePath?: string;
  imageBytes?: number;
  providerMessage?: string;
  appVersion?: string;
  platform?: string;
  deviceModel?: string;
}

async function logFailure(client: any, input: FailureLogInput): Promise<void> {
  try {
    // attempt_number makes "failed on attempt 1, succeeded on attempt 2"
    // readable straight from the table without joining scan history.
    let attemptNumber: number | null = null;
    if (input.userId && input.handSide) {
      const { count } = await client
        .from("palm_scans")
        .select("id", { count: "exact", head: true })
        .eq("user_id", input.userId)
        .eq("hand_type", input.handSide);
      attemptNumber = typeof count === "number" ? count : null;
    }

    const { error } = await client.from("palm_analysis_failures").insert({
      user_id: input.userId ?? null,
      scan_id: input.scanId ?? null,
      analysis_id: input.analysisId ?? null,
      hand_side: input.handSide ?? null,
      language: input.language ?? null,
      attempt_number: attemptNumber,
      stage: input.stage,
      failure_code: input.failureCode,
      reason: input.reason?.slice(0, 2000) ?? null,
      quality_score: input.qualityScore ?? null,
      palm_detected: input.palmDetected ?? null,
      suitable_for_analysis: input.suitableForAnalysis ?? null,
      quality_issues: input.qualityIssues ?? [],
      http_status: input.httpStatus ?? null,
      image_path: input.imagePath ?? null,
      image_bytes: input.imageBytes ?? null,
      provider_message: input.providerMessage
        ? sanitizeMessage(input.providerMessage)
        : null,
      app_version: input.appVersion ?? null,
      platform: input.platform ?? null,
      device_model: input.deviceModel ?? null,
    });

    if (error) {
      console.error("[palm-analysis] failure log insert FAILED", {
        code: error.code,
        message: error.message,
      });
    } else {
      console.log("[palm-analysis] failure logged", {
        stage: input.stage,
        code: input.failureCode,
        scan_id: input.scanId,
        quality_score: input.qualityScore,
        palm_detected: input.palmDetected,
      });
    }
  } catch (e: any) {
    // Never let diagnostics break the response path.
    console.error("[palm-analysis] failure log threw", { message: e?.message });
  }
}

// ── Quality-gate reason resolution ────────────────────────────────────────────
// Turns Gemini's image_quality block into ONE specific reason code. The model is
// asked for `primary_issue` directly; the keyword pass over `issues` is the
// fallback for older/looser responses so the client is never left with a bare
// "low quality".
const PRIMARY_ISSUE_CODES: Record<string, FailureCode> = {
  no_palm: "NO_PALM_DETECTED",
  partial_palm: "PARTIAL_PALM",
  blurry: "TOO_BLURRY",
  too_dark: "TOO_DARK",
  too_bright: "TOO_BRIGHT",
  too_far: "TOO_FAR",
  too_close: "TOO_CLOSE",
  obstructed: "OBSTRUCTED",
  wrong_side: "WRONG_SIDE",
};

/** Ordered most-specific first: the first keyword hit wins. */
const ISSUE_KEYWORD_RULES: Array<[RegExp, FailureCode]> = [
  [/no palm|not a palm|no hand|palm (is )?not (visible|present|detected)/i, "NO_PALM_DETECTED"],
  [/partial|cut off|cropped|out of frame|outside the frame|not fully|incomplete/i, "PARTIAL_PALM"],
  [/blur|out of focus|motion|shaky|unsharp|soft focus/i, "TOO_BLURRY"],
  [/too dark|underexposed|low light|dim|shadow/i, "TOO_DARK"],
  [/too bright|overexposed|glare|washed out|reflection|flash/i, "TOO_BRIGHT"],
  [/too far|small in frame|distant|zoom in/i, "TOO_FAR"],
  [/too close|cropped by proximity|zoom out/i, "TOO_CLOSE"],
  [/obstruct|covered|occlud|glove|ring|jewel|henna|mehndi|dirt|writing/i, "OBSTRUCTED"],
  [/back of (the )?hand|dorsal|wrong side|knuckle/i, "WRONG_SIDE"],
];

function resolveQualityFailure(imageQuality: any): {
  code: FailureCode;
  reason: string;
} {
  const palmDetected = imageQuality?.palm_detected === true;
  const issues: string[] = Array.isArray(imageQuality?.issues)
    ? imageQuality.issues.filter((i: unknown) => typeof i === "string")
    : [];

  // 1. Model-declared primary issue is the most trustworthy signal.
  const primary = String(imageQuality?.primary_issue ?? "").toLowerCase().trim();
  if (primary && PRIMARY_ISSUE_CODES[primary]) {
    return {
      code: PRIMARY_ISSUE_CODES[primary],
      reason: issues[0] ?? primary.replace(/_/g, " "),
    };
  }

  // 2. No palm at all outranks any keyword match.
  if (!palmDetected) {
    return {
      code: "NO_PALM_DETECTED",
      reason: issues[0] ?? "No palm was detected in the image",
    };
  }

  // 3. Keyword pass over the free-text issues.
  const haystack = issues.join(" | ");
  for (const [pattern, code] of ISSUE_KEYWORD_RULES) {
    if (pattern.test(haystack)) {
      return { code, reason: issues.find((i) => pattern.test(i)) ?? haystack };
    }
  }

  // 4. Genuinely unclassifiable — a palm was seen but scored too low.
  return {
    code: "LOW_QUALITY_IMAGE",
    reason: issues[0] ?? "Image quality was below the analysis threshold",
  };
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

const MAX_JSON_ATTEMPTS = 3;

async function callGeminiJson(
  label: string,
  prompt: string,
  imageBase64?: string,
  imageMimeType?: string,
  temperature = 0.3,
  maxTokens = 8192
): Promise<any> {
  let lastParseError = "";

  for (let attempt = 1; attempt <= MAX_JSON_ATTEMPTS; attempt++) {
    const raw = await callGemini(
      prompt,
      imageBase64,
      imageMimeType,
      temperature,
      maxTokens
    );
    try {
      return JSON.parse(extractJson(raw));
    } catch (e: any) {
      lastParseError = e?.message ?? String(e);
      const pos = Number(/position (\d+)/.exec(lastParseError)?.[1] ?? -1);
      console.error(
        `[palm-analysis] ${label} returned unparseable JSON (attempt ${attempt}/${MAX_JSON_ATTEMPTS})`,
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

// ── Failure classification ────────────────────────────────────────────────────
function classifyFailure(message: string): {
  code: string;
  status: number;
  error: string;
} {
  if (
    /Gemini API error (429|500|502|503|504)|high demand|UNAVAILABLE|overloaded|RESOURCE_EXHAUSTED|No available Gemini model/i
      .test(message)
  ) {
    return {
      code: "AI_SERVICE_BUSY",
      status: 503,
      error: "The AI service is busy right now. Please try again in a moment.",
    };
  }
  if (/truncated|MAX_TOKENS/i.test(message)) {
    return {
      code: "AI_RESPONSE_TRUNCATED",
      status: 502,
      error: "The analysis was cut short. Please try again.",
    };
  }
  if (/timed out|timeout|aborted|AbortError/i.test(message)) {
    return {
      code: "AI_TIMEOUT",
      status: 504,
      error: "The analysis took too long. Please try again.",
    };
  }
  return { code: "", status: 500, error: "" };
}

// ── Gemini API helper ─────────────────────────────────────────────────────────
async function callGemini(
  prompt: string,
  imageBase64?: string,
  imageMimeType?: string,
  temperature = 0.3,
  maxTokens = 8192
): Promise<string> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const parts: any[] = [];
  if (imageBase64 && imageMimeType) {
    parts.push({
      inlineData: { mimeType: imageMimeType, data: imageBase64 },
    });
  }
  parts.push({ text: prompt });

  const buildBody = () => ({
    contents: [{ role: "user", parts }],
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
        console.warn(`[palm-analysis] time budget exhausted before trying ${model}`);
        break;
      }

      const controller = new AbortController();
      const attemptMs = Math.min(55000, remainingMs());
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

          if (
            res.status === 400 &&
            thinkingSupported &&
            /thinking/i.test(errText)
          ) {
            console.warn(`[palm-analysis] ${model} rejected thinkingLevel, retrying without it`);
            thinkingSupported = false;
            continue;
          }

          if (isModelUnavailable(res.status, errText)) {
            console.warn(`[palm-analysis] model ${model} unavailable (${res.status}), trying next`);
            break;
          }

          if (
            TRANSIENT_STATUSES.has(res.status) &&
            transientRetries < MAX_ATTEMPTS_PER_MODEL - 1
          ) {
            const wait = backoffMs(transientRetries);
            transientRetries++;
            console.warn(
              `[palm-analysis] model ${model} transient ${res.status}, retry ${transientRetries}/${MAX_ATTEMPTS_PER_MODEL - 1} in ${wait}ms`
            );
            await delay(wait);
            continue;
          }

          if (TRANSIENT_STATUSES.has(res.status)) {
            console.warn(`[palm-analysis] model ${model} still ${res.status} after retries, trying next`);
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
          console.log(`[palm-analysis] using Gemini model ${model}`);
          activeModel = model;
        }
        return text;
      } catch (e: any) {
        const aborted =
          e?.name === "AbortError" || /abort/i.test(e?.message ?? "");
        if (aborted) {
          lastError = `Gemini request to ${model} timed out after ${attemptMs}ms`;
          console.warn(`[palm-analysis] ${lastError}, trying next model`);
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

// ── Free tier scan quota ──────────────────────────────────────────────────────
const DEFAULT_FREE_SCANS_PER_MONTH = 2;

async function freeScansUsedThisMonth(
  client: any,
  userId: string,
  currentScanId: string
): Promise<number> {
  const now = new Date();
  const monthStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)
  ).toISOString();

  const { count, error } = await client
    .from("palm_scans")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", monthStart)
    .neq("id", currentScanId);

  if (error) {
    console.error("[palm-analysis] free scan count FAILED", {
      code: error.code,
      message: error.message,
    });
    return 0;
  }
  return count ?? 0;
}

async function freeScanLimit(client: any): Promise<number> {
  const { data, error } = await client
    .from("app_settings")
    .select("value")
    .eq("key", "free_tier_limits")
    .maybeSingle();

  if (error || !data) return DEFAULT_FREE_SCANS_PER_MONTH;
  const configured = Number(data.value?.scans_per_month);
  return Number.isFinite(configured) && configured > 0
    ? configured
    : DEFAULT_FREE_SCANS_PER_MONTH;
}

// ── Stage A: Image validation + feature extraction + Palm Intelligence Profile ─
// Stage A now produces TWO outputs in one Gemini call:
//   1. Raw palm features (image quality, lines, mounts, marks) — same as before
//   2. Palm Intelligence Profile: structured signals → observations → interpretations → life areas
//      This profile is the foundation for a personalized reading. Two different palms MUST produce
//      different profiles. Only report features that are actually visible in the image.
//
// IMPORTANT SAFETY RULES:
// - Never claim to predict death, disease, exact lifespan, pregnancy, fertility, criminal behavior,
//   guaranteed financial returns, or legal outcomes.
// - Use language like "may suggest", "traditionally associated with", "can indicate".
// - If a feature is not clearly visible, set visible:false and confidence below 0.5.
// - Only report features that are actually observable in the image.
function buildStageAPrompt(handSide: string): string {
  return `You are HastVeda's expert palm analysis AI. You perform two tasks in one response:

TASK 1 — Raw Feature Extraction: Identify all visible palm features from the image.
TASK 2 — Palm Intelligence Profile: Convert those features into a structured intelligence profile
  (signal → observation → interpretation → life_area → confidence).

This profile is the foundation for a personalized reading. Two different palms MUST produce
different profiles. Only report features that are actually visible in the image.

IMPORTANT SAFETY RULES:
- Never claim to predict death, disease, exact lifespan, pregnancy, fertility, criminal behavior,
  guaranteed financial returns, or legal outcomes.
- Use language like "may suggest", "traditionally associated with", "can indicate".
- If a feature is not clearly visible, set visible:false and confidence below 0.5.
- Only report features that are actually observable in the image.

Hand side: ${handSide}

IMAGE QUALITY ASSESSMENT — be precise, the user is shown a correction tip based on it:
- Judge quality ONLY on whether the palm lines can actually be read. Do not lower the
  score for skin tone, hand size, age, jewellery that does not cover lines, or background.
- "primary_issue" must name the SINGLE biggest thing the user has to fix. Use "none"
  when the image is usable. Pick the most actionable one if several apply:
    no_palm       — no hand/palm in the frame at all, or the subject is not a palm
    partial_palm  — palm is cut off by the frame edge; not all of it is visible
    wrong_side    — the back of the hand is showing instead of the palm
    blurry        — motion blur or out of focus; line edges are not sharp
    too_dark      — underexposed; lines lost in shadow
    too_bright    — overexposed, glare or flash reflection washing out lines
    too_far       — palm occupies too little of the frame to resolve fine lines
    too_close     — so close that part of the palm is cropped or out of focus
    obstructed    — lines covered by henna, heavy writing, dirt, a glove or a ring
- "issues" must be short, user-actionable phrases ("palm is cut off at the bottom"),
  not internal notes.

Return ONLY valid JSON (no markdown fences) matching this exact structure:

{
  "image_quality": {
    "score": <0.0-1.0 float>,
    "palm_detected": <boolean>,
    "primary_issue": <"none"|"no_palm"|"partial_palm"|"blurry"|"too_dark"|"too_bright"|"too_far"|"too_close"|"obstructed"|"wrong_side">,
    "issues": <array of strings, empty if none>,
    "suitable_for_analysis": <boolean>
  },
  "hand_side": "${handSide}",
  "palm_shape": {
    "shape_type": <"square"|"rectangular"|"spatulate"|"conic"|"psychic"|"mixed"|"unknown">,
    "confidence": <0.0-1.0>,
    "observations": <array of strings>
  },
  "palm_features": {
    "life_line": {
      "visible": <boolean>,
      "confidence": <0.0-1.0>,
      "length": <"short"|"medium"|"long"|"unknown">,
      "depth": <"faint"|"moderate"|"deep"|"unknown">,
      "continuity": <"broken"|"chained"|"continuous"|"unknown">,
      "curvature": <"slight"|"moderate"|"pronounced"|"unknown">,
      "branches": <boolean>,
      "observations": <array of strings, max 3>
    },
    "head_line": {
      "visible": <boolean>,
      "confidence": <0.0-1.0>,
      "length": <"short"|"medium"|"long"|"unknown">,
      "depth": <"faint"|"moderate"|"deep"|"unknown">,
      "direction": <"straight"|"curved_down"|"curved_up"|"sloping"|"unknown">,
      "continuity": <"broken"|"chained"|"continuous"|"unknown">,
      "observations": <array of strings, max 3>
    },
    "heart_line": {
      "visible": <boolean>,
      "confidence": <0.0-1.0>,
      "length": <"short"|"medium"|"long"|"unknown">,
      "depth": <"faint"|"moderate"|"deep"|"unknown">,
      "curvature": <"slight"|"moderate"|"pronounced"|"unknown">,
      "continuity": <"broken"|"chained"|"continuous"|"unknown">,
      "observations": <array of strings, max 3>
    },
    "fate_line": {
      "visible": <boolean>,
      "confidence": <0.0-1.0>,
      "length": <"short"|"medium"|"long"|"absent"|"unknown">,
      "depth": <"faint"|"moderate"|"deep"|"unknown">,
      "continuity": <"broken"|"chained"|"continuous"|"unknown">,
      "observations": <array of strings, max 3>
    },
    "sun_line": {
      "visible": <boolean>,
      "confidence": <0.0-1.0>,
      "observations": <array of strings, max 2>
    },
    "mercury_line": {
      "visible": <boolean>,
      "confidence": <0.0-1.0>,
      "observations": <array of strings, max 2>
    }
  },
  "mounts": {
    "jupiter": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "saturn": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "apollo": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "mercury": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "venus": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "moon": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "mars_upper": <"flat"|"raised"|"overdeveloped"|"unknown">,
    "mars_lower": <"flat"|"raised"|"overdeveloped"|"unknown">
  },
  "special_marks": <array of strings describing any notable marks, crosses, stars, triangles, max 5>,
  "overall_confidence": <0.0-1.0 float, average of visible feature confidences>,

  "palm_intelligence_profile": {
    "profile_version": "1.0",
    "signal_count": <integer, total number of meaningful signals identified>,
    "overall_confidence": <0.0-1.0>,

    "signals": [
      {
        "signal_id": <string, e.g. "life_line_length_long">,
        "source_feature": <string, e.g. "life_line">,
        "signal": <string, concise signal name, e.g. "Long, deep life line">,
        "observation": <string, what is literally visible in the image>,
        "interpretation": <string, traditional palmistry meaning of this specific observation>,
        "life_areas": <array of strings from: "personality","career","money","relationships","health","future","strengths","challenges">,
        "confidence": <0.0-1.0>,
        "is_positive": <boolean>
      }
    ],

    "life_area_interpretations": {
      "personality": {
        "primary_signals": <array of signal_ids that most influence this area>,
        "key_traits": <array of 2-4 specific trait strings derived from actual palm signals>,
        "interpretation_basis": <string, which palm features drive this interpretation>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "career": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific career tendency strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "money": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific financial tendency strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "relationships": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific relationship tendency strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "health": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific vitality/wellness tendency strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "future": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific future tendency strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "strengths": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific strength strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      },
      "challenges": {
        "primary_signals": <array of signal_ids>,
        "key_traits": <array of 2-4 specific challenge strings>,
        "interpretation_basis": <string>,
        "strength": <"weak"|"moderate"|"strong"|"very_strong">
      }
    }
  }
}`;
}

// ── Stage B: Personalized reading generated FROM the Palm Intelligence Profile ─
// CRITICAL: Stage B reads from palm_intelligence_profile, NOT from raw features.
// This ensures:
//   1. Two different palms produce demonstrably different readings.
//   2. The reading is grounded in actual palm signals, not generic AI text.
//   3. The same palm always produces the same underlying interpretation.
function buildStageBPrompt(
  stageAResult: any,
  language: string,
  isPremium: boolean
): string {
  // Extract the structured profile — this is what drives the reading
  const profile = stageAResult.palm_intelligence_profile || {};
  const signals = profile.signals || [];
  const lifeAreas = profile.life_area_interpretations || {};

  // Build a concise profile summary for the prompt
  // Only include signals with confidence >= 0.4 and visible features
  const meaningfulSignals = signals
    .filter((s: any) => s.confidence >= 0.4)
    .map((s: any) => `• [${s.source_feature}] ${s.signal}: ${s.interpretation} (life areas: ${(s.life_areas || []).join(", ")}, confidence: ${Math.round(s.confidence * 100)}%)`)
    .join("\n");

  const profileSummary = `
PALM INTELLIGENCE PROFILE (${signals.length} signals identified, overall confidence: ${Math.round((profile.overall_confidence || 0.7) * 100)}%):

MEANINGFUL SIGNALS:
${meaningfulSignals || "No high-confidence signals identified — use conservative interpretations."}

LIFE AREA INTERPRETATIONS:
${Object.entries(lifeAreas).map(([area, data]: [string, any]) => {
  const traits = (data.key_traits || []).join(", ");
  const basis = data.interpretation_basis || "";
  return `• ${area.toUpperCase()} [${data.strength || "moderate"}]: ${traits}${basis ? ` (basis: ${basis})` : ""}`;
}).join("\n")}
`.trim();

  // Language instruction
  let langInstruction: string;
  if (language === "hi") {
    langInstruction = `LANGUAGE REQUIREMENT (CRITICAL):
- The user has selected HINDI as their language.
- Every "content_hi", "title_hi", "summary_hi", "key_traits_hi", "daily_insight_hi", "confidence_note_hi" field MUST be written in natural, fluent Hindi (Devanagari script).
- The Hindi text must be warm, culturally appropriate, and natural — NOT a word-for-word machine translation.
- Every "content_en", "title_en", "summary_en", "key_traits_en", "daily_insight_en", "confidence_note_en" field must be written in English.
- Both language versions must convey the SAME underlying interpretation — only the language changes, not the meaning.`;
  } else if (language === "hi-Latn") {
    langInstruction = `LANGUAGE REQUIREMENT (CRITICAL):
- The user has selected HINGLISH as their language.
- Hinglish means natural conversational Indian Hindi written primarily in Roman/Latin script, with English words retained naturally where they fit.
- Example Hinglish style: "Aapke palm mein independent decisions lene ki strong tendency dikhai deti hai. Career mein aap apne terms par kaam karna prefer karte hain."
- Every "content_hi", "title_hi", "summary_hi", "key_traits_hi", "daily_insight_hi", "confidence_note_hi" field MUST be written in natural Hinglish (Roman script, conversational Indian Hindi + English blend).
- Every "content_en", "title_en", "summary_en", "key_traits_en", "daily_insight_en", "confidence_note_en" field must be written in English.
- Both language versions must convey the SAME underlying interpretation — only the language changes, not the meaning.
- Hinglish must feel natural and conversational, not like a transliteration of formal Hindi.`;
  } else {
    langInstruction = `LANGUAGE REQUIREMENT (CRITICAL):
- The user has selected ENGLISH as their language.
- Every "content_en", "title_en", "summary_en", "key_traits_en", "daily_insight_en", "confidence_note_en" field MUST be written in natural, fluent English.
- Every "content_hi", "title_hi", "summary_hi", "key_traits_hi", "daily_insight_hi", "confidence_note_hi" field MUST be written in natural Hindi (Devanagari script).
- Both language versions must convey the SAME underlying interpretation — only the language changes, not the meaning.`;
  }

  // FINAL FREE / PREMIUM STRUCTURE (mirrors PremiumFeatures in the Flutter app).
  // FREE: overall analysis, palm lines, personality, love_relationships,
  //       health, life_path, basic strengths, today's insight, palm profile.
  // PREMIUM: wealth, career, future_tendencies, palm marks, detailed report,
  //          deep predictions, detailed strengths, remedies, advanced analysis.
  const premiumNote = isPremium
    ? "Generate COMPLETE detailed interpretations for all sections. Each content field should be 5-7 sentences with specific references to the palm signals identified above."
    : "Generate FULL rich interpretations for personality, love_relationships, health and life_path — these are FREE sections and must always contain real, deeply personal content. For career, wealth and future_tendencies: provide a brief 1-sentence teaser only.";

  return `You are HastVeda's palm reading narrative engine.

CRITICAL INSTRUCTION — THE MOST IMPORTANT RULE:
You are generating a PERSONALIZED reading from a structured Palm Intelligence Profile.
The customer does NOT want to be told what their palm looks like.
They want to know what these patterns mean in their ACTUAL LIFE — their current situations, emotions, relationships, decisions, career concerns, financial worries, personal tendencies, challenges, and opportunities.

DO NOT write sentences like:
- "Your Head Line is sloping."
- "Your Life Line is long and curved."
- "Your Heart Line is continuous."

INSTEAD, translate those signals into relatable life observations like:
- "You may currently be weighing several possibilities at once, which can make it difficult to commit to one direction. You may know more clearly what you want than you are allowing yourself to believe, but you appear to be looking for greater certainty before taking the next step."
- "There is a steady, resilient quality to how you approach life's demands. Even when circumstances become difficult, you tend to find a way through — though you may not always give yourself credit for this."
- "Your emotional life runs deeper than most people around you realize. You feel things strongly, but you have learned to be selective about who you allow to see that depth."

The desired customer reaction is: "YES — THIS IS WHAT IS GOING ON WITH ME."

Every sentence must be grounded in the specific signals identified in the Palm Intelligence Profile below.
Two different profiles MUST produce demonstrably different readings.
Do NOT write generic palmistry paragraphs. Every sentence should be traceable to a specific signal.

${langInstruction}

${premiumNote}

SAFETY RULES (MANDATORY):
- Never claim to predict death, disease, exact lifespan, pregnancy, fertility, criminal behavior, guaranteed financial returns, or legal outcomes.
- Use language like "may suggest", "can indicate", "your reading suggests", "there is a tendency toward".
- This is entertainment/wellness content, not scientific fact.
- Do not generate fear-based predictions.
- Only interpret features that appear in the Palm Intelligence Profile below.

${profileSummary}

Based on the Palm Intelligence Profile above, generate a personalized reading narrative.
Palmistry terminology may be used SPARINGLY as supporting context, but must NOT dominate the reading.

DEPTH REQUIREMENTS FOR EACH SECTION:

summary_en / summary_hi:
- 8-12 meaningful sentences. This is the OVERALL PERSONAL READING.
- Cover: who this person appears to be right now, what they may currently be experiencing, their core emotional and mental tendencies, a key strength, a current challenge or tension, and what their palm patterns suggest about their present life situation.
- Make the reader feel: "This is specifically about me."
- Do NOT start with palm line descriptions. Start with the person's life situation.

head_line_summary_en / head_line_summary_hi:
- 3-5 meaningful sentences about the HEAD LINE — but framed as what this means for the person's thinking, decision-making, mental approach, and current mental/intellectual situation.
- Example: "You tend to think through decisions carefully, sometimes to the point where the thinking itself becomes the obstacle. There may be a situation in your life right now where you already know what you want to do, but you are still searching for more certainty before committing."
- Both English and Hindi/Hinglish versions are REQUIRED.

heart_line_summary_en / heart_line_summary_hi:
- 3-5 meaningful sentences about the HEART LINE — framed as what this means for the person's emotional life, relationships, and how they experience love and connection.
- Example: "Your emotional responses tend to be genuine and deep, even when you present a composed exterior. In relationships, you may give more than you receive, not because you are unaware of this, but because connection matters more to you than keeping score."
- Both versions REQUIRED.

life_line_summary_en / life_line_summary_hi:
- 3-5 meaningful sentences about the LIFE LINE — framed as what this means for the person's vitality, resilience, physical energy, and how they handle life's demands.
- Example: "There is a consistent, steady energy in how you approach life's demands. You may not always feel this yourself — especially during periods of stress — but your capacity to recover and continue tends to be stronger than average."
- Both versions REQUIRED.

personality (FREE — MUST be rich and personal):
- 5-7 meaningful sentences. Cover: core character tendencies, thinking style, how this person approaches decisions and challenges, their emotional expression style, a key personal strength, and one area where they may be holding themselves back or experiencing friction.
- All grounded in the profile signals. Make it feel like a personal consultation, not a horoscope.

love_relationships (FREE — MUST be rich and personal):
- 5-7 meaningful sentences. Cover: how this person experiences emotional connection, what they seek in relationships, how they express affection, what they find difficult in relationships, and what their current relationship situation may look like based on the signals.
- All grounded in heart line and relationship signals. Avoid generic "you are loving and caring" filler.

health (FREE — MUST be substantive):
- 4-5 meaningful sentences. Cover: vitality and energy patterns, how this person handles physical and mental stress, resilience indicators, and any wellness tendencies worth noting.
- Grounded in life line and health signals. Do NOT make medical claims.

life_path (FREE — MUST be substantive):
- 4-5 meaningful sentences. Cover: the direction this person appears to be moving in life, their decision-making approach, how they handle change and uncertainty, and what their palm patterns suggest about their sense of purpose or direction.
- Grounded in head line and fate line signals.

daily_insight_en / daily_insight_hi (FREE — MUST NOT be blank):
- 5-7 meaningful sentences PLUS a short practical guidance point.
- This should describe something relevant to the person's current situation or day.
- It should create the feeling: "This is relevant to me right now."
- It may discuss: a decision the person may be delaying, relationship uncertainty, emotional pressure, a career or business direction, financial caution, an opportunity requiring attention, or a recurring personal pattern.
- Structure: (1-2 sentences) What your palm signals suggest about your current energy or focus. (2-3 sentences) A specific tendency, situation, or pattern that may be active right now. (1-2 sentences) How this may show up in your interactions or decisions today. (1 sentence) A personal guidance point: one concrete, actionable suggestion based on your palm profile.
- Do NOT make this a generic motivational quote. It must be grounded in the profile signals.
- BOTH daily_insight_en AND daily_insight_hi are REQUIRED and must not be empty.

key_traits_en / key_traits_hi:
- 3-5 short trait strings, each derived from a specific palm signal. These should be life-relevant descriptors, not palm terminology.
- Examples: "Analytical under pressure", "Deep emotional reserves", "Cautious decision-maker", "Resilient through change"

Return ONLY valid JSON (no markdown fences) matching this exact structure:
{
  "summary_en": <string, 8-12 sentence overall personal reading in English, grounded in profile signals, focused on life situations not palm descriptions>,
  "summary_hi": <string, 8-12 sentence overall personal reading in secondary language>,
  "overall_score": <integer 60-95, based on feature clarity and positive indicators>,
  "head_line_summary_en": <string, 3-5 sentence Head Line life-situation interpretation in English>,
  "head_line_summary_hi": <string, 3-5 sentence Head Line life-situation interpretation in secondary language — REQUIRED>,
  "heart_line_summary_en": <string, 3-5 sentence Heart Line life-situation interpretation in English>,
  "heart_line_summary_hi": <string, 3-5 sentence Heart Line life-situation interpretation in secondary language — REQUIRED>,
  "life_line_summary_en": <string, 3-5 sentence Life Line life-situation interpretation in English>,
  "life_line_summary_hi": <string, 3-5 sentence Life Line life-situation interpretation in secondary language — REQUIRED>,
  "personality": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string, 5-7 sentences in English — core character, thinking style, emotional expression, strengths, growth area, all grounded in profile signals>,
    "content_hi": <string, 5-7 sentences in secondary language — same depth as English>,
    "score": <integer 60-95>,
    "is_premium_locked": false
  },
  "love_relationships": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string, 5-7 sentences in English — emotional nature, relationship style, affection expression, relationship challenges, current relationship situation, all from heart line and relationship signals>,
    "content_hi": <string, 5-7 sentences in secondary language — same depth as English>,
    "score": <integer 60-95>,
    "is_premium_locked": false
  },
  "career": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string in English, 1-sentence teaser for free users or full 4-5 sentences for premium>,
    "content_hi": <string in secondary language>,
    "score": <integer 60-95>,
    "is_premium_locked": <boolean>
  },
  "wealth": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string in English, 1-sentence teaser for free users or full 4-5 sentences for premium>,
    "content_hi": <string in secondary language>,
    "score": <integer 60-95>,
    "is_premium_locked": <boolean>
  },
  "health": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string, 4-5 sentences in English — vitality patterns, stress handling, resilience, wellness tendencies, all from life line and health signals>,
    "content_hi": <string, 4-5 sentences in secondary language — same depth as English>,
    "score": <integer 60-95>,
    "is_premium_locked": false
  },
  "life_path": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string, 4-5 sentences in English — life direction, decision-making approach, handling change and uncertainty, sense of purpose, all from head line and fate line signals>,
    "content_hi": <string, 4-5 sentences in secondary language — same depth as English>,
    "score": <integer 60-95>,
    "is_premium_locked": false
  },
  "future_tendencies": {
    "title_en": <string in English>,
    "title_hi": <string in secondary language>,
    "content_en": <string in English, 1-sentence teaser for free users or full 4-5 sentences for premium>,
    "content_hi": <string in secondary language>,
    "score": <integer 60-95>,
    "is_premium_locked": <boolean>
  },
  "key_traits_en": <array of 3-5 short life-relevant trait strings in English, each derived from a specific palm signal>,
  "key_traits_hi": <array of 3-5 short trait strings in secondary language>,
  "daily_insight_en": <string, 5-7 sentences in English PLUS a practical guidance point. Grounded in profile signals. Describes something relevant to the person's current situation. NOT a generic motivational quote. MUST NOT be empty.>,
  "daily_insight_hi": <string, same structure as daily_insight_en but in secondary language — 5-7 sentences plus guidance point. MUST NOT be empty.>,
  "confidence_note_en": <string or null, shown if overall_confidence < 0.6, in English>,
  "confidence_note_hi": <string or null, in secondary language if confidence_note_en is not null>
}`;
}

// ── Main handler ──────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();
  let analysisId: string | undefined;
  // Hoisted so the outer catch can still write a failure row after an
  // unexpected throw — that path used to leave no diagnosable trace at all.
  const failCtx: {
    userId?: string;
    scanId?: string;
    handSide?: string;
    language?: string;
    imagePath?: string;
    appVersion?: string;
    platform?: string;
    deviceModel?: string;
  } = {};

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
      scan_id,
      image_path,
      hand_side = "right",
      language = "en",
      force_reanalysis = false,
      client_meta = {},
    } = body;

    // Device context, recorded on failures so a per-device capture problem is
    // visible in the failure log. Never required — old clients omit it.
    const clientMeta = {
      appVersion: typeof client_meta?.app_version === "string"
        ? client_meta.app_version.slice(0, 40)
        : undefined,
      platform: typeof client_meta?.platform === "string"
        ? client_meta.platform.slice(0, 40)
        : undefined,
      deviceModel: typeof client_meta?.device_model === "string"
        ? client_meta.device_model.slice(0, 80)
        : undefined,
    };

    failCtx.userId = userId;
    failCtx.scanId = scan_id;
    failCtx.handSide = hand_side;
    failCtx.language = language;
    failCtx.imagePath = image_path;
    failCtx.appVersion = clientMeta.appVersion;
    failCtx.platform = clientMeta.platform;
    failCtx.deviceModel = clientMeta.deviceModel;

    if (!scan_id) {
      return new Response(
        JSON.stringify({ error: "scan_id is required", code: "MISSING_SCAN_ID" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Verify scan belongs to user ─────────────────────────────────────────
    const { data: scan, error: scanError } = await userClient
      .from("palm_scans")
      .select("id, user_id, image_path, status")
      .eq("id", scan_id)
      .eq("user_id", userId)
      .maybeSingle();

    if (scanError || !scan) {
      return new Response(
        JSON.stringify({ error: "Scan not found", code: "SCAN_NOT_FOUND" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Idempotency: return existing completed analysis ─────────────────────
    if (!force_reanalysis) {
      const { data: existingAnalysis } = await userClient
        .from("palm_analysis")
        .select("*")
        .eq("scan_id", scan_id)
        .eq("user_id", userId)
        .eq("status", "completed")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existingAnalysis) {
        return new Response(
          JSON.stringify({
            success: true,
            analysis_id: existingAnalysis.id,
            status: "completed",
            cached: true,
            data: existingAnalysis,
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
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

    // ── Enforce free-tier scan quota ────────────────────────────────────────
    if (!isPremium) {
      const limit = await freeScanLimit(serviceClient);
      const used = await freeScansUsedThisMonth(serviceClient, userId, scan_id);

      if (used >= limit) {
        console.log("[palm-analysis] free scan limit reached", { used, limit });
        await writeSideEffect(
          serviceClient
            .from("palm_scans")
            .update({ status: "failed" })
            .eq("id", scan_id),
          "palm_scans->failed(quota)"
        );
        await logFailure(serviceClient, {
          userId,
          scanId: scan_id,
          handSide: hand_side,
          language,
          stage: "quota",
          failureCode: "FREE_LIMIT_REACHED",
          reason: `Free scan limit reached (${used}/${limit} this month)`,
          httpStatus: 403,
          appVersion: clientMeta.appVersion,
          platform: clientMeta.platform,
          deviceModel: clientMeta.deviceModel,
        });
        return new Response(
          JSON.stringify({
            error: "Free scan limit reached for this month",
            code: "FREE_LIMIT_REACHED",
            reason: "FREE_LIMIT_REACHED",
            limit,
            used,
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    // ── Create analysis record (processing) ─────────────────────────────────
    const { data: analysisRecord, error: createError } = await serviceClient
      .from("palm_analysis")
      .insert({
        scan_id,
        user_id: userId,
        status: "processing",
        ai_model: currentModel(),
        ai_provider: "google",
        analysis_version: "2.1",
      })
      .select()
      .single();

    if (createError || !analysisRecord) {
      console.error("[palm-analysis] create analysis record failed", {
        code: createError?.code,
        message: createError?.message,
        details: createError?.details,
        hint: createError?.hint
      });
      return new Response(
        JSON.stringify({ error: "Failed to create analysis record", code: "DB_ERROR" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    analysisId = analysisRecord.id;

    // ── Update scan status to processing ────────────────────────────────────
    await writeSideEffect(
      serviceClient
        .from("palm_scans")
        .update({ status: "processing", hand_type: hand_side })
        .eq("id", scan_id),
      "palm_scans->processing"
    );

    // ── Get image from storage ──────────────────────────────────────────────
    const imageScanPath = image_path || scan.image_path;
    if (!imageScanPath) {
      await writeAnalysis(
        serviceClient,
        analysisId!,
        { status: "failed", error_message: "No image path provided" },
        "no-image"
      );
      return new Response(
        JSON.stringify({ error: "No image available for analysis", code: "NO_IMAGE" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: imageData, error: downloadError } = await serviceClient.storage
      .from("palm-images")
      .download(imageScanPath);

    if (downloadError || !imageData) {
      console.error("[palm-analysis] storage download failed", {
        message: (downloadError as { message?: string })?.message,
      });
      await writeAnalysis(
        serviceClient,
        analysisId!,
        { status: "failed", error_message: "Failed to download image" },
        "image-download"
      );
      return new Response(
        JSON.stringify({ error: "Failed to retrieve palm image", code: "IMAGE_DOWNLOAD_FAILED" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const arrayBuffer = await imageData.arrayBuffer();
    const uint8Array = new Uint8Array(arrayBuffer);
    let binary = "";
    for (let i = 0; i < uint8Array.byteLength; i++) {
      binary += String.fromCharCode(uint8Array[i]);
    }
    const imageBase64 = btoa(binary);
    const imageMimeType = imageData.type || "image/jpeg";

    // ── STAGE A: Image validation + feature extraction + Palm Intelligence Profile ─
    let stageAResult: any;
    try {
      const stageAPrompt = buildStageAPrompt(hand_side);
      stageAResult = await callGeminiJson(
        "Stage A",
        stageAPrompt,
        imageBase64,
        imageMimeType,
        0.2,
        10000  // Increased for profile generation
      );
    } catch (e: any) {
      console.error("[palm-analysis] Stage A failed", { message: e?.message });
      await writeAnalysis(
        serviceClient,
        analysisId!,
        { status: "failed", error_message: `Stage A failed: ${e.message}` },
        "stage-a"
      );
      await writeSideEffect(
        serviceClient.from("palm_scans").update({ status: "failed" }).eq("id", scan_id),
        "palm_scans->failed"
      );
      const failA = classifyFailure(e?.message ?? "");
      await logFailure(serviceClient, {
        userId,
        scanId: scan_id,
        analysisId,
        handSide: hand_side,
        language,
        stage: "stage_a",
        failureCode: (failA.code || "STAGE_A_FAILED") as FailureCode,
        reason: failA.error || "Stage A feature extraction failed",
        httpStatus: failA.status,
        imagePath: image_path ?? scan.image_path,
        providerMessage: e?.message,
        appVersion: clientMeta.appVersion,
        platform: clientMeta.platform,
        deviceModel: clientMeta.deviceModel,
      });
      return new Response(
        JSON.stringify({
          error: failA.error || "Palm analysis failed. Please try again.",
          code: failA.code || "STAGE_A_FAILED",
          reason: failA.code || "STAGE_A_FAILED",
          details: e.message,
        }),
        {
          status: failA.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── Validate image quality ───────────────────────────────────────────────
    const imageQuality = stageAResult.image_quality || {};
    const qualityScore = imageQuality.score || 0;
    const palmDetected = imageQuality.palm_detected || false;
    const suitableForAnalysis = imageQuality.suitable_for_analysis || false;

    await writeSideEffect(
      serviceClient
        .from("palm_scans")
        .update({ quality_score: qualityScore * 100 })
        .eq("id", scan_id),
      "palm_scans->quality_score"
    );

    if (!palmDetected || !suitableForAnalysis || qualityScore < 0.35) {
      // Resolve ONE specific reason so the user gets a correction tip, not
      // "Scan Failed". The gate itself is unchanged — same thresholds.
      const qf = resolveQualityFailure(imageQuality);

      await writeAnalysis(
        serviceClient,
        analysisId!,
        {
          status: "failed",
          error_message: `Image quality insufficient: ${qf.code}`,
          confidence_score: qualityScore * 100,
        },
        "low-quality"
      );
      await writeSideEffect(
        serviceClient.from("palm_scans").update({ status: "failed" }).eq("id", scan_id),
        "palm_scans->failed"
      );

      await logFailure(serviceClient, {
        userId,
        scanId: scan_id,
        analysisId,
        handSide: hand_side,
        language,
        stage: "quality_gate",
        failureCode: qf.code,
        reason: qf.reason,
        qualityScore,
        palmDetected,
        suitableForAnalysis,
        qualityIssues: imageQuality.issues || [],
        httpStatus: 422,
        imagePath: image_path ?? scan.image_path,
        appVersion: clientMeta.appVersion,
        platform: clientMeta.platform,
        deviceModel: clientMeta.deviceModel,
      });

      return new Response(
        JSON.stringify({
          error: "image_quality_insufficient",
          code: "LOW_QUALITY_IMAGE",
          // The specific reason the client renders its message from.
          reason: qf.code,
          reason_detail: qf.reason,
          quality_score: qualityScore,
          issues: imageQuality.issues || [],
          palm_detected: palmDetected,
          suitable_for_analysis: suitableForAnalysis,
        }),
        { status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Save palm features ───────────────────────────────────────────────────
    const palmFeaturesData = stageAResult.palm_features || {};
    const { data: featuresRecord, error: featuresError } = await serviceClient
      .from("palm_features")
      .insert({
        scan_id,
        user_id: userId,
        life_line: palmFeaturesData.life_line || {},
        heart_line: palmFeaturesData.heart_line || {},
        head_line: palmFeaturesData.head_line || {},
        fate_line: palmFeaturesData.fate_line || {},
        sun_line: palmFeaturesData.sun_line || {},
        mercury_line: palmFeaturesData.mercury_line || {},
        mounts: stageAResult.mounts || {},
        special_marks: stageAResult.special_marks || [],
        raw_features: stageAResult,
      })
      .select()
      .single();

    if (featuresError) {
      console.error("[palm-analysis] palm_features insert FAILED", {
        code: featuresError.code,
        message: featuresError.message,
      });
    }

    // ── Save Palm Intelligence Profile ───────────────────────────────────────
    // This is the stable structured intermediate representation.
    // Stored separately so it can be reused by future features (Ask HastVeda, etc.)
    const intelligenceProfile = stageAResult.palm_intelligence_profile || {};
    const lifeAreaInterps = intelligenceProfile.life_area_interpretations || {};
    const signals = intelligenceProfile.signals || [];

    const { data: profileRecord, error: profileError } = await serviceClient
      .from("palm_intelligence_profiles")
      .upsert(
        {
          scan_id,
          user_id: userId,
          analysis_id: analysisId,
          life_line_signals: signals.filter((s: any) => s.source_feature === "life_line"),
          head_line_signals: signals.filter((s: any) => s.source_feature === "head_line"),
          heart_line_signals: signals.filter((s: any) => s.source_feature === "heart_line"),
          fate_line_signals: signals.filter((s: any) => s.source_feature === "fate_line"),
          sun_line_signals: signals.filter((s: any) => s.source_feature === "sun_line"),
          mercury_line_signals: signals.filter((s: any) => s.source_feature === "mercury_line"),
          mount_signals: signals.filter((s: any) => s.source_feature?.startsWith("mount")),
          special_mark_signals: signals.filter((s: any) => s.source_feature === "special_marks"),
          palm_shape_signals: signals.filter((s: any) => s.source_feature === "palm_shape"),
          life_area_interpretations: lifeAreaInterps,
          overall_confidence: intelligenceProfile.overall_confidence || stageAResult.overall_confidence || 0.7,
          signal_count: intelligenceProfile.signal_count || signals.length,
          profile_version: intelligenceProfile.profile_version || "1.0",
          raw_stage_a: stageAResult,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "scan_id" }
      )
      .select()
      .single();

    if (profileError) {
      // Non-fatal: log but continue — the reading can still be generated
      console.error("[palm-analysis] palm_intelligence_profiles upsert FAILED", {
        code: profileError.code,
        message: profileError.message,
      });
    } else {
      console.log("[palm-analysis] Palm Intelligence Profile saved", {
        profile_id: profileRecord?.id,
        signal_count: signals.length,
      });
    }

    // ── STAGE B: Personalized reading from Palm Intelligence Profile ─────────
    // Stage B receives the full stageAResult (which includes palm_intelligence_profile)
    // and generates the reading narrative grounded in the structured profile.
    let stageBResult: any;
    try {
      const stageBPrompt = buildStageBPrompt(stageAResult, language, isPremium);
      stageBResult = await callGeminiJson(
        "Stage B",
        stageBPrompt,
        undefined,
        undefined,
        0.6,
        12000  // Increased token budget for longer readings
      );
    } catch (e: any) {
      console.error("[palm-analysis] Stage B failed", { message: e?.message });
      await writeAnalysis(
        serviceClient,
        analysisId!,
        { status: "failed", error_message: `Stage B failed: ${e.message}` },
        "stage-b"
      );
      const failB = classifyFailure(e?.message ?? "");
      await logFailure(serviceClient, {
        userId,
        scanId: scan_id,
        analysisId,
        handSide: hand_side,
        language,
        stage: "stage_b",
        failureCode: (failB.code || "STAGE_B_FAILED") as FailureCode,
        reason: failB.error || "Stage B reading generation failed",
        // The image passed the gate here — record that so this is never
        // mistaken for a capture problem.
        qualityScore,
        palmDetected,
        suitableForAnalysis,
        httpStatus: failB.status,
        imagePath: image_path ?? scan.image_path,
        providerMessage: e?.message,
        appVersion: clientMeta.appVersion,
        platform: clientMeta.platform,
        deviceModel: clientMeta.deviceModel,
      });
      return new Response(
        JSON.stringify({
          error: failB.error || "Reading generation failed. Please try again.",
          code: failB.code || "STAGE_B_FAILED",
          reason: failB.code || "STAGE_B_FAILED",
          details: e?.message,
        }),
        {
          status: failB.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const processingTimeMs = Date.now() - startTime;
    const overallConfidence = stageAResult.overall_confidence || 0.7;
    const confidenceScore100 = Math.round(overallConfidence * 100);

    // ── Save complete analysis ───────────────────────────────────────────────
    const analysisUpdates = {
      features_id: featuresRecord?.id || null,
      status: "completed",
      life_analysis: {
        features: palmFeaturesData.life_line || {},
        interpretation_en: stageBResult.life_path?.content_en || "",
        interpretation_hi: stageBResult.life_path?.content_hi || "",
        summary_en: stageBResult.life_line_summary_en || "",
        summary_hi: stageBResult.life_line_summary_hi || "",
        score: stageBResult.life_path?.score || 75,
        is_premium_locked: false, // policy-driven, not model-driven
      },
      love_analysis: {
        features: palmFeaturesData.heart_line || {},
        interpretation_en: stageBResult.love_relationships?.content_en || "",
        interpretation_hi: stageBResult.love_relationships?.content_hi || "",
        summary_en: stageBResult.heart_line_summary_en || "",
        summary_hi: stageBResult.heart_line_summary_hi || "",
        score: stageBResult.love_relationships?.score || 75,
        is_premium_locked: false, // policy-driven, not model-driven
      },
      career_analysis: {
        features: palmFeaturesData.fate_line || {},
        interpretation_en: stageBResult.career?.content_en || "",
        interpretation_hi: stageBResult.career?.content_hi || "",
        score: stageBResult.career?.score || 75,
        is_premium_locked: !isPremium, // policy-driven, not model-driven
      },
      health_analysis: {
        features: palmFeaturesData.life_line || {},
        interpretation_en: stageBResult.health?.content_en || "",
        interpretation_hi: stageBResult.health?.content_hi || "",
        score: stageBResult.health?.score || 75,
        is_premium_locked: false, // policy-driven, not model-driven
      },
      wealth_analysis: {
        features: palmFeaturesData.mercury_line || {},
        interpretation_en: stageBResult.wealth?.content_en || "",
        interpretation_hi: stageBResult.wealth?.content_hi || "",
        score: stageBResult.wealth?.score || 75,
        is_premium_locked: !isPremium, // policy-driven, not model-driven
      },
      personality_analysis: {
        features: stageAResult.palm_shape || {},
        interpretation_en: stageBResult.personality?.content_en || "",
        interpretation_hi: stageBResult.personality?.content_hi || "",
        summary_en: stageBResult.head_line_summary_en || "",
        summary_hi: stageBResult.head_line_summary_hi || "",
        score: stageBResult.personality?.score || 75,
        is_premium_locked: false, // policy-driven, not model-driven
        key_traits_en: stageBResult.key_traits_en || [],
        key_traits_hi: stageBResult.key_traits_hi || [],
        future_tendencies_en: stageBResult.future_tendencies?.content_en || "",
        future_tendencies_hi: stageBResult.future_tendencies?.content_hi || "",
        future_tendencies_locked: !isPremium, // policy-driven, not model-driven
        future_tendencies_score: stageBResult.future_tendencies?.score || 75,
      },
      summary: stageBResult.summary_en || "",
      summary_hi: stageBResult.summary_hi || "",
      overall_score: stageBResult.overall_score || 75,
      is_premium: isPremium,
      confidence_score: confidenceScore100,
      processing_time_ms: processingTimeMs,
      // Store daily insight directly on the analysis record so it can be
      // retrieved when loading from reading history (not just from predictions table)
      daily_insight_en: stageBResult.daily_insight_en || "",
      daily_insight_hi: stageBResult.daily_insight_hi || "",
      // Store hand_side for display in reading history
      hand_side,
    };

    const persisted = await writeAnalysis(
      serviceClient,
      analysisId!,
      analysisUpdates,
      "completed"
    );
    if (!persisted) {
      await logFailure(serviceClient, {
        userId,
        scanId: scan_id,
        analysisId,
        handSide: hand_side,
        language,
        stage: "persist",
        failureCode: "PERSIST_FAILED",
        reason: "Reading was generated but could not be saved",
        qualityScore,
        palmDetected,
        suitableForAnalysis,
        httpStatus: 500,
        imagePath: image_path ?? scan.image_path,
        appVersion: clientMeta.appVersion,
        platform: clientMeta.platform,
        deviceModel: clientMeta.deviceModel,
      });
      return new Response(
        JSON.stringify({
          error: "Failed to save your reading. Please try again.",
          code: "PERSIST_FAILED",
          reason: "PERSIST_FAILED",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Update scan status ───────────────────────────────────────────────────
    await writeSideEffect(
      serviceClient.from("palm_scans").update({ status: "completed" }).eq("id", scan_id),
      "palm_scans->completed"
    );

    // ── Create reading history entry ─────────────────────────────────────────
    const readingTitle = language === "hi"
      ? "हस्तरेखा विश्लेषण"
      : language === "hi-Latn"
      ? "Hastarekha Analysis"
      : "Palm Reading";

    await writeSideEffect(
      serviceClient.from("reading_history").insert({
        user_id: userId,
        scan_id,
        analysis_id: analysisId,
        reading_type: "single",
        title: readingTitle,
        summary: stageBResult.summary_en || "Your palm reading is ready.",
        is_complete: true,
        is_premium: isPremium,
        completed_at: new Date().toISOString(),
      }),
      "reading_history insert"
    );

    // ── Create daily prediction ──────────────────────────────────────────────
    if (stageBResult.daily_insight_en) {
      const predictionTitle = language === "hi"
        ? "आज की अंतर्दृष्टि"
        : language === "hi-Latn"
        ? "Aaj ki Insight"
        : "Today's Insight";

      await writeSideEffect(
        serviceClient.from("predictions").insert({
          user_id: userId,
          analysis_id: analysisId,
          prediction_type: "palm_based",
          time_period: "daily",
          title: predictionTitle,
          content: stageBResult.daily_insight_en,
          short_summary: stageBResult.daily_insight_en,
          is_premium: false,
          is_featured: true,
          metadata: { content_hi: stageBResult.daily_insight_hi || "" },
        }),
        "predictions insert"
      );
    }

    // ── Log AI usage ─────────────────────────────────────────────────────────
    await writeSideEffect(
      serviceClient.from("ai_usage").insert({
        user_id: userId,
        scan_id,
        analysis_id: analysisId,
        ai_provider: "google",
        ai_model: currentModel(),
        operation_type: "palm_analysis_v2",
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        latency_ms: processingTimeMs,
        success: true,
        metadata: {
          language,
          signal_count: signals.length,
          profile_version: intelligenceProfile.profile_version || "1.0",
        },
      }),
      "ai_usage insert"
    );

    // ── Return result ────────────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        analysis_id: analysisId,
        status: "completed",
        cached: false,
        data: {
          ...analysisUpdates,
          id: analysisId,
          scan_id,
          user_id: userId,
          hand_side,
          image_quality: stageAResult.image_quality,
          palm_features: stageAResult.palm_features,
          palm_shape: stageAResult.palm_shape,
          mounts: stageAResult.mounts,
          special_marks: stageAResult.special_marks,
          summary_en: stageBResult.summary_en,
          summary_hi: stageBResult.summary_hi,
          overall_score: stageBResult.overall_score || 75,
          key_traits_en: stageBResult.key_traits_en || [],
          key_traits_hi: stageBResult.key_traits_hi || [],
          daily_insight_en: stageBResult.daily_insight_en || "",
          daily_insight_hi: stageBResult.daily_insight_hi || "",
          confidence_note_en: stageBResult.confidence_note_en || null,
          confidence_note_hi: stageBResult.confidence_note_hi || null,
          is_premium: isPremium,
          processing_time_ms: processingTimeMs,
          // Expose Stage B categories directly for client convenience
          personality: stageBResult.personality || {},
          love_relationships: stageBResult.love_relationships || {},
          career: stageBResult.career || {},
          wealth: stageBResult.wealth || {},
          health: stageBResult.health || {},
          life_path: stageBResult.life_path || {},
          future_tendencies: stageBResult.future_tendencies || {},
          // Line summaries for palm_line_screen display
          head_line_summary_en: stageBResult.head_line_summary_en || "",
          head_line_summary_hi: stageBResult.head_line_summary_hi || "",
          heart_line_summary_en: stageBResult.heart_line_summary_en || "",
          heart_line_summary_hi: stageBResult.heart_line_summary_hi || "",
          life_line_summary_en: stageBResult.life_line_summary_en || "",
          life_line_summary_hi: stageBResult.life_line_summary_hi || "",
          // Expose Palm Intelligence Profile for client use
          palm_intelligence_profile: {
            profile_id: profileRecord?.id || null,
            signal_count: signals.length,
            overall_confidence: intelligenceProfile.overall_confidence || overallConfidence,
            profile_version: intelligenceProfile.profile_version || "1.0",
          },
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Palm analysis error:", {
      type: error?.constructor?.name ?? typeof error,
      message: error instanceof Error ? error.message : String(error),
    });
    const safeMessage = error instanceof Error ? error.message : String(error);
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      const serviceClient = createClient(supabaseUrl, supabaseServiceKey);
      if (analysisId) {
        await writeAnalysis(
          serviceClient,
          analysisId,
          { status: "failed", error_message: safeMessage },
          "outer-catch"
        );
      }
      // Logged even without an analysisId — a throw before the analysis row
      // exists is exactly the case that was previously invisible.
      await logFailure(serviceClient, {
        userId: failCtx.userId,
        scanId: failCtx.scanId,
        analysisId,
        handSide: failCtx.handSide,
        language: failCtx.language,
        stage: "unknown",
        failureCode: "UNKNOWN",
        reason: "Unexpected server error during palm analysis",
        httpStatus: 500,
        imagePath: failCtx.imagePath,
        providerMessage: safeMessage,
        appVersion: failCtx.appVersion,
        platform: failCtx.platform,
        deviceModel: failCtx.deviceModel,
      });
    } catch (updateErr: any) {
      console.error("[palm-analysis] outer-catch handling threw", {
        message: updateErr?.message,
      });
    }
    return new Response(
      JSON.stringify({
        error: "An unexpected error occurred. Please try again.",
        code: "INTERNAL_ERROR",
        reason: "UNKNOWN",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
