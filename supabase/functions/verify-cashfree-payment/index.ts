import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createInvoiceIfNeeded,
  grantQuestionAllowance,
} from "../_shared/payment_fulfillment.ts";

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

async function fulfillPaidOrder(
  supabase: ReturnType<typeof createClient>,
  orderRecord: Record<string, unknown>,
  userId: string,
  paymentId: string,
  isAskQuestion: boolean,
): Promise<void> {
  const { data: userProfile } = await supabase
    .from("user_profiles")
    .select("full_name, email")
    .eq("id", userId)
    .maybeSingle();

  try {
    await grantQuestionAllowance(
      supabase,
      userId,
      orderRecord.cashfree_order_id as string,
      isAskQuestion,
    );
  } catch (err) {
    console.error("[verify-cashfree-payment] Question allowance grant failed:", err);
  }

  try {
    await createInvoiceIfNeeded(
      supabase,
      orderRecord,
      userProfile,
      paymentId,
      "[verify-cashfree-payment]",
    );
  } catch (err) {
    console.error("[verify-cashfree-payment] Invoice creation failed (non-fatal):", err);
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
    const cashfreeAppId = IS_SANDBOX
      ? Deno.env.get("CASHFREE_SANDBOX_APP_ID")!
      : Deno.env.get("CASHFREE_APP_ID")!;
    const cashfreeSecretKey = IS_SANDBOX
      ? Deno.env.get("CASHFREE_SANDBOX_SECRET_KEY")!
      : Deno.env.get("CASHFREE_SECRET_KEY")!;

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

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── Parse request ─────────────────────────────────────────
    const body = await req.json();
    const { cashfree_order_id } = body;
    if (!cashfree_order_id) {
      return new Response(
        JSON.stringify({ error: "cashfree_order_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Fetch our order record ────────────────────────────────
    const { data: orderRecord, error: orderFetchError } = await supabase
      .from("cashfree_orders")
      .select("*")
      .eq("cashfree_order_id", cashfree_order_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (orderFetchError || !orderRecord) {
      return new Response(
        JSON.stringify({ error: "Order not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Determine product type ────────────────────────────────
    const productId: string = orderRecord.product_id ?? "premium";
    const isAskQuestion = productId === "ask_question";

    // ── Idempotency: already successful ──────────────────────
    if (orderRecord.status === "payment_successful") {
      await fulfillPaidOrder(
        supabase,
        orderRecord,
        user.id,
        (orderRecord.payment_id as string) || cashfree_order_id,
        isAskQuestion,
      );
      if (isAskQuestion) {
        return new Response(
          JSON.stringify({
            success: true,
            status: "payment_successful",
            product_type: "ask_question",
            already_processed: true,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      return new Response(
        JSON.stringify({ success: true, status: "payment_successful", already_premium: true }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Verify with Cashfree server-side ──────────────────────
    const cashfreeResponse = await fetch(
      `${CASHFREE_BASE_URL}/orders/${cashfree_order_id}`,
      {
        method: "GET",
        headers: {
          Accept: "application/json",
          "x-client-id": cashfreeAppId,
          "x-client-secret": cashfreeSecretKey,
          "x-api-version": CASHFREE_API_VERSION,
        },
      }
    );

    if (!cashfreeResponse.ok) {
      console.error("Cashfree verification failed:", await cashfreeResponse.text());
      return new Response(
        JSON.stringify({ error: "Payment verification failed" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const cashfreeData = await cashfreeResponse.json();
    const orderStatus = cashfreeData.order_status;

    if (orderStatus !== "PAID") {
      const mappedStatus =
        orderStatus === "CANCELLED" ? "payment_cancelled" :
        orderStatus === "EXPIRED" ? "payment_failed" : "payment_pending";

      await supabase
        .from("cashfree_orders")
        .update({ status: mappedStatus, updated_at: new Date().toISOString() })
        .eq("id", orderRecord.id);

      if (!isAskQuestion && orderRecord.coupon_id) {
        await supabase
          .from("coupon_redemptions")
          .update({ payment_status: mappedStatus })
          .eq("order_id", orderRecord.id)
          .eq("payment_status", "pending");
      }

      return new Response(
        JSON.stringify({ success: false, status: mappedStatus, order_status: orderStatus }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Payment is PAID ───────────────────────────────────────
    const paymentId = cashfreeData.cf_order_id?.toString() || cashfree_order_id;

    // Update order record
    await supabase
      .from("cashfree_orders")
      .update({
        status: "payment_successful",
        payment_id: paymentId,
        paid_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", orderRecord.id);

    orderRecord.paid_at = new Date().toISOString();
    orderRecord.payment_id = paymentId;

    // ── ROUTING: ask_question vs premium ─────────────────────
    if (isAskQuestion) {
      console.log(`[verify-cashfree-payment] ask_question order paid: ${cashfree_order_id} user=${user.id}`);

      const { data: questionRow, error: questionFetchError } = await supabase
        .from("question_usage")
        .select("id, status, is_paid")
        .eq("payment_order_id", cashfree_order_id)
        .eq("user_id", user.id)
        .maybeSingle();

      if (questionFetchError) {
        console.error("[verify-cashfree-payment] Failed to fetch question_usage:", questionFetchError);
      }

      if (questionRow) {
        await supabase
          .from("question_usage")
          .update({
            is_paid: true,
            status: "pending",
            updated_at: new Date().toISOString(),
          })
          .eq("id", questionRow.id);

        try {
          const answerUrl = `${supabaseUrl}/functions/v1/answer-hastveda-question`;
          fetch(answerUrl, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${supabaseServiceKey}`,
              "x-internal-call": "verify-cashfree-payment",
            },
            body: JSON.stringify({
              question_usage_id: questionRow.id,
              user_id: user.id,
            }),
          }).catch((e) => console.error("[verify-cashfree-payment] Failed to trigger answer function:", e));
        } catch (triggerError) {
          console.error("[verify-cashfree-payment] Error triggering answer function:", triggerError);
        }
      } else {
        console.log(`[verify-cashfree-payment] No question_usage row found for order ${cashfree_order_id} — webhook recovery will handle it`);
      }

      await fulfillPaidOrder(supabase, orderRecord, user.id, paymentId, true);

      return new Response(
        JSON.stringify({
          success: true,
          status: "payment_successful",
          product_type: "ask_question",
          question_id: questionRow?.id ?? null,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── premium: grant Premium entitlement ───────────────────
    console.log(`[verify-cashfree-payment] Premium order paid: ${cashfree_order_id} user=${user.id}`);

    const { error: entitlementError } = await supabase
      .from("entitlements")
      .upsert(
        {
          user_id: user.id,
          entitlement_type: "PREMIUM",
          is_active: true,
          granted_at: new Date().toISOString(),
          expires_at: null,
        },
        { onConflict: "user_id,entitlement_type", ignoreDuplicates: false }
      );

    if (entitlementError) {
      const pgCode = (entitlementError as any).code ?? "unknown";
      const pgMsg = (entitlementError as any).message ?? String(entitlementError);
      console.error(
        `[verify-cashfree-payment] CRITICAL: entitlement upsert FAILED — code=${pgCode} message=${pgMsg}. Premium NOT granted for user=${user.id}`
      );
      return new Response(
        JSON.stringify({
          success: false,
          status: "entitlement_grant_failed",
          error: "Payment was received but Premium could not be activated. Please contact support with your order ID.",
          diagnostic: {
            cashfree_order_id,
            cashfree_status: "PAID",
            db_error_code: pgCode,
            db_error_message: pgMsg,
            user_id: user.id,
          },
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`[verify-cashfree-payment] Premium entitlement granted for user=${user.id}, order=${cashfree_order_id}`);

    // Update user profile tier
    await supabase
      .from("user_profiles")
      .update({ tier: "premium" })
      .eq("id", user.id);

    // Finalize coupon redemption
    if (orderRecord.coupon_id) {
      await supabase
        .from("coupon_redemptions")
        .update({
          payment_status: "success",
          redeemed_at: new Date().toISOString(),
        })
        .eq("order_id", orderRecord.id)
        .eq("payment_status", "pending");

      await supabase.rpc("increment_coupon_used_count", {
        p_coupon_id: orderRecord.coupon_id,
      });
    }

    await fulfillPaidOrder(supabase, orderRecord, user.id, paymentId, false);

    return new Response(
      JSON.stringify({ success: true, status: "payment_successful", premium_granted: true }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("verify-cashfree-payment error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
