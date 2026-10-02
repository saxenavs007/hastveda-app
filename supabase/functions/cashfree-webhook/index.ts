import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts";

// ── Invoice helper ────────────────────────────────────────────
async function createInvoiceIfNeeded(
  supabase: ReturnType<typeof createClient>,
  orderRecord: Record<string, unknown>,
  userProfile: { full_name?: string; email?: string } | null,
  paymentId: string
): Promise<void> {
  const cashfreeOrderId = orderRecord.cashfree_order_id as string;
  const orderId = orderRecord.id as string;

  const { data: existing } = await supabase
    .from("payment_invoices")
    .select("id")
    .eq("cashfree_order_id", cashfreeOrderId)
    .maybeSingle();

  if (existing) {
    console.log(`[cashfree-webhook] Invoice already exists for order ${cashfreeOrderId} — skipping`);
    return;
  }

  const now = new Date();
  const datePart = now.toISOString().slice(0, 10).replace(/-/g, "");
  const randomPart = Math.random().toString(36).substring(2, 8).toUpperCase();
  const invoiceNumber = `INV-${datePart}-${randomPart}`;

  const baseAmount = (orderRecord.base_amount as number) ?? (orderRecord.final_amount as number) ?? 0;
  const gstRate = (orderRecord.gst_rate as number) ?? 0.18;
  const gstAmount = (orderRecord.gst_amount as number) ?? Math.round(baseAmount * gstRate * 100) / 100;
  const totalAmount = (orderRecord.final_amount as number) ?? (baseAmount + gstAmount);
  const productId = (orderRecord.product_id as string) ?? "hastveda_premium";
  const description = productId === "ask_question"
    ? "HastVeda — Ask Question (Additional)"
    : "HastVeda Premium Access — Lifetime";

  const customerName = userProfile?.full_name ?? "HastVeda User";
  const customerEmail = userProfile?.email ?? "";

  const { data: invoice, error: insertError } = await supabase
    .from("payment_invoices")
    .insert({
      cashfree_order_id: cashfreeOrderId,
      cashfree_order_uuid: orderId,
      invoice_number: invoiceNumber,
      user_id: orderRecord.user_id as string,
      customer_name: customerName,
      customer_email: customerEmail,
      description,
      sac_code: "998314",
      base_amount: baseAmount,
      gst_rate: gstRate,
      gst_amount: gstAmount,
      total_amount: totalAmount,
      currency: "INR",
      payment_reference: paymentId,
      status: "generated",
    })
    .select("id, invoice_number")
    .maybeSingle();

  if (insertError) {
    if ((insertError as any).code === "23505") {
      console.log(`[cashfree-webhook] Invoice unique conflict for ${cashfreeOrderId} — already created`);
      return;
    }
    console.error(`[cashfree-webhook] Failed to insert invoice for ${cashfreeOrderId}:`, insertError);
    return;
  }

  console.log(`[cashfree-webhook] Invoice ${invoiceNumber} created for order ${cashfreeOrderId}`);

  if (!customerEmail) {
    console.warn(`[cashfree-webhook] No customer email for order ${cashfreeOrderId} — skipping email`);
    return;
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (!resendApiKey) {
    console.warn("[cashfree-webhook] RESEND_API_KEY not set — skipping invoice email");
    return;
  }

  const gstPercent = Math.round(gstRate * 100);
  const dateStr = now.toLocaleDateString("en-IN", { year: "numeric", month: "long", day: "numeric" });
  const emailHtml = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>HastVeda Invoice</title></head>
<body style="font-family: Arial, sans-serif; background: #f5f5f5; margin: 0; padding: 20px;">
  <div style="max-width: 600px; margin: 0 auto; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #2A1200, #D4A843); padding: 32px 24px; text-align: center;">
      <h1 style="color: #fff; margin: 0; font-size: 28px;">🔮 HastVeda</h1>
      <p style="color: rgba(255,255,255,0.8); margin: 8px 0 0;">Tax Invoice</p>
    </div>
    <div style="padding: 24px;">
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 24px;">
        <tr><td style="padding: 4px 0; color: #666; font-size: 13px;">Invoice Number</td><td style="padding: 4px 0; text-align: right; font-weight: bold; font-size: 13px;">${invoiceNumber}</td></tr>
        <tr><td style="padding: 4px 0; color: #666; font-size: 13px;">Date</td><td style="padding: 4px 0; text-align: right; font-size: 13px;">${dateStr}</td></tr>
        <tr><td style="padding: 4px 0; color: #666; font-size: 13px;">Customer</td><td style="padding: 4px 0; text-align: right; font-size: 13px;">${customerName}</td></tr>
        <tr><td style="padding: 4px 0; color: #666; font-size: 13px;">Order ID</td><td style="padding: 4px 0; text-align: right; font-size: 13px; color: #888;">${cashfreeOrderId}</td></tr>
      </table>
      <div style="background: #f9f9f9; border-radius: 8px; padding: 16px; margin-bottom: 16px;">
        <p style="margin: 0 0 8px; font-weight: bold; font-size: 14px; color: #333;">${description}</p>
        <p style="margin: 0; font-size: 12px; color: #888;">SAC Code: 998314</p>
      </div>
      <table style="width: 100%; border-collapse: collapse;">
        <tr><td style="padding: 8px 0; color: #555; font-size: 14px; border-top: 1px solid #eee;">Base Amount</td><td style="padding: 8px 0; text-align: right; font-size: 14px; border-top: 1px solid #eee;">₹${baseAmount.toFixed(2)}</td></tr>
        <tr><td style="padding: 8px 0; color: #555; font-size: 14px;">GST (${gstPercent}%)</td><td style="padding: 8px 0; text-align: right; font-size: 14px;">₹${gstAmount.toFixed(2)}</td></tr>
        <tr style="background: #fff8ee;"><td style="padding: 12px 8px; font-weight: bold; font-size: 16px; border-top: 2px solid #D4A843; color: #2A1200;">Total Paid</td><td style="padding: 12px 8px; text-align: right; font-weight: bold; font-size: 16px; border-top: 2px solid #D4A843; color: #D4A843;">₹${totalAmount.toFixed(2)}</td></tr>
      </table>
      <div style="margin-top: 24px; padding: 12px; background: #f0f8f0; border-radius: 8px; border-left: 3px solid #4caf50;">
        <p style="margin: 0; font-size: 13px; color: #2e7d32;">✅ Payment Confirmed — Reference: ${paymentId}</p>
      </div>
      <p style="margin-top: 24px; font-size: 12px; color: #aaa; text-align: center;">Thank you for choosing HastVeda. For support, contact us at support@hastveda.com</p>
    </div>
  </div>
</body>
</html>`;

  try {
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "HastVeda <noreply@hastveda.com>",
        to: [customerEmail],
        subject: `Your HastVeda Invoice ${invoiceNumber}`,
        html: emailHtml,
      }),
    });

    if (emailResponse.ok) {
      const emailData = await emailResponse.json();
      await supabase
        .from("payment_invoices")
        .update({
          resend_email_id: emailData.id ?? null,
          sent_at: new Date().toISOString(),
          status: "sent",
        })
        .eq("id", invoice!.id);
      console.log(`[cashfree-webhook] Invoice email sent to ${customerEmail}`);
    } else {
      const errText = await emailResponse.text();
      console.error(`[cashfree-webhook] Resend email failed: ${emailResponse.status} — ${errText}`);
    }
  } catch (emailErr) {
    console.error(`[cashfree-webhook] Email send threw exception:`, emailErr);
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

    // ── Idempotency: already processed ───────────────────────
    if (orderRecord.status === "payment_successful") {
      return new Response("OK", { status: 200 });
    }

    // ── Determine product type from DB record ─────────────────
    const productId: string = orderRecord.product_id ?? "premium";
    const isAskQuestion = productId === "ask_question";

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

      // Fetch user profile for invoice
      const { data: userProfile } = await supabase
        .from("user_profiles")
        .select("full_name, email")
        .eq("id", orderRecord.user_id)
        .maybeSingle();

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

      // Generate invoice (idempotent — safe to call from both verify and webhook)
      try {
        await createInvoiceIfNeeded(supabase, orderRecord, userProfile, paymentId);
      } catch (invoiceErr) {
        console.error("[cashfree-webhook] Invoice creation failed (non-fatal):", invoiceErr);
      }

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
