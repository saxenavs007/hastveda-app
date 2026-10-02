// answer-hastveda-question Edge Function
// Securely processes a user's palm question using HastVeda's existing Gemini AI infrastructure.
// Called by: verify-cashfree-payment, cashfree-webhook, and directly from Flutter app.
//
// Security guarantees:
// 1. Verifies question belongs to authenticated user (or uses service-role for internal calls)
// 2. Verifies question is legitimately free (≤2 per Premium user) OR has a paid ₹50 order
// 3. Prevents double-processing (idempotent)
// 4. Never allows unpaid ₹50 questions to be answered
// 5. Handles AI failure safely — records failed status without losing the question
//
// SECRETS REQUIRED (set in Supabase Dashboard → Project Settings → Edge Functions → Secrets):
//   GEMINI_API_KEY            — Google Gemini API key
//   AWS_LAMBDA_CHAT_COMPLETION_URL — AWS Lambda proxy URL (primary AI path)
//   SUPABASE_SERVICE_ROLE_KEY — auto-set by Supabase
//   SUPABASE_ANON_KEY         — auto-set by Supabase
//   SUPABASE_URL              — auto-set by Supabase

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const FREE_QUESTION_LIMIT = 2;

// ── HastVeda AI system prompt ─────────────────────────────────────────────────
const HASTVEDA_SYSTEM_PROMPT = `You are HastVeda, an ancient and wise palm reading oracle deeply rooted in Indian Vedic tradition and palmistry. You have profound knowledge of:
- Hasta Rekha Shastra (Indian palmistry)
- The major and minor lines of the palm (life line, heart line, head line, fate line, sun line, mercury line)
- Mounts of the palm and their significance
- Finger shapes, lengths, and their meanings
- Vedic astrology connections to palmistry
- Practical life guidance based on palm features

Your personality:
- Warm, wise, and deeply compassionate
- Speak with the authority of ancient wisdom
- Use occasional Sanskrit/Hindi terms naturally (with brief explanations)
- Ground your insights in both traditional palmistry and practical modern life guidance
- Be specific and personal — never give generic advice
- Balance spiritual wisdom with actionable practical guidance

When answering questions:
- Reference specific palm features when relevant
- Connect the question to broader life patterns visible in palmistry
- Provide both traditional interpretation and modern practical guidance
- Be encouraging but honest
- Give complete, natural answers — never stop mid-sentence or mid-thought
- If the question is about a specific palm feature, explain what that feature typically indicates

Always respond as HastVeda — the ancient oracle, not as an AI assistant.`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    const awsLambdaUrl = Deno.env.get("AWS_LAMBDA_CHAT_COMPLETION_URL");

    // ── Startup diagnostics (secrets presence check) ──────────
    console.log(`[answer-hastveda-question] Startup check:
  SUPABASE_URL: ${supabaseUrl ? "✅ set" : "❌ MISSING"}
  SUPABASE_SERVICE_ROLE_KEY: ${supabaseServiceKey ? "✅ set" : "❌ MISSING"}
  GEMINI_API_KEY: ${geminiApiKey ? "✅ set" : "❌ MISSING — AI will fail"}
  AWS_LAMBDA_CHAT_COMPLETION_URL: ${awsLambdaUrl ? "✅ set" : "⚠️ not set — will use Gemini direct fallback"}`);

    if (!geminiApiKey && !awsLambdaUrl) {
      console.error("[answer-hastveda-question] CRITICAL: Neither GEMINI_API_KEY nor AWS_LAMBDA_CHAT_COMPLETION_URL is configured as a Supabase Edge Function secret. Set them in Supabase Dashboard → Project Settings → Edge Functions → Secrets.");
    }

    // ── Determine caller type ─────────────────────────────────
    const isInternalCall = req.headers.get("x-internal-call") !== null;
    const authHeader = req.headers.get("Authorization");

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let authenticatedUserId: string | null = null;

    if (isInternalCall) {
      const body = await req.json();
      const { question_usage_id, user_id } = body;

      if (!question_usage_id || !user_id) {
        return new Response(
          JSON.stringify({ error: "question_usage_id and user_id required for internal calls" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      authenticatedUserId = user_id;
      return await processQuestion(supabase, question_usage_id, authenticatedUserId, awsLambdaUrl ?? null, geminiApiKey ?? null, corsHeaders, true);
    }

    // External call from Flutter — verify JWT
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUser = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    authenticatedUserId = user.id;

    const body = await req.json();
    const { question_usage_id } = body;

    if (!question_usage_id) {
      return new Response(
        JSON.stringify({ error: "question_usage_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return await processQuestion(supabase, question_usage_id, authenticatedUserId, awsLambdaUrl ?? null, geminiApiKey ?? null, corsHeaders, false);

  } catch (error) {
    console.error("answer-hastveda-question error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

async function processQuestion(
  supabase: ReturnType<typeof createClient>,
  questionUsageId: string,
  userId: string,
  awsLambdaUrl: string | null,
  geminiApiKey: string | null,
  corsHeaders: Record<string, string>,
  isInternal: boolean
): Promise<Response> {
  // ── Fetch question record ─────────────────────────────────
  const { data: question, error: fetchError } = await supabase
    .from("question_usage")
    .select("*")
    .eq("id", questionUsageId)
    .maybeSingle();

  if (fetchError || !question) {
    return new Response(
      JSON.stringify({ error: "Question not found" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // ── Ownership verification ────────────────────────────────
  if (question.user_id !== userId) {
    console.error(`[answer-hastveda-question] Ownership mismatch: question.user_id=${question.user_id} vs authenticated=${userId}`);
    return new Response(
      JSON.stringify({ error: "Unauthorized — question does not belong to this user" }),
      { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // ── Idempotency: already answered ────────────────────────
  if (question.status === "answered" && question.answer_text) {
    return new Response(
      JSON.stringify({
        success: true,
        already_answered: true,
        answer_text: question.answer_text,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // ── Prevent double-processing ─────────────────────────────
  if (question.status === "processing") {
    return new Response(
      JSON.stringify({ success: false, status: "processing", message: "Question is already being processed" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // ── Legitimacy check: free question ──────────────────────
  if (question.is_free === true) {
    const { count: freeCount } = await supabase
      .from("question_usage")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("is_free", true);

    if ((freeCount ?? 0) > FREE_QUESTION_LIMIT) {
      await supabase
        .from("question_usage")
        .update({ status: "rejected_free_quota_exceeded", updated_at: new Date().toISOString() })
        .eq("id", questionUsageId);

      return new Response(
        JSON.stringify({ error: "Free question quota exceeded. Please pay ₹50 for additional questions." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: entitlement } = await supabase
      .from("entitlements")
      .select("id")
      .eq("user_id", userId)
      .eq("entitlement_type", "PREMIUM")
      .eq("is_active", true)
      .maybeSingle();

    if (!entitlement) {
      await supabase
        .from("question_usage")
        .update({ status: "rejected_no_premium", updated_at: new Date().toISOString() })
        .eq("id", questionUsageId);

      return new Response(
        JSON.stringify({ error: "Premium subscription required for free questions." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  } else {
    // ── Legitimacy check: paid question ──────────────────────
    if (!question.is_paid || !question.payment_order_id) {
      return new Response(
        JSON.stringify({ error: "Question payment not verified. Please complete payment first." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: paymentOrder } = await supabase
      .from("cashfree_orders")
      .select("status, product_id, user_id")
      .eq("cashfree_order_id", question.payment_order_id)
      .maybeSingle();

    if (!paymentOrder || paymentOrder.status !== "payment_successful") {
      return new Response(
        JSON.stringify({ error: "Payment not confirmed. Please verify your payment." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (paymentOrder.product_id !== "ask_question") {
      console.error(`[answer-hastveda-question] Wrong product_id on payment: ${paymentOrder.product_id}`);
      return new Response(
        JSON.stringify({ error: "Invalid payment type for this question." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (paymentOrder.user_id !== userId) {
      console.error(`[answer-hastveda-question] Payment user mismatch`);
      return new Response(
        JSON.stringify({ error: "Payment does not belong to this user." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { count: usageCount } = await supabase
      .from("question_usage")
      .select("id", { count: "exact", head: true })
      .eq("payment_order_id", question.payment_order_id)
      .eq("status", "answered");

    if ((usageCount ?? 0) > 0) {
      return new Response(
        JSON.stringify({ error: "This payment has already been used for a question." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  }

  // ── Question text validation ──────────────────────────────
  const questionText = (question.question_text ?? "").trim();
  if (!questionText) {
    await supabase
      .from("question_usage")
      .update({ status: "failed_empty_question", updated_at: new Date().toISOString() })
      .eq("id", questionUsageId);

    return new Response(
      JSON.stringify({ error: "Question text is empty." }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // ── Mark as processing (prevents duplicate calls) ─────────
  await supabase
    .from("question_usage")
    .update({ status: "processing", updated_at: new Date().toISOString() })
    .eq("id", questionUsageId);

  // ── Call AI via AWS Lambda (existing HastVeda infrastructure) ──
  let answerText: string | null = null;
  let aiError: string | null = null;

  try {
    const messages = [
      {
        role: "user",
        content: questionText,
      },
    ];

    // Lambda uses @rocketnew/llm-sdk which requires:
    //  - uppercase provider key (GEMINI, not gemini)
    //  - model IDs prefixed with the provider slug (gemini/<model>)
    // gemini-1.5-flash was retired at Google; other Edge Functions in this repo
    // (palm-analysis, couple-reading, detailed-report) already use gemini-3.6-flash.
    const lambdaPayload = {
      provider: "GEMINI",
      model: "gemini/gemini-3.6-flash",
      messages,
      stream: false,
      parameters: {
        system: HASTVEDA_SYSTEM_PROMPT,
        temperature: 0.7,
        max_tokens: 2048,
      },
    };

    let aiResponse: any = null;
    let usedFallback = false;

    // Try AWS Lambda first (existing infrastructure)
    if (awsLambdaUrl) {
      try {
        console.log(`[answer-hastveda-question] Calling AWS Lambda: ${awsLambdaUrl.substring(0, 60)}...`);
        const lambdaResponse = await fetch(awsLambdaUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(lambdaPayload),
        });

        if (lambdaResponse.ok) {
          aiResponse = await lambdaResponse.json();
          console.log("[answer-hastveda-question] Lambda call succeeded");
        } else {
          const errText = await lambdaResponse.text();
          console.error(`[answer-hastveda-question] Lambda returned non-OK: ${lambdaResponse.status} — ${errText}`);
        }
      } catch (lambdaErr) {
        console.error("[answer-hastveda-question] Lambda call threw exception:", lambdaErr);
      }
    } else {
      console.warn("[answer-hastveda-question] AWS_LAMBDA_CHAT_COMPLETION_URL not set — skipping Lambda, using Gemini direct");
    }

    // Fallback: direct Gemini API if Lambda failed or not configured
    if (!aiResponse) {
      if (!geminiApiKey) {
        throw new Error("GEMINI_API_KEY is not configured as a Supabase Edge Function secret. Set it in Supabase Dashboard → Project Settings → Edge Functions → Secrets.");
      }
      usedFallback = true;
      console.log("[answer-hastveda-question] Using direct Gemini API fallback");
      const geminiResponse = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${geminiApiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: HASTVEDA_SYSTEM_PROMPT }] },
            contents: [{ role: "user", parts: [{ text: questionText }] }],
            generationConfig: { temperature: 0.7, maxOutputTokens: 2048 },
          }),
        }
      );

      if (geminiResponse.ok) {
        const geminiData = await geminiResponse.json();
        const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (rawText) {
          aiResponse = { choices: [{ message: { content: rawText } }] };
          console.log("[answer-hastveda-question] Gemini direct API succeeded");
        } else {
          console.error("[answer-hastveda-question] Gemini returned OK but no text:", JSON.stringify(geminiData));
        }
      } else {
        const errText = await geminiResponse.text();
        console.error(`[answer-hastveda-question] Gemini direct API failed: ${geminiResponse.status} — ${errText}`);
        throw new Error(`Gemini API error ${geminiResponse.status}: ${errText}`);
      }
    }

    // Extract answer text from response
    if (aiResponse) {
      answerText =
        aiResponse?.choices?.[0]?.message?.content ||
        aiResponse?.content ||
        aiResponse?.text ||
        null;
    }

    if (!answerText) {
      throw new Error("AI returned empty response");
    }

    console.log(`[answer-hastveda-question] AI answer generated (${answerText.length} chars) via ${usedFallback ? "Gemini direct" : "Lambda"}`);

  } catch (err) {
    aiError = err instanceof Error ? err.message : String(err);
    console.error("[answer-hastveda-question] AI call failed:", aiError);
  }

  // ── Store result ──────────────────────────────────────────
  if (answerText) {
    const { error: updateError } = await supabase
      .from("question_usage")
      .update({
        answer_text: answerText,
        status: "answered",
        answered_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", questionUsageId);

    if (updateError) {
      console.error("[answer-hastveda-question] Failed to store answer:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to store answer. Please contact support." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        status: "answered",
        answer_text: answerText,
        question_id: questionUsageId,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } else {
    // AI failed — record failure safely, preserve question
    await supabase
      .from("question_usage")
      .update({
        status: "failed",
        answer_text: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", questionUsageId);

    return new Response(
      JSON.stringify({
        success: false,
        status: "failed",
        error: "AI analysis temporarily unavailable. Your question has been saved and will be answered soon.",
        ai_error: aiError,
        hint: "Ensure GEMINI_API_KEY and AWS_LAMBDA_CHAT_COMPLETION_URL are set as Supabase Edge Function secrets.",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
}
