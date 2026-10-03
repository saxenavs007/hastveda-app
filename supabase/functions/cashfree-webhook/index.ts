import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts";
import {
  createInvoiceIfNeeded,
  grantQuestionAllowance,
} from "../_shared/payment_fulfillment.ts";

async function settlePaidOrder(
  supabase: ReturnType<typeof createClient>,
  orderRecord: Record<string, unknown>,
  paymentId: string,
  isAskQuestion: boolean,
): Promise<void> {
  const userId = orderRecord.user_id as string;
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
    console.error("[cashfree-webhook] Question allowance grant failed:", err);
  }

  try {
    await createInvoiceIfNeeded(
      supabase,
      orderRecord,
      userProfile,
      paymentId,
      "[cashfree-webhook]",
    );
  } catch (invoiceErr) {
    console.error("[cashfree-webhook] Invoice creation failed (non-fatal):", invoiceErr);
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const CASHFREE_ENV = Deno.env.get("CASHFREE_ENV") ?? "production";
    const IS_SANDBOX = CASHFREE_ENV === "sandbox";
    const cashfreeSecretKey = IS_SANDBOX
      ? Deno.env.get("CASHFREE_SANDBOX_SECRET_KEY")!
      : Deno.env.get("CASHFREE_SECRET_KEY")!;

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── Webhook signature verification ────────────────────────
    const rawBody = await req.text();
    const skipSignatureCheck = Boolean(req.headers.get("x-test-mode")) ||
      Deno.env.get("ENVIRONMENT") === "development";

    if (skipSignatureCheck) {
      console.warn(
        "[cashfree-webhook] Signature check skipped for manual test request",
      );
    } else {
      const timestamp = req.headers.get("x-webhook-timestamp");
      const receivedSignature = req.headers.get("x-webhook-signature");

      if (!timestamp || !receivedSignature) {
        console.error("Missing webhook signature headers");
        return new Response("Unauthorized", { status: 401 });
      }

      const signatureData = `${timestamp}${rawBody}`;
      const expectedSignature = createHmac("sha256", cashfreeSecretKey)
        .update(signatureData)
        .digest("base64");

      if (expectedSignature !== receivedSignature) {
        console.error("Webhook signature mismatch");
        return new Response("Unauthorized", { status: 401 });
      }
    }

    // ── Parse webhook payload ─────────────────────────────────
    const payload = JSON.parse(rawBody);
    const eventType = payload.type;
    const orderData = payload.data?.order;
    const paymentData = payload.data?.payment;

    if (!orderData?.order_id) {
      return new Response("Invalid payload", { status: 400 });
    }

    const cashfreeOrderId = orderData.order_id;

    // ── Fetch our order record ────────────────────────────────
    const { data: orderRecord } = await supabase
      .from("cashfree_orders")
      .select("*")
      .eq("cashfree_order_id", cashfreeOrderId)
      .maybeSingle();

    if (!orderRecord) {
      console.error("Order not found for webhook:", cashfreeOrderId);
      return new Response("OK", { status: 200 });
    }

    // ── Determine product type from DB record ─────────────────
    const productId: string = orderRecord.product_id ?? "premium";
    const isAskQuestion = productId === "ask_question";

    // Already paid: credits and the GST email are idempotent, so a retry
    // still finishes a grant or invoice the first attempt missed.
    if (orderRecord.status === "payment_successful") {
      await settlePaidOrder(
        supabase,
        orderRecord,
        (orderRecord.payment_id as string) || cashfreeOrderId,
        isAskQuestion,
      );
      return new Response("OK", { status: 200 });
    }

    // ── Handle event types ────────────────────────────────────
    if (
      eventType === "PAYMENT_SUCCESS_WEBHOOK" ||
      paymentData?.payment_status === "SUCCESS"
    ) {
      const paymentId =
        paymentData?.cf_payment_id?.toString() ||
        paymentData?.payment_id?.toString() ||
        cashfreeOrderId;

      // Update order
      await supabase
        .from("cashfree_orders")
        .update({
          status: "payment_successful",
          payment_id: paymentId,
          paid_at: new Date().toISOString(),
          webhook_received_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", orderRecord.id);

      if (isAskQuestion) {
        console.log(`[cashfree-webhook] ask_question order paid: ${cashfreeOrderId} user=${orderRecord.user_id}`);

        const { data: existingQuestion } = await supabase
          .from("question_usage")
          .select("id, status, question_text, is_paid")
          .eq("payment_order_id", cashfreeOrderId)
          .eq("user_id", orderRecord.user_id)
          .maybeSingle();

        let questionId: string | null = null;

        if (existingQuestion) {
          await supabase
            .from("question_usage")
            .update({
              is_paid: true,
              status: "pending",
              updated_at: new Date().toISOString(),
            })
            .eq("id", existingQuestion.id);
          questionId = existingQuestion.id;
          console.log(`[cashfree-webhook] Marked existing question ${questionId} as paid`);
        } else {
          console.log(`[cashfree-webhook] No question_usage row for order ${cashfreeOrderId} — creating recovery record`);
          const { data: recoveryRow } = await supabase
            .from("question_usage")
            .insert({
              user_id: orderRecord.user_id,
              question_text: "",
              is_free: false,
              is_paid: true,
              payment_order_id: cashfreeOrderId,
              status: "payment_received_pending_question",
            })
            .select("id")
            .maybeSingle();
          questionId = recoveryRow?.id ?? null;
          console.log(`[cashfree-webhook] Created recovery record: ${questionId}`);
        }

        if (questionId && existingQuestion?.question_text) {
          try {
            const answerUrl = `${supabaseUrl}/functions/v1/answer-hastveda-question`;
            fetch(answerUrl, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${supabaseServiceKey}`,
                "x-internal-call": "cashfree-webhook",
              },
              body: JSON.stringify({
                question_usage_id: questionId,
                user_id: orderRecord.user_id,
              }),
            }).catch((e) => console.error("[cashfree-webhook] Failed to trigger answer function:", e));
          } catch (triggerError) {
            console.error("[cashfree-webhook] Error triggering answer function:", triggerError);
          }
        }

      } else {
        console.log(`[cashfree-webhook] Premium order paid: ${cashfreeOrderId} user=${orderRecord.user_id}`);

        await supabase.from("entitlements").upsert(
          {
            user_id: orderRecord.user_id,
            entitlement_type: "PREMIUM",
            is_active: true,
            granted_at: new Date().toISOString(),
            expires_at: null,
          },
          { onConflict: "user_id,entitlement_type", ignoreDuplicates: false }
        );

        await supabase
          .from("user_profiles")
          .update({ tier: "premium" })
          .eq("id", orderRecord.user_id);

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
      }

      orderRecord.paid_at = new Date().toISOString();
      orderRecord.payment_id = paymentId;
      await settlePaidOrder(supabase, orderRecord, paymentId, isAskQuestion);

    } else if (
      eventType === "PAYMENT_FAILED_WEBHOOK" ||
      paymentData?.payment_status === "FAILED"
    ) {
      await supabase
        .from("cashfree_orders")
        .update({
          status: "payment_failed",
          failure_reason: paymentData?.payment_message || "Payment failed",
          webhook_received_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", orderRecord.id);

      if (!isAskQuestion && orderRecord.coupon_id) {
        await supabase
          .from("coupon_redemptions")
          .update({ payment_status: "failed" })
          .eq("order_id", orderRecord.id)
          .eq("payment_status", "pending");
      }
    } else if (
      eventType === "PAYMENT_USER_DROPPED_WEBHOOK" ||
      paymentData?.payment_status === "USER_DROPPED"
    ) {
      await supabase
        .from("cashfree_orders")
        .update({
          status: "payment_cancelled",
          webhook_received_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", orderRecord.id);

      if (!isAskQuestion && orderRecord.coupon_id) {
        await supabase
          .from("coupon_redemptions")
          .update({ payment_status: "cancelled" })
          .eq("order_id", orderRecord.id)
          .eq("payment_status", "pending");
      }
    }

    return new Response("OK", { status: 200 });
  } catch (error) {
    console.error("cashfree-webhook error:", error);
    return new Response("Internal Server Error", { status: 500 });
  }
});
