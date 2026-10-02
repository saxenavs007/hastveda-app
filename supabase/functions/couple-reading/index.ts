// HastVeda Couple Reading Edge Function
// Pipeline:
//   1. Person 1 palm image → Gemini Stage A (feature extraction) + Stage B (interpretation)
//   2. Person 2 palm image → Gemini Stage A (feature extraction) + Stage B (interpretation)
//   3. Compatibility Engine → Gemini Stage C (couple interpretation from both structured analyses)
//   4. Save to couple_readings + reading_history
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
  // Models sometimes wrap the object in a sentence of prose. Keeping only the
  // outermost braces stops a preamble or trailing note from breaking the parse.
  const first = text.indexOf("{");
  const last = text.lastIndexOf("}");
  if (first !== -1 && last > first) text = text.slice(first, last + 1);
  return text;
}

// Gemini occasionally emits JSON that will not parse — an unescaped quote inside
// a string, an unterminated array, a placeholder echoed from the prompt. The
// response is re-sampled rather than patched: a fresh generation is far likelier
// to be well-formed than a regex repair is to be correct.
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
      // Log only a short window around the syntax defect — enough to identify
      // the malformation without dumping the user's reading into the logs.
      const pos = Number(/position (\d+)/.exec(lastParseError)?.[1] ?? -1);
      console.error(
        `[couple-reading] ${label} returned unparseable JSON (attempt ${attempt}/${MAX_JSON_ATTEMPTS})`,
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
// Google restricts retired models to keys that already used them, so a key that
// worked yesterday can start returning 404 NOT_FOUND ("no longer available to
// new users"). Set GEMINI_MODEL to pin a model; otherwise we walk the flash tier
// until one answers, then cache that choice for the life of the isolate.
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

// Total wall-clock a single logical call may spend across retries and model
// fallbacks. Kept under the platform's function timeout so the request ends with
// a useful error instead of being killed mid-flight.
const CALL_BUDGET_MS = 110_000;
// Not worth starting another attempt with less than this left.
const MIN_ATTEMPT_MS = 12_000;

// Gemini 3.x models think before answering. For a fixed-schema extraction that
// spends latency and output tokens without improving the result — a thinking
// overrun is what truncated the JSON and blew the request timeout. Models that
// reject the field get one retry without it rather than a failed request.
let thinkingSupported = true;

let activeModel: string | null = null;

// The model that produced the current results — recorded on the row as ai_model.
function currentModel(): string {
  return activeModel ?? GEMINI_MODELS[0];
}

// A retired/unknown model 404s; an unsupported one 400s with "not found".
// Both mean "try the next model", unlike auth (403) errors.
function isModelUnavailable(status: number, body: string): boolean {
  return status === 404 || (status === 400 && /not found|not supported/i.test(body));
}

// Overload (503) and rate limiting (429) are temporary and say nothing about the
// model itself — Gemini returns these under load. Retry the same model briefly
// before falling through to the next one.
const TRANSIENT_STATUSES = new Set([429, 500, 502, 503, 504]);
const MAX_ATTEMPTS_PER_MODEL = 3;

function backoffMs(attempt: number): number {
  return 700 * Math.pow(2, attempt); // 700ms, 1.4s
}

const delay = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Try `activeModel` first once known, then any remaining candidates.
function modelCandidates(): string[] {
  if (!activeModel) return GEMINI_MODELS;
  return [activeModel, ...GEMINI_MODELS.filter((m) => m !== activeModel)];
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
    parts.push({ inlineData: { mimeType: imageMimeType, data: imageBase64 } });
  }
  parts.push({ text: prompt });

  // Rebuilt per attempt because the thinking field may be dropped mid-call.
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

  // The platform caps total function runtime, and this helper may make several
  // attempts across several models. A shared deadline means we fail with a clear
  // "busy" message instead of being killed mid-request.
  const startedAt = Date.now();
  const remainingMs = () => CALL_BUDGET_MS - (Date.now() - startedAt);

  for (const model of modelCandidates()) {
    let transientRetries = 0;

    // Retry this model while the API reports a temporary condition, then move on.
    while (true) {
      if (remainingMs() < MIN_ATTEMPT_MS) {
        console.warn(`[couple-reading] time budget exhausted before trying ${model}`);
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

          // This model version does not accept the thinking field — drop it and
          // retry the same model rather than treating it as unavailable.
          if (
            res.status === 400 &&
            thinkingSupported &&
            /thinking/i.test(errText)
          ) {
            console.warn(`[couple-reading] ${model} rejected thinkingLevel, retrying without it`);
            thinkingSupported = false;
            continue;
          }

          if (isModelUnavailable(res.status, errText)) {
            // Retired, or not enabled for this key — try the next model.
            console.warn(`[couple-reading] model ${model} unavailable (${res.status}), trying next`);
            break;
          }

          if (
            TRANSIENT_STATUSES.has(res.status) &&
            transientRetries < MAX_ATTEMPTS_PER_MODEL - 1
          ) {
            const wait = backoffMs(transientRetries);
            transientRetries++;
            console.warn(
              `[couple-reading] model ${model} transient ${res.status}, retry ${transientRetries}/${MAX_ATTEMPTS_PER_MODEL - 1} in ${wait}ms`
            );
            await delay(wait);
            continue;
          }

          if (TRANSIENT_STATUSES.has(res.status)) {
            // Out of retries here — another model may still have capacity.
            console.warn(`[couple-reading] model ${model} still ${res.status} after retries, trying next`);
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
          // Usually MAX_TOKENS (the model spent its budget before emitting text)
          // or SAFETY. Naming the reason turns a silent retry loop into a fix.
          throw new Error(`Empty response from Gemini (${model}, finishReason=${finishReason})`);
        }

        // A MAX_TOKENS stop yields syntactically broken JSON. Left alone it
        // surfaces downstream as a bare "Unexpected end of JSON input" from
        // JSON.parse, which says nothing about the real cause.
        if (finishReason === "MAX_TOKENS") {
          throw new Error(
            `Gemini response truncated (${model}, maxOutputTokens=${maxTokens}) — raise the token budget`
          );
        }

        if (activeModel !== model) {
          console.log(`[couple-reading] using Gemini model ${model}`);
          activeModel = model;
        }
        return text;
      } catch (e: any) {
        // The attempt timeout aborts the fetch. Treat that like transient
        // capacity trouble so the remaining models still get a chance, rather
        // than failing the whole request on one slow model.
        const aborted =
          e?.name === "AbortError" || /abort/i.test(e?.message ?? "");
        if (aborted) {
          lastError = `Gemini request to ${model} timed out after ${attemptMs}ms`;
          console.warn(`[couple-reading] ${lastError}, trying next model`);
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

// ── Stage A: Image validation + feature extraction (same as palm-analysis) ────
function buildStageAPrompt(handSide: string): string {
  return `You are an expert palm analysis AI for HastVeda, a palmistry wellness application.

Analyze the provided palm image and return ONLY valid JSON matching this exact schema. Do not include any text outside the JSON. Do not use markdown code fences.

IMPORTANT SAFETY RULES:
- Never make claims about death, disease, lifespan, medical conditions, pregnancy, fertility, criminal behavior, or guaranteed financial/legal outcomes.
- Use language like "may suggest", "traditionally associated with", "can indicate".
- If a feature is not clearly visible, set visible:false and confidence below 0.5.
- Only report features that are actually observable in the image.

Hand side: ${handSide}

Return this exact JSON structure:
{
  "image_quality": {
    "score": <0.0-1.0 float>,
    "palm_detected": <boolean>,
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
  "overall_confidence": <0.0-1.0 float>
}`;
}

// ── Stage B: Individual interpretation (same as palm-analysis) ────────────────
function buildStageBPrompt(features: any, language: string): string {
  const featuresJson = JSON.stringify(features, null, 2);
  const langInstruction =
    language === "hi"
      ? "Generate ALL text content in Hindi (Devanagari script). Use respectful, warm language."
      : "Generate ALL text content in English. Use warm, encouraging language.";

  return `You are HastVeda's palm reading interpretation engine.

${langInstruction}

SAFETY RULES (MANDATORY):
- Never claim to predict death, disease, exact lifespan, pregnancy, fertility, criminal behavior, guaranteed financial returns, or legal outcomes.
- Use language like "may suggest", "traditionally associated with", "can indicate", "your reading suggests".
- This is entertainment/wellness content, not scientific fact.
- Only interpret features that are marked as visible:true.

Based on these validated palm observations, generate a concise individual reading summary for use in couple compatibility analysis:
${featuresJson}

Return ONLY valid JSON (no markdown fences) matching this exact structure:
{
  "summary_en": <string, 2-3 sentence overall summary in English>,
  "summary_hi": <string, 2-3 sentence overall summary in Hindi>,
  "overall_score": <integer 60-95>,
  "personality": {
    "content_en": <string, 2-3 sentences about personality traits>,
    "content_hi": <string, 2-3 sentences in Hindi>,
    "score": <integer 60-95>
  },
  "love_relationships": {
    "content_en": <string, 2-3 sentences about emotional/relationship tendencies>,
    "content_hi": <string, 2-3 sentences in Hindi>,
    "score": <integer 60-95>
  },
  "communication_style": {
    "content_en": <string, 1-2 sentences about communication tendencies>,
    "content_hi": <string, 1-2 sentences in Hindi>
  },
  "emotional_nature": {
    "content_en": <string, 1-2 sentences about emotional nature>,
    "content_hi": <string, 1-2 sentences in Hindi>
  },
  "key_traits_en": <array of 3-5 short trait strings in English>,
  "key_traits_hi": <array of 3-5 short trait strings in Hindi>
}`;
}

// ── Stage C: Couple compatibility interpretation ───────────────────────────────
function buildStageCPrompt(
  person1Name: string,
  person2Name: string,
  person1Features: any,
  person1Interpretation: any,
  person2Features: any,
  person2Interpretation: any,
  language: string
): string {
  const langInstruction =
    language === "hi"
      ? "Generate ALL text content in Hindi (Devanagari script). Use warm, respectful language appropriate for a couple reading."
      : "Generate ALL text content in English. Use warm, encouraging language appropriate for a couple reading.";

  const p1Summary = {
    name: person1Name,
    palm_shape: person1Features.palm_shape,
    heart_line: person1Features.palm_features?.heart_line,
    head_line: person1Features.palm_features?.head_line,
    life_line: person1Features.palm_features?.life_line,
    fate_line: person1Features.palm_features?.fate_line,
    mounts: person1Features.mounts,
    special_marks: person1Features.special_marks,
    personality: person1Interpretation.personality,
    love_relationships: person1Interpretation.love_relationships,
    communication_style: person1Interpretation.communication_style,
    emotional_nature: person1Interpretation.emotional_nature,
    key_traits_en: person1Interpretation.key_traits_en,
    overall_score: person1Interpretation.overall_score,
  };

  const p2Summary = {
    name: person2Name,
    palm_shape: person2Features.palm_shape,
    heart_line: person2Features.palm_features?.heart_line,
    head_line: person2Features.palm_features?.head_line,
    life_line: person2Features.palm_features?.life_line,
    fate_line: person2Features.palm_features?.fate_line,
    mounts: person2Features.mounts,
    special_marks: person2Features.special_marks,
    personality: person2Interpretation.personality,
    love_relationships: person2Interpretation.love_relationships,
    communication_style: person2Interpretation.communication_style,
    emotional_nature: person2Interpretation.emotional_nature,
    key_traits_en: person2Interpretation.key_traits_en,
    overall_score: person2Interpretation.overall_score,
  };

  return `You are HastVeda's couple compatibility interpretation engine.

${langInstruction}

MANDATORY SAFETY RULES:
- Never claim to predict death, disease, exact lifespan, pregnancy, fertility, criminal behavior, guaranteed financial returns, or legal outcomes.
- Use language like "may suggest", "traditionally associated with", "can indicate", "the reading suggests".
- This is traditional palmistry / entertainment / spiritual content, NOT scientific fact.
- Base ALL compatibility observations on the actual palm feature data provided below.
- Do NOT invent features not present in the data.
- Clearly distinguish observations from interpretations.
- Do NOT present palmistry as scientifically proven.

You have received the individual palm analysis for two people. Based ONLY on the actual palm features and interpretations provided, generate a couple compatibility reading.

PERSON 1 (${person1Name}) Palm Analysis:
${JSON.stringify(p1Summary, null, 2)}

PERSON 2 (${person2Name}) Palm Analysis:
${JSON.stringify(p2Summary, null, 2)}

Generate a compatibility reading that:
1. References specific observable features from both palms
2. Compares heart line characteristics for emotional compatibility
3. Compares head line characteristics for communication compatibility
4. Compares life line characteristics for energy/vitality compatibility
5. Compares personality traits derived from palm shape and mounts
6. Identifies complementary and contrasting patterns
7. Derives relationship strengths from actual palm observations
8. Derives potential challenges from actual palm observations

Return ONLY valid JSON (no markdown fences) matching this exact structure:
{
  "overall_compatibility_score": <integer 55-92, derived from actual feature comparison>,
  "love_score": <integer 55-92, based on heart line comparison>,
  "emotional_score": <integer 55-92, based on emotional nature comparison>,
  "communication_score": <integer 55-92, based on head line comparison>,
  "financial_score": <integer 55-92, based on fate line and mercury line comparison>,
  "career_score": <integer 55-92, based on fate line and sun line comparison>,
  "personality_score": <integer 55-92, based on palm shape and mount comparison>,
  "attraction_score": <integer 55-92, based on venus mount and heart line comparison>,
  "marriage_score": <integer 55-92, based on marriage indicators and heart line depth>,
  "overview_en": <string, 3-4 sentences summarizing the couple compatibility based on actual palm observations>,
  "overview_hi": <string, 3-4 sentences in Hindi>,
  "person1_observations_en": <string, 2-3 sentences describing Person 1's key palm traits relevant to the relationship>,
  "person1_observations_hi": <string, 2-3 sentences in Hindi>,
  "person2_observations_en": <string, 2-3 sentences describing Person 2's key palm traits relevant to the relationship>,
  "person2_observations_hi": <string, 2-3 sentences in Hindi>,
  "strengths_en": <array of 3-4 strings, each describing a relationship strength derived from actual palm features>,
  "strengths_hi": <array of 3-4 strings in Hindi>,
  "challenges_en": <array of 2-3 strings, each describing a potential challenge derived from actual palm features>,
  "challenges_hi": <array of 2-3 strings in Hindi>,
  "communication_tendencies_en": <string, 2-3 sentences about communication patterns based on head line comparison>,
  "communication_tendencies_hi": <string, 2-3 sentences in Hindi>,
  "emotional_tendencies_en": <string, 2-3 sentences about emotional patterns based on heart line comparison>,
  "emotional_tendencies_hi": <string, 2-3 sentences in Hindi>,
  "marriage_interpretation_en": <string, 2-3 sentences about long-term partnership potential based on palm observations>,
  "marriage_interpretation_hi": <string, 2-3 sentences in Hindi>,
  "growth_together_en": <array of 3 strings, growth suggestions derived from complementary palm features>,
  "growth_together_hi": <array of 3 strings in Hindi>,
  "future_tendencies_en": <array of 3 strings, future tendency observations based on palm patterns>,
  "future_tendencies_hi": <array of 3 strings in Hindi>,
  "recommendations_en": <array of 3-4 personalized recommendation strings based on the specific palm patterns observed>,
  "recommendations_hi": <array of 3-4 strings in Hindi>,
  "compatibility_basis_en": <string, 1-2 sentences explaining which specific palm features were used to derive the compatibility scores>,
  "compatibility_basis_hi": <string, 1-2 sentences in Hindi>
}`;
}

// ── Download image from Supabase storage ──────────────────────────────────────
async function downloadImage(
  serviceClient: any,
  imagePath: string
): Promise<{ base64: string; mimeType: string }> {
  const { data: imageData, error } = await serviceClient.storage
    .from("palm-images")
    .download(imagePath);

  if (error || !imageData) {
    throw new Error(`Failed to download image: ${error?.message}`);
  }

  const arrayBuffer = await imageData.arrayBuffer();
  const uint8Array = new Uint8Array(arrayBuffer);
  let binary = "";
  for (let i = 0; i < uint8Array.byteLength; i++) {
    binary += String.fromCharCode(uint8Array[i]);
  }
  return {
    base64: btoa(binary),
    mimeType: imageData.type || "image/jpeg",
  };
}

// ── Analyze single palm (Stage A + B) ────────────────────────────────────────
async function analyzeSinglePalm(
  serviceClient: any,
  imagePath: string,
  handSide: string,
  language: string
): Promise<{ features: any; interpretation: any }> {
  const { base64, mimeType } = await downloadImage(serviceClient, imagePath);

  // Stage A: Feature extraction
  const stageAPrompt = buildStageAPrompt(handSide);
  const features = await callGeminiJson(
    "Stage A",
    stageAPrompt,
    base64,
    mimeType,
    0.2,
    8192
  );

  // Validate image quality
  const imageQuality = features.image_quality || {};
  if (!imageQuality.palm_detected || !imageQuality.suitable_for_analysis || (imageQuality.score || 0) < 0.35) {
    throw {
      code: "LOW_QUALITY_IMAGE",
      quality_score: imageQuality.score || 0,
      issues: imageQuality.issues || [],
      palm_detected: imageQuality.palm_detected || false,
    };
  }

  // Stage B: Individual interpretation
  const stageBPrompt = buildStageBPrompt(features, language);
  const interpretation = await callGeminiJson(
    "Stage B",
    stageBPrompt,
    undefined,
    undefined,
    0.5,
    8192
  );

  return { features, interpretation };
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
      person1_image_path,
      person2_image_path,
      person1_name = "Person 1",
      person2_name = "Person 2",
      person1_hand_side = "right",
      person2_hand_side = "right",
      language = "en",
    } = body;

    if (!person1_image_path || !person2_image_path) {
      return new Response(
        JSON.stringify({ error: "Both person1_image_path and person2_image_path are required", code: "MISSING_IMAGES" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
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
    const hasCoupleReading = (entitlements || []).some((e: any) => {
      if (e.entitlement_type !== "COUPLE_READING") return false;
      if (!e.expires_at) return true;
      return new Date(e.expires_at) > now;
    });

    if (!isPremium && !hasCoupleReading) {
      return new Response(
        JSON.stringify({
          error: "Couple Reading requires Premium or a Couple Reading entitlement.",
          code: "ENTITLEMENT_REQUIRED",
          required_entitlement: "COUPLE_READING",
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Analyze Person 1 palm ───────────────────────────────────────────────
    let person1Features: any;
    let person1Interpretation: any;
    try {
      const result = await analyzeSinglePalm(
        serviceClient,
        person1_image_path,
        person1_hand_side,
        language
      );
      person1Features = result.features;
      person1Interpretation = result.interpretation;
    } catch (e: any) {
      if (e.code === "LOW_QUALITY_IMAGE") {
        return new Response(
          JSON.stringify({
            error: "image_quality_insufficient",
            code: "LOW_QUALITY_IMAGE_PERSON1",
            person: 1,
            quality_score: e.quality_score,
            issues: e.issues,
            palm_detected: e.palm_detected,
          }),
          { status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      return new Response(
        JSON.stringify({ error: `Person 1 palm analysis failed: ${e.message}`, code: "PERSON1_ANALYSIS_FAILED" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Analyze Person 2 palm ───────────────────────────────────────────────
    let person2Features: any;
    let person2Interpretation: any;
    try {
      const result = await analyzeSinglePalm(
        serviceClient,
        person2_image_path,
        person2_hand_side,
        language
      );
      person2Features = result.features;
      person2Interpretation = result.interpretation;
    } catch (e: any) {
      if (e.code === "LOW_QUALITY_IMAGE") {
        return new Response(
          JSON.stringify({
            error: "image_quality_insufficient",
            code: "LOW_QUALITY_IMAGE_PERSON2",
            person: 2,
            quality_score: e.quality_score,
            issues: e.issues,
            palm_detected: e.palm_detected,
          }),
          { status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      return new Response(
        JSON.stringify({ error: `Person 2 palm analysis failed: ${e.message}`, code: "PERSON2_ANALYSIS_FAILED" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Stage C: Couple compatibility interpretation ─────────────────────────
    let compatibilityResult: any;
    try {
      const stageCPrompt = buildStageCPrompt(
        person1_name,
        person2_name,
        person1Features,
        person1Interpretation,
        person2Features,
        person2Interpretation,
        language
      );
      compatibilityResult = await callGeminiJson(
        "Stage C",
        stageCPrompt,
        undefined,
        undefined,
        0.5,
        8192
      );
    } catch (e: any) {
      return new Response(
        JSON.stringify({ error: `Compatibility analysis failed: ${e.message}`, code: "COMPATIBILITY_FAILED" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const processingTimeMs = Date.now() - startTime;

    // ── Save to couple_readings ──────────────────────────────────────────────
    const coupleReadingData = {
      user_id: userId,
      partner_name: person2_name,
      person1_name: person1_name,
      person2_name: person2_name,
      overall_compatibility_score: compatibilityResult.overall_compatibility_score || 75,
      love_score: compatibilityResult.love_score || 75,
      emotional_score: compatibilityResult.emotional_score || 75,
      communication_score: compatibilityResult.communication_score || 75,
      financial_score: compatibilityResult.financial_score || 75,
      career_score: compatibilityResult.career_score || 75,
      personality_score: compatibilityResult.personality_score || 75,
      attraction_score: compatibilityResult.attraction_score || 75,
      marriage_score: compatibilityResult.marriage_score || 75,
      compatibility_data: {
        // Full compatibility interpretation
        overview_en: compatibilityResult.overview_en || "",
        overview_hi: compatibilityResult.overview_hi || "",
        person1_observations_en: compatibilityResult.person1_observations_en || "",
        person1_observations_hi: compatibilityResult.person1_observations_hi || "",
        person2_observations_en: compatibilityResult.person2_observations_en || "",
        person2_observations_hi: compatibilityResult.person2_observations_hi || "",
        strengths_en: compatibilityResult.strengths_en || [],
        strengths_hi: compatibilityResult.strengths_hi || [],
        challenges_en: compatibilityResult.challenges_en || [],
        challenges_hi: compatibilityResult.challenges_hi || [],
        communication_tendencies_en: compatibilityResult.communication_tendencies_en || "",
        communication_tendencies_hi: compatibilityResult.communication_tendencies_hi || "",
        emotional_tendencies_en: compatibilityResult.emotional_tendencies_en || "",
        emotional_tendencies_hi: compatibilityResult.emotional_tendencies_hi || "",
        marriage_interpretation_en: compatibilityResult.marriage_interpretation_en || "",
        marriage_interpretation_hi: compatibilityResult.marriage_interpretation_hi || "",
        growth_together_en: compatibilityResult.growth_together_en || [],
        growth_together_hi: compatibilityResult.growth_together_hi || [],
        future_tendencies_en: compatibilityResult.future_tendencies_en || [],
        future_tendencies_hi: compatibilityResult.future_tendencies_hi || [],
        recommendations_en: compatibilityResult.recommendations_en || [],
        recommendations_hi: compatibilityResult.recommendations_hi || [],
        compatibility_basis_en: compatibilityResult.compatibility_basis_en || "",
        compatibility_basis_hi: compatibilityResult.compatibility_basis_hi || "",
        // Person summaries
        person1_summary_en: person1Interpretation.summary_en || "",
        person1_summary_hi: person1Interpretation.summary_hi || "",
        person1_key_traits_en: person1Interpretation.key_traits_en || [],
        person1_key_traits_hi: person1Interpretation.key_traits_hi || [],
        person2_summary_en: person2Interpretation.summary_en || "",
        person2_summary_hi: person2Interpretation.summary_hi || "",
        person2_key_traits_en: person2Interpretation.key_traits_en || [],
        person2_key_traits_hi: person2Interpretation.key_traits_hi || [],
        // Raw features for reference
        person1_features: person1Features,
        person2_features: person2Features,
        language,
        processing_time_ms: processingTimeMs,
        ai_model: currentModel(),
      },
      compatibility_analysis: {
        overview_en: compatibilityResult.overview_en || "",
        overview_hi: compatibilityResult.overview_hi || "",
      },
      relationship_strengths: compatibilityResult.strengths_en || [],
      relationship_challenges: compatibilityResult.challenges_en || [],
      love_compatibility: compatibilityResult.emotional_tendencies_en || "",
      summary: compatibilityResult.overview_en || "",
      language,
      status: "completed",
      is_complete: true,
    };

    const { data: savedReading, error: saveError } = await serviceClient
      .from("couple_readings")
      .insert(coupleReadingData)
      .select()
      .single();

    if (saveError) {
      console.error("Failed to save couple reading:", saveError);
    }

    const coupleReadingId = savedReading?.id;

    // ── Save to reading_history ──────────────────────────────────────────────
    const historyTitle = language === "hi"
      ? `${person1_name} & ${person2_name} — युगल पठन`
      : `${person1_name} & ${person2_name} — Couple Reading`;

    const historySummary = language === "hi"
      ? (compatibilityResult.overview_hi || compatibilityResult.overview_en || "युगल अनुकूलता पठन पूर्ण हुआ।")
      : (compatibilityResult.overview_en || "Couple compatibility reading completed.");

    await serviceClient.from("reading_history").insert({
      user_id: userId,
      reading_type: "couple",
      title: historyTitle,
      summary: historySummary,
      is_complete: true,
      is_premium: isPremium,
      completed_at: new Date().toISOString(),
      metadata: {
        couple_reading_id: coupleReadingId,
        person1_name,
        person2_name,
        overall_score: compatibilityResult.overall_compatibility_score || 75,
        language,
      },
    });

    // ── Log AI usage ─────────────────────────────────────────────────────────
    await serviceClient.from("ai_usage").insert({
      user_id: userId,
      ai_provider: "google",
      ai_model: currentModel(),
      operation_type: "couple_reading",
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      latency_ms: processingTimeMs,
      success: true,
    });

    // ── Return result ────────────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        couple_reading_id: coupleReadingId,
        processing_time_ms: processingTimeMs,
        data: {
          couple_reading_id: coupleReadingId,
          person1_name,
          person2_name,
          overall_compatibility_score: compatibilityResult.overall_compatibility_score || 75,
          love_score: compatibilityResult.love_score || 75,
          emotional_score: compatibilityResult.emotional_score || 75,
          communication_score: compatibilityResult.communication_score || 75,
          financial_score: compatibilityResult.financial_score || 75,
          career_score: compatibilityResult.career_score || 75,
          personality_score: compatibilityResult.personality_score || 75,
          attraction_score: compatibilityResult.attraction_score || 75,
          marriage_score: compatibilityResult.marriage_score || 75,
          overview_en: compatibilityResult.overview_en || "",
          overview_hi: compatibilityResult.overview_hi || "",
          person1_observations_en: compatibilityResult.person1_observations_en || "",
          person1_observations_hi: compatibilityResult.person1_observations_hi || "",
          person2_observations_en: compatibilityResult.person2_observations_en || "",
          person2_observations_hi: compatibilityResult.person2_observations_hi || "",
          strengths_en: compatibilityResult.strengths_en || [],
          strengths_hi: compatibilityResult.strengths_hi || [],
          challenges_en: compatibilityResult.challenges_en || [],
          challenges_hi: compatibilityResult.challenges_hi || [],
          communication_tendencies_en: compatibilityResult.communication_tendencies_en || "",
          communication_tendencies_hi: compatibilityResult.communication_tendencies_hi || "",
          emotional_tendencies_en: compatibilityResult.emotional_tendencies_en || "",
          emotional_tendencies_hi: compatibilityResult.emotional_tendencies_hi || "",
          marriage_interpretation_en: compatibilityResult.marriage_interpretation_en || "",
          marriage_interpretation_hi: compatibilityResult.marriage_interpretation_hi || "",
          growth_together_en: compatibilityResult.growth_together_en || [],
          growth_together_hi: compatibilityResult.growth_together_hi || [],
          future_tendencies_en: compatibilityResult.future_tendencies_en || [],
          future_tendencies_hi: compatibilityResult.future_tendencies_hi || [],
          recommendations_en: compatibilityResult.recommendations_en || [],
          recommendations_hi: compatibilityResult.recommendations_hi || [],
          compatibility_basis_en: compatibilityResult.compatibility_basis_en || "",
          compatibility_basis_hi: compatibilityResult.compatibility_basis_hi || "",
          person1_summary_en: person1Interpretation.summary_en || "",
          person1_summary_hi: person1Interpretation.summary_hi || "",
          person1_key_traits_en: person1Interpretation.key_traits_en || [],
          person1_key_traits_hi: person1Interpretation.key_traits_hi || [],
          person2_summary_en: person2Interpretation.summary_en || "",
          person2_summary_hi: person2Interpretation.summary_hi || "",
          person2_key_traits_en: person2Interpretation.key_traits_en || [],
          person2_key_traits_hi: person2Interpretation.key_traits_hi || [],
          language,
          is_premium: isPremium,
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Couple reading error:", error);
    return new Response(
      JSON.stringify({
        error: "An unexpected error occurred. Please try again.",
        code: "INTERNAL_ERROR",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
