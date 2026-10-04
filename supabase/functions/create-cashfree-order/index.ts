import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Environment-aware Cashfree configuration ──────────────────
const CASHFREE_ENV = Deno.env.get("CASHFREE_ENV") ?? "production";
const IS_SANDBOX = CASHFREE_ENV === "sandbox";
const CASHFREE_BASE_URL = IS_SANDBOX
  ? "https://sandbox.cashfree.com/pg"
  : "https://api.cashfree.com/pg";
const CASHFREE_API_VERSION = "2025-01-01";

// Pricing constants (server-side — never trust client)
const REGULAR_PRICE = 299.0;
const LAUNCH_PRICE = 199.0;
const ASK_QUESTION_PRICE = 50.0; // ₹50 per additional question
const MIN_PAYABLE = 1.0; // Cashfree minimum
const GST_RATE = 0.18; // 18% GST

// Keep checkout on the browser that started the order. Only accept a return
// URL whose origin matches the request Origin header.
function cashfreeReturnUrl(
  req: Request,
  requested: unknown,
  orderId: string,
): string {
  const fallback =
    `https://palmveda4192.builtwithrocket.new?order_id=${encodeURIComponent(orderId)}`;
  const originHeader = req.headers.get("origin");
  if (
    !originHeader ||
    typeof requested !== "string" ||
    requested.length === 0 ||
    requested.length > 500
  ) {
    return fallback;
  }
  try {
    const origin = new URL(originHeader);
    const target = new URL(requested);
    const local =
      origin.hostname === "localhost" || origin.hostname === "127.0.0.1";
    const httpsOk = origin.protocol === "https:" && target.protocol === "https:";
    const localOk =
      local && (target.protocol === "http:" || target.protocol === "https:");
    if (target.origin !== origin.origin || !(httpsOk || localOk)) {
      return fallback;
    }
    target.searchParams.set("order_id", orderId);
    target.hash = "";
    return target.toString();
  } catch {
    return fallback;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    // Use sandbox credentials when CASHFREE_ENV=sandbox; production credentials otherwise.
    // Production credentials (CASHFREE_APP_ID / CASHFREE_SECRET_KEY) are NEVER modified.
    const cashfreeAppId = IS_SANDBOX
      ? Deno.env.get("CASHFREE_SANDBOX_APP_ID")!
      : Deno.env.get("CASHFREE_APP_ID")!;
    const cashfreeSecretKey = IS_SANDBOX
      ? Deno.env.get("CASHFREE_SANDBOX_SECRET_KEY")!
      : Deno.env.get("CASHFREE_SECRET_KEY")!;

    // User-scoped client for auth verification
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

    // Service-role client for DB writes
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── Parse request ─────────────────────────────────────────
    const body = await req.json();
    const couponCode: string | null = body.coupon_code?.trim()?.toUpperCase() || null;
    // product_type: 'premium' (default) or 'ask_question'
    const productType: string = body.product_type || "premium";

    // ── Fetch user profile (self-healing with full diagnostics) ──
    let { data: profile } = await supabase
      .from("user_profiles")
      .select("id, email, full_name, phone")
      .eq("id", user.id)
      .maybeSingle();

    if (!profile) {
      console.log(
        `[create-cashfree-order] Profile missing for auth uid=${user.id}, email=${user.email}. Attempting self-heal INSERT.`
      );

      const { data: insertedProfile, error: insertError } = await supabase
        .from("user_profiles")
        .insert({
          id: user.id,
          email: user.email ?? "",
          full_name: user.user_metadata?.full_name ?? user.email?.split("@")[0] ?? "HastVeda User",
          avatar_url: user.user_metadata?.avatar_url ?? null,
        })
        .select("id, email, full_name, phone")
        .maybeSingle();

      if (insertError) {
        const pgCode = (insertError as any).code ?? "unknown";
        const pgMessage = (insertError as any).message ?? String(insertError);
        const pgDetails = (insertError as any).details ?? "";
        const pgHint = (insertError as any).hint ?? "";

        console.error(
          `[create-cashfree-order] INSERT failed: code=${pgCode} message=${pgMessage} details=${pgDetails} hint=${pgHint}`
        );

        if (pgCode === "23505") {
          const { data: existingByEmail } = await supabase
            .from("user_profiles")
            .select("id, email, full_name, phone")
            .eq("email", user.email ?? "")
            .maybeSingle();

          if (existingByEmail) {
            profile = existingByEmail;
            console.log(`[create-cashfree-order] Found profile by email for uid=${user.id}`);
          } else {
            return new Response(
              JSON.stringify({
                error: "Profile creation failed. Please contact support.",
                diagnostic: { db_error_code: pgCode, auth_uid: user.id },
              }),
              { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
        } else {
          return new Response(
            JSON.stringify({
              error: "Failed to create user profile due to a database error.",
              diagnostic: {
                db_error_code: pgCode,
                db_error_message: pgMessage,
                db_error_details: pgDetails,
                db_error_hint: pgHint,
                auth_uid: user.id,
                auth_email: user.email,
              },
            }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      if (!insertedProfile && !profile) {
        return new Response(
          JSON.stringify({
            error: "Profile creation returned no row. Please contact support.",
            diagnostic: { auth_uid: user.id, auth_email: user.email },
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (insertedProfile) {
        profile = insertedProfile;
      }
      console.log(`[create-cashfree-order] Profile auto-created successfully for uid=${user.id}`);
    }

    // ── Product-type routing ──────────────────────────────────
    if (productType === "ask_question") {
      // ₹50 additional question — no coupon, no Premium check needed
      const baseAmount = ASK_QUESTION_PRICE;
      const gstAmount = Math.round(baseAmount * GST_RATE * 100) / 100; // ₹9.00
      const questionAmount = Math.round((baseAmount + gstAmount) * 100) / 100; // ₹59.00
      const timestamp = Date.now();
      const randomSuffix = Math.random().toString(36).substring(2, 8).toUpperCase();
      const cashfreeOrderId = `HV_Q_${timestamp}_${randomSuffix}`;

      const cashfreePayload = {
        order_id: cashfreeOrderId,
        order_amount: questionAmount,
        order_currency: "INR",
        customer_details: {
          customer_id: user.id.replace(/-/g, "").substring(0, 50),
          customer_name: profile.full_name || "HastVeda User",
          customer_email: profile.email || user.email || "user@hastveda.com",
          customer_phone: profile.phone || "9999999999",
        },
        order_meta: {
          return_url: cashfreeReturnUrl(req, body.return_url, cashfreeOrderId),
          notify_url: `${supabaseUrl}/functions/v1/cashfree-webhook`,
        },
        order_note: "HastVeda — Ask Question",
      };

      const cashfreeResponse = await fetch(`${CASHFREE_BASE_URL}/orders`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "x-client-id": cashfreeAppId,
          "x-client-secret": cashfreeSecretKey,
          "x-api-version": CASHFREE_API_VERSION,
        },
        body: JSON.stringify(cashfreePayload),
      });

      // Log credential presence (never log values)
      console.log(
        `[create-cashfree-order] ask_question: env=${CASHFREE_ENV} appId_present=${!!cashfreeAppId} secretKey_present=${!!cashfreeSecretKey} url=${CASHFREE_BASE_URL}`
      );

      const cashfreeHttpStatus = cashfreeResponse.status;
      if (!cashfreeResponse.ok) {
        let errorBody: string;
        try { errorBody = await cashfreeResponse.text(); } catch (_) { errorBody = "(unreadable)"; }
        console.error(
          `[create-cashfree-order] ask_question Cashfree order failed. HTTP ${cashfreeHttpStatus}:`,
          errorBody
        );
        let parsedError: Record<string, unknown> = {};
        try { parsedError = JSON.parse(errorBody); } catch (_) {}
        return new Response(
          JSON.stringify({
            error: "Payment gateway error. Please try again.",
            diagnostic: {
              cashfree_http_status: cashfreeHttpStatus,
              cashfree_error_code: parsedError.code ?? parsedError.error_code ?? null,
              cashfree_error_message: parsedError.message ?? parsedError.error_description ?? null,
              cashfree_error_type: parsedError.type ?? null,
            },
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      let cashfreeData: Record<string, unknown>;
      try {
        cashfreeData = await cashfreeResponse.json();
      } catch (_) {
        console.error(`[create-cashfree-order] ask_question: Cashfree returned non-JSON on HTTP ${cashfreeHttpStatus}`);
        return new Response(
          JSON.stringify({
            error: "Payment gateway returned an unexpected response. Please try again.",
            diagnostic: { cashfree_http_status: cashfreeHttpStatus },
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const paymentSessionId = cashfreeData.payment_session_id as string | undefined;

      // ── Guard: payment_session_id must be present (mirrors premium branch guard) ──
      if (!paymentSessionId || String(paymentSessionId).trim() === "") {
        console.error(
          `[create-cashfree-order] ask_question: Cashfree returned HTTP ${cashfreeHttpStatus} but payment_session_id is missing/empty.`,
          JSON.stringify(cashfreeData)
        );
        return new Response(
          JSON.stringify({
            error: "Payment gateway did not return a session token. Please try again.",
            diagnostic: {
              cashfree_http_status: cashfreeHttpStatus,
              cashfree_order_id: cashfreeData.order_id ?? null,
              cashfree_order_status: cashfreeData.order_status ?? null,
            },
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Store in cashfree_orders with product_id = 'ask_question'
      await supabase.from("cashfree_orders").insert({
        user_id: user.id,
        cashfree_order_id: cashfreeOrderId,
        payment_session_id: paymentSessionId,
        original_amount: baseAmount,
        discount_amount: 0,
        final_amount: questionAmount,
        base_amount: baseAmount,
        gst_rate: GST_RATE,
        gst_amount: gstAmount,
        currency: "INR",
        status: "order_created",
        coupon_id: null,
        coupon_code: null,
        product_id: "ask_question",
      });

      return new Response(
        JSON.stringify({
          success: true,
          order_id: cashfreeOrderId,
          payment_session_id: paymentSessionId,
          final_amount: questionAmount,
          original_amount: baseAmount,
          base_amount: baseAmount,
          gst_rate: GST_RATE,
          gst_amount: gstAmount,
          discount_amount: 0,
          currency: "INR",
          environment: CASHFREE_ENV,
          product_type: "ask_question",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Default: Premium purchase ─────────────────────────────

    // Check if already Premium
    const { data: existingEntitlement } = await supabase
      .from("entitlements")
      .select("id")
      .eq("user_id", user.id)
      .eq("entitlement_type", "PREMIUM")
      .eq("is_active", true)
      .maybeSingle();

    if (existingEntitlement) {
      return new Response(
        JSON.stringify({ error: "User already has Premium access" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Coupon validation (server-side) ───────────────────────
    let discountAmount = 0;
    let couponId: string | null = null;
    let couponRecord: Record<string, unknown> | null = null;

    if (couponCode) {
      const { data: coupon, error: couponError } = await supabase
        .from("discount_codes")
        .select("*")
        .eq("code", couponCode)
        .eq("is_active", true)
        .maybeSingle();

      if (couponError || !coupon) {
        return new Response(
          JSON.stringify({ error: "Invalid or inactive coupon code" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (coupon.expires_at && new Date(coupon.expires_at) < new Date()) {
        return new Response(
          JSON.stringify({ error: "Coupon code has expired" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (coupon.used_count >= coupon.max_redemptions) {
        return new Response(
          JSON.stringify({ error: "Coupon usage limit reached" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (coupon.assigned_user_id && coupon.assigned_user_id !== user.id) {
        return new Response(
          JSON.stringify({ error: "This coupon is not valid for your account" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { count: userRedemptionCount } = await supabase
        .from("coupon_redemptions")
        .select("id", { count: "exact", head: true })
        .eq("coupon_id", coupon.id)
        .eq("user_id", user.id)
        .eq("payment_status", "success");

      if ((userRedemptionCount || 0) >= coupon.max_per_customer) {
        return new Response(
          JSON.stringify({ error: "You have already used this coupon" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (coupon.discount_type === "percentage") {
        discountAmount = Math.min(
          (LAUNCH_PRICE * coupon.discount_value) / 100,
          LAUNCH_PRICE - MIN_PAYABLE
        );
      } else {
        discountAmount = Math.min(coupon.discount_value, LAUNCH_PRICE - MIN_PAYABLE);
      }
      discountAmount = Math.round(discountAmount * 100) / 100;
      couponId = coupon.id;
      couponRecord = coupon;
    }

    // ── Calculate final amount (server-side) ──────────────────
    const originalAmount = LAUNCH_PRICE;
    const finalAmount = Math.max(originalAmount - discountAmount, MIN_PAYABLE);
    const finalAmountRounded = Math.round(finalAmount * 100) / 100;

    // Add 18% GST on the post-discount amount
    const gstAmount = Math.round(finalAmountRounded * GST_RATE * 100) / 100;
    const gstInclusiveAmount = Math.round((finalAmountRounded + gstAmount) * 100) / 100;

    // ── Generate unique order ID ──────────────────────────────
    const timestamp = Date.now();
    const randomSuffix = Math.random().toString(36).substring(2, 8).toUpperCase();
    const cashfreeOrderId = `HV_${timestamp}_${randomSuffix}`;

    // ── Create Cashfree order ─────────────────────────────────
    const cashfreePayload = {
      order_id: cashfreeOrderId,
      order_amount: gstInclusiveAmount,
      order_currency: "INR",
      customer_details: {
        customer_id: user.id.replace(/-/g, "").substring(0, 50),
        customer_name: profile.full_name || "HastVeda User",
        customer_email: profile.email || user.email || "user@hastveda.com",
        customer_phone: profile.phone || "9999999999",
      },
      order_meta: {
        return_url: cashfreeReturnUrl(req, body.return_url, cashfreeOrderId),
        notify_url: `${supabaseUrl}/functions/v1/cashfree-webhook`,
      },
      order_note: "HastVeda Premium Access",
    };

    const cashfreeResponse = await fetch(`${CASHFREE_BASE_URL}/orders`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "x-client-id": cashfreeAppId,
        "x-client-secret": cashfreeSecretKey,
        "x-api-version": CASHFREE_API_VERSION,
      },
      body: JSON.stringify(cashfreePayload),
    });

    // ── Inspect Cashfree HTTP response ───────────────────────
    const cashfreeHttpStatus = cashfreeResponse.status;
    let cashfreeData: Record<string, unknown>;
    try {
      cashfreeData = await cashfreeResponse.json();
    } catch (_) {
      const rawText = await cashfreeResponse.text().catch(() => "(unreadable)");
      console.error(`[create-cashfree-order] Cashfree non-JSON response. HTTP ${cashfreeHttpStatus}: ${rawText}`);
      return new Response(
        JSON.stringify({
          error: "Payment gateway returned an unexpected response. Please try again.",
          diagnostic: { cashfree_http_status: cashfreeHttpStatus },
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!cashfreeResponse.ok) {
      // Log full error body server-side (never sent to client)
      console.error(
        `[create-cashfree-order] Cashfree order creation failed. HTTP ${cashfreeHttpStatus}:`,
        JSON.stringify(cashfreeData)
      );
      // Return safe diagnostic to client — no credentials exposed
      return new Response(
        JSON.stringify({
          error: "Payment gateway error. Please try again.",
          diagnostic: {
            cashfree_http_status: cashfreeHttpStatus,
            cashfree_error_code: cashfreeData.code ?? cashfreeData.error_code ?? null,
            cashfree_error_message: cashfreeData.message ?? cashfreeData.error_description ?? null,
            cashfree_error_type: cashfreeData.type ?? null,
          },
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const paymentSessionId = cashfreeData.payment_session_id as string | undefined;

    // ── Guard: payment_session_id must be present ─────────────
    if (!paymentSessionId || String(paymentSessionId).trim() === "") {
      console.error(
        `[create-cashfree-order] Cashfree returned HTTP ${cashfreeHttpStatus} but payment_session_id is missing/empty.`,
        JSON.stringify(cashfreeData)
      );
      return new Response(
        JSON.stringify({
          error: "Payment gateway did not return a session token. Please try again.",
          diagnostic: {
            cashfree_http_status: cashfreeHttpStatus,
            cashfree_order_id: cashfreeData.order_id ?? null,
            cashfree_order_status: cashfreeData.order_status ?? null,
          },
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Store order in Supabase ───────────────────────────────
    const { data: orderRecord, error: orderError } = await supabase
      .from("cashfree_orders")
      .insert({
        user_id: user.id,
        cashfree_order_id: cashfreeOrderId,
        payment_session_id: paymentSessionId,
        original_amount: originalAmount,
        discount_amount: discountAmount,
        final_amount: gstInclusiveAmount,
        base_amount: finalAmountRounded,
        gst_rate: GST_RATE,
        gst_amount: gstAmount,
        currency: "INR",
        status: "order_created",
        coupon_id: couponId,
        coupon_code: couponCode,
        product_id: "hastveda_premium",
      })
      .select()
      .maybeSingle();

    if (orderError) {
      console.error("Failed to store order:", orderError);
      return new Response(
        JSON.stringify({ error: "Failed to create order record" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Create pending coupon redemption record ───────────────
    if (couponId && couponRecord) {
      await supabase.from("coupon_redemptions").insert({
        coupon_id: couponId,
        coupon_code: couponCode,
        user_id: user.id,
        order_id: orderRecord.id,
        original_amount: originalAmount,
        discount_amount: discountAmount,
        final_amount: finalAmountRounded,
        payment_status: "pending",
        campaign: couponRecord.campaign || null,
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        order_id: cashfreeOrderId,
        payment_session_id: paymentSessionId,
        final_amount: gstInclusiveAmount,
        original_amount: originalAmount,
        base_amount: finalAmountRounded,
        gst_rate: GST_RATE,
        gst_amount: gstAmount,
        discount_amount: discountAmount,
        currency: "INR",
        environment: CASHFREE_ENV,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("create-cashfree-order error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
