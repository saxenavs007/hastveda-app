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

// ── Invoice helper ────────────────────────────────────────────
async function createInvoiceIfNeeded(
  supabase: ReturnType<typeof createClient>,
  orderRecord: Record<string, unknown>,
  userProfile: { full_name?: string; email?: string } | null,
  paymentId: string
): Promise<void> {
  const cashfreeOrderId = orderRecord.cashfree_order_id as string;
  const orderId = orderRecord.id as string;

  // Idempotency: check if invoice already exists for this order
  const { data: existing } = await supabase
    .from("payment_invoices")
    .select("id, resend_email_id")
    .eq("cashfree_order_id", cashfreeOrderId)
    .maybeSingle();

  if (existing) {
    console.log(`[verify-cashfree-payment] Invoice already exists for order ${cashfreeOrderId} — skipping`);
    return;
  }

  // Generate invoice number: INV-YYYYMMDD-XXXXXX
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

  // Insert invoice record
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
    // 23505 = unique_violation — another concurrent call already inserted
    if ((insertError as any).code === "23505") {
      console.log(`[verify-cashfree-payment] Invoice unique conflict for ${cashfreeOrderId} — already created by concurrent call`);
      return;
    }
    console.error(`[verify-cashfree-payment] Failed to insert invoice for ${cashfreeOrderId}:`, insertError);
    return;
  }

  console.log(`[verify-cashfree-payment] Invoice ${invoiceNumber} created for order ${cashfreeOrderId}`);

  // Send invoice email via Resend
  if (!customerEmail) {
    console.warn(`[verify-cashfree-payment] No customer email for order ${cashfreeOrderId} — skipping email`);
    return;
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (!resendApiKey) {
    console.warn("[verify-cashfree-payment] RESEND_API_KEY not set — skipping invoice email");
    return;
  }

  const emailHtml = buildInvoiceEmailHtml({
    invoiceNumber,
    customerName,
    description,
    baseAmount,
    gstRate,
    gstAmount,
    totalAmount,
    paymentReference: paymentId,
    cashfreeOrderId,
    date: now.toLocaleDateString("en-IN", { year: "numeric", month: "long", day: "numeric" }),
  });

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
      const resendEmailId = emailData.id as string | undefined;
      // Update invoice with email ID and sent timestamp
      await supabase
        .from("payment_invoices")
        .update({
          resend_email_id: resendEmailId ?? null,
          sent_at: new Date().toISOString(),
          status: "sent",
        })
        .eq("id", invoice!.id);
      console.log(`[verify-cashfree-payment] Invoice email sent to ${customerEmail}, resend_id=${resendEmailId}`);
    } else {
      const errText = await emailResponse.text();
      console.error(`[verify-cashfree-payment] Resend email failed for ${cashfreeOrderId}: ${emailResponse.status} — ${errText}`);
    }
  } catch (emailErr) {
    console.error(`[verify-cashfree-payment] Email send threw exception for ${cashfreeOrderId}:`, emailErr);
  }
}

function buildInvoiceEmailHtml(params: {
  invoiceNumber: string;
  customerName: string;
  description: string;
  baseAmount: number;
  gstRate: number;
  gstAmount: number;
  totalAmount: number;
  paymentReference: string;
  cashfreeOrderId: string;
  date: string;
}): string {
  const gstPercent = Math.round(params.gstRate * 100);
  return `<!DOCTYPE html>
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
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Invoice Number</td>
          <td style="padding: 4px 0; text-align: right; font-weight: bold; font-size: 13px;">${params.invoiceNumber}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Date</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px;">${params.date}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Customer</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px;">${params.customerName}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Order ID</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px; color: #888;">${params.cashfreeOrderId}</td>
        </tr>
      </table>

      <div style="background: #f9f9f9; border-radius: 8px; padding: 16px; margin-bottom: 16px;">
        <p style="margin: 0 0 8px; font-weight: bold; font-size: 14px; color: #333;">${params.description}</p>
        <p style="margin: 0; font-size: 12px; color: #888;">SAC Code: 998314</p>
      </div>

      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="padding: 8px 0; color: #555; font-size: 14px; border-top: 1px solid #eee;">Base Amount</td>
          <td style="padding: 8px 0; text-align: right; font-size: 14px; border-top: 1px solid #eee;">₹${params.baseAmount.toFixed(2)}</td>
        </tr>
        <tr>
          <td style="padding: 8px 0; color: #555; font-size: 14px;">GST (${gstPercent}%)</td>
          <td style="padding: 8px 0; text-align: right; font-size: 14px;">₹${params.gstAmount.toFixed(2)}</td>
        </tr>
        <tr style="background: #fff8ee;">
          <td style="padding: 12px 8px; font-weight: bold; font-size: 16px; border-top: 2px solid #D4A843; color: #2A1200;">Total Paid</td>
          <td style="padding: 12px 8px; text-align: right; font-weight: bold; font-size: 16px; border-top: 2px solid #D4A843; color: #D4A843;">₹${params.totalAmount.toFixed(2)}</td>
        </tr>
      </table>

      <div style="margin-top: 24px; padding: 12px; background: #f0f8f0; border-radius: 8px; border-left: 3px solid #4caf50;">
        <p style="margin: 0; font-size: 13px; color: #2e7d32;">✅ Payment Confirmed — Reference: ${params.paymentReference}</p>
      </div>

      <p style="margin-top: 24px; font-size: 12px; color: #aaa; text-align: center;">
        Thank you for choosing HastVeda. For support, contact us at support@hastveda.com
      </p>
    </div>
  </div>
</body>
</html>`;
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

    // Fetch user profile for invoice
    const { data: userProfile } = await supabase
      .from("user_profiles")
      .select("full_name, email")
      .eq("id", user.id)
      .maybeSingle();

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

      // Generate invoice (idempotent)
      try {
        await createInvoiceIfNeeded(supabase, orderRecord, userProfile, paymentId);
      } catch (invoiceErr) {
        console.error("[verify-cashfree-payment] Invoice creation failed (non-fatal):", invoiceErr);
      }

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

    // Generate invoice (idempotent)
    try {
      await createInvoiceIfNeeded(supabase, orderRecord, userProfile, paymentId);
    } catch (invoiceErr) {
      console.error("[verify-cashfree-payment] Invoice creation failed (non-fatal):", invoiceErr);
    }

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
