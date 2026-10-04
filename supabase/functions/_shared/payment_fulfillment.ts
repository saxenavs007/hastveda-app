import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type SupabaseClient = ReturnType<typeof createClient>;

const PREMIUM_FREE_QUESTIONS = 2; // per IST month, while Premium is active
const TOPUP_QUESTION_CREDIT = 1; // one paid question, no monthly cap

export async function grantQuestionAllowance(
  supabase: SupabaseClient,
  userId: string,
  cashfreeOrderId: string,
  isAskQuestion: boolean,
): Promise<void> {
  const grantType = isAskQuestion ? "topup" : "premium_quota";
  const credits = isAskQuestion ? TOPUP_QUESTION_CREDIT : PREMIUM_FREE_QUESTIONS;
  const { error } = await supabase.rpc("grant_question_credits", {
    p_user_id: userId,
    p_cashfree_order_id: cashfreeOrderId,
    p_grant_type: grantType,
    p_credits: credits,
  });
  if (error) {
    console.error(
      `[question-credits] ${grantType} grant failed for order=${cashfreeOrderId}:`,
      error,
    );
    return;
  }
  console.log(
    `[question-credits] ${grantType} recorded (${credits}) for order=${cashfreeOrderId}`,
  );
}

export async function createInvoiceIfNeeded(
  supabase: SupabaseClient,
  orderRecord: Record<string, unknown>,
  userProfile: { full_name?: string; email?: string } | null,
  paymentId: string,
  logPrefix: string,
): Promise<void> {
  const cashfreeOrderId = orderRecord.cashfree_order_id as string;
  const orderId = orderRecord.id as string;
  const userId = orderRecord.user_id as string;

  let customerEmail = userProfile?.email ?? "";
  if (!customerEmail) {
    try {
      const { data: authUser } = await supabase.auth.admin.getUserById(userId);
      customerEmail = authUser.user?.email ?? "";
    } catch (err) {
      console.warn(`${logPrefix} Could not load auth email for ${userId}:`, err);
    }
  }

  const customerName = userProfile?.full_name || "HastVeda User";
  const paidAt = (orderRecord.paid_at as string | undefined) ?? new Date().toISOString();

  const { data: existing } = await supabase
    .from("payment_invoices")
    .select(
      "id, invoice_number, resend_email_id, customer_name, customer_email, description, base_amount, gst_rate, gst_amount, total_amount, payment_reference",
    )
    .eq("cashfree_order_id", cashfreeOrderId)
    .maybeSingle();

  if (existing?.resend_email_id) {
    console.log(`${logPrefix} Invoice already emailed for order ${cashfreeOrderId}`);
    return;
  }

  const now = new Date();
  const invoiceNumber = existing?.invoice_number as string | undefined ??
    `INV-${now.toISOString().slice(0, 10).replace(/-/g, "")}-${Math.random().toString(36).substring(2, 8).toUpperCase()}`;

  const baseAmount = numberOr(
    existing?.base_amount,
    (orderRecord.base_amount as number) ?? (orderRecord.final_amount as number) ?? 0,
  );
  const gstRate = numberOr(existing?.gst_rate, (orderRecord.gst_rate as number) ?? 0.18);
  const gstAmount = numberOr(
    existing?.gst_amount,
    (orderRecord.gst_amount as number) ?? Math.round(baseAmount * gstRate * 100) / 100,
  );
  const totalAmount = numberOr(
    existing?.total_amount,
    (orderRecord.final_amount as number) ?? baseAmount + gstAmount,
  );
  const productId = (orderRecord.product_id as string) ?? "hastveda_premium";
  const description = (existing?.description as string | undefined) ??
    (productId === "ask_question"
      ? "HastVeda — Ask Question (Additional)"
      : "HastVeda Premium Access — Lifetime");
  const paymentReference = (existing?.payment_reference as string | undefined) ?? paymentId;
  const emailTo = (existing?.customer_email as string | undefined) || customerEmail;
  const name = (existing?.customer_name as string | undefined) || customerName;

  let invoiceId = existing?.id as string | undefined;
  if (!existing) {
    const { data: invoice, error: insertError } = await supabase
      .from("payment_invoices")
      .insert({
        cashfree_order_id: cashfreeOrderId,
        cashfree_order_uuid: orderId,
        invoice_number: invoiceNumber,
        user_id: userId,
        customer_name: name,
        customer_email: emailTo,
        description,
        sac_code: "998314",
        base_amount: baseAmount,
        gst_rate: gstRate,
        gst_amount: gstAmount,
        total_amount: totalAmount,
        currency: "INR",
        payment_reference: paymentReference,
        status: "generated",
      })
      .select("id")
      .maybeSingle();

    if (insertError) {
      if ((insertError as { code?: string }).code === "23505") {
        // The other endpoint inserted the row first. Reuse it and send
        // only when that row has not been emailed yet.
        const { data: raced } = await supabase
          .from("payment_invoices")
          .select("id, resend_email_id")
          .eq("cashfree_order_id", cashfreeOrderId)
          .maybeSingle();
        if (!raced || raced.resend_email_id) {
          console.log(`${logPrefix} Invoice already recorded for ${cashfreeOrderId}`);
          return;
        }
        invoiceId = raced.id as string;
      } else {
        console.error(`${logPrefix} Failed to insert invoice for ${cashfreeOrderId}:`, insertError);
        return;
      }
    } else {
      invoiceId = invoice?.id as string | undefined;
      console.log(`${logPrefix} Invoice ${invoiceNumber} created for order ${cashfreeOrderId}`);
    }
  }

  if (!invoiceId) {
    console.error(`${logPrefix} Invoice row missing for ${cashfreeOrderId}`);
    return;
  }

  if (!emailTo) {
    console.warn(`${logPrefix} No customer email for order ${cashfreeOrderId} — skipping email`);
    return;
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (!resendApiKey) {
    console.warn(`${logPrefix} RESEND_API_KEY not set — skipping invoice email`);
    return;
  }

  const { data: claimed, error: claimError } = await supabase.rpc(
    "claim_invoice_send",
    { p_invoice_id: invoiceId },
  );
  if (claimError) {
    console.error(`${logPrefix} Invoice send claim failed for ${cashfreeOrderId}:`, claimError);
    return;
  }
  if (claimed !== true) {
    console.log(`${logPrefix} Invoice email already claimed for ${cashfreeOrderId}`);
    return;
  }

  const companyName = LEGAL_ENTITY_NAME;
  const companyGstin = LEGAL_ENTITY_GSTIN;
  const hastvedaLogoUrl = companyLogoUrl();
  const nestLogoUrl = valueNestLogoUrl();
  const [hastvedaLogo, valueNestLogo] = await Promise.all([
    fetchPublicLogo(hastvedaLogoUrl),
    fetchPublicLogo(nestLogoUrl),
  ]);

  const emailHtml = buildGstInvoiceHtml({
    invoiceNumber,
    customerName: name,
    customerEmail: emailTo,
    description,
    baseAmount,
    gstRate,
    gstAmount,
    totalAmount,
    paymentReference,
    cashfreeOrderId,
    paidAt,
    companyName,
    companyGstin,
    hastvedaLogoSrc: hastvedaLogo ? "cid:hastveda-logo" : hastvedaLogoUrl,
    valueNestLogoSrc: valueNestLogo ? "cid:valuenest-logo" : nestLogoUrl,
  });

  try {
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "HastVeda <noreply@hastveda.com>",
        to: [emailTo],
        subject: `GST Invoice ${invoiceNumber} — ${companyName}`,
        html: emailHtml,
        attachments: [
          ...(hastvedaLogo
            ? [{
              filename: "hastveda_logo.png",
              content: hastvedaLogo.base64,
              content_id: "hastveda-logo",
            }]
            : []),
          ...(valueNestLogo
            ? [{
              filename: "valuenest_logo.png",
              content: valueNestLogo.base64,
              content_id: "valuenest-logo",
            }]
            : []),
        ],
      }),
    });

    if (!emailResponse.ok) {
      const errText = await emailResponse.text();
      console.error(
        `${logPrefix} Resend email failed for ${cashfreeOrderId}: ${emailResponse.status} — ${errText}`,
      );
      await releaseInvoiceClaim(supabase, invoiceId);
      return;
    }

    const emailData = await emailResponse.json();
    if (invoiceId) {
      await supabase
        .from("payment_invoices")
        .update({
          resend_email_id: emailData.id ?? null,
          sent_at: new Date().toISOString(),
          status: "sent",
        })
        .eq("id", invoiceId);
    }
    console.log(
      `${logPrefix} GST invoice emailed to ${emailTo}, resend_id=${emailData.id}`,
    );
  } catch (emailErr) {
    console.error(`${logPrefix} Email send threw for ${cashfreeOrderId}:`, emailErr);
    await releaseInvoiceClaim(supabase, invoiceId);
  }
}

async function releaseInvoiceClaim(
  supabase: SupabaseClient,
  invoiceId: string,
): Promise<void> {
  const { error } = await supabase
    .from("payment_invoices")
    .update({ status: "generated", send_claimed_at: null })
    .eq("id", invoiceId)
    .is("resend_email_id", null);
  if (error) {
    console.error(`[gst-invoice] Failed to release send claim ${invoiceId}:`, error);
  }
}

const LEGAL_ENTITY_NAME = "ValueNest Technologies Private Limited";
const LEGAL_ENTITY_GSTIN = "08AAFCH6906C1ZR";

function publicAssetUrl(fileName: string): string {
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  return `${supabaseUrl}/storage/v1/object/public/public-assets/${fileName}`;
}

function companyLogoUrl(): string {
  const configured = Deno.env.get("COMPANY_LOGO_URL")?.trim();
  if (configured) return configured;
  return publicAssetUrl("hastveda_logo.png");
}

function valueNestLogoUrl(): string {
  const configured = Deno.env.get("VALUENEST_LOGO_URL")?.trim();
  if (configured) return configured;
  return publicAssetUrl("valuenest_logo.png");
}

async function fetchPublicLogo(
  logoUrl: string,
): Promise<{ base64: string } | null> {
  try {
    const response = await fetch(logoUrl);
    if (!response.ok) {
      console.warn(`[gst-invoice] Logo fetch failed ${response.status} from ${logoUrl}`);
      return null;
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0) return null;
    return { base64: bytesToBase64(bytes) };
  } catch (err) {
    console.warn(`[gst-invoice] Logo fetch error for ${logoUrl}:`, err);
    return null;
  }
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function numberOr(value: unknown, fallback: number): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function brandLogoRow(hastvedaSrc: string, valueNestSrc: string): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;border-collapse:collapse;">
      <tr>
        <td style="padding:0 16px;text-align:center;vertical-align:middle;">
          <img src="${escapeHtml(hastvedaSrc)}" alt="HastVeda" width="64" height="64" style="display:block;margin:0 auto;border-radius:8px;background:#ffffff;" />
          <div style="color:#D4A843;font-size:11px;margin-top:6px;letter-spacing:0.4px;">HastVeda</div>
        </td>
        <td style="width:1px;background:rgba(212,168,67,0.5);font-size:0;line-height:72px;">&nbsp;</td>
        <td style="padding:0 16px;text-align:center;vertical-align:middle;">
          <img src="${escapeHtml(valueNestSrc)}" alt="ValueNest" width="148" height="64" style="display:block;margin:0 auto;border-radius:8px;object-fit:contain;background:#071428;" />
          <div style="color:#ffffff;font-size:11px;margin-top:6px;letter-spacing:0.4px;">ValueNest</div>
        </td>
      </tr>
    </table>`;
}

function formatInr(amount: number): string {
  return `₹${amount.toFixed(2)}`;
}

function formatPaidAt(iso: string): string {
  const parsed = new Date(iso);
  const when = Number.isNaN(parsed.getTime()) ? new Date() : parsed;
  return when.toLocaleString("en-IN", {
    timeZone: "Asia/Kolkata",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}

function buildGstInvoiceHtml(params: {
  invoiceNumber: string;
  customerName: string;
  customerEmail: string;
  description: string;
  baseAmount: number;
  gstRate: number;
  gstAmount: number;
  totalAmount: number;
  paymentReference: string;
  cashfreeOrderId: string;
  paidAt: string;
  companyName: string;
  companyGstin: string;
  hastvedaLogoSrc: string;
  valueNestLogoSrc: string;
}): string {
  const gstPercent = Math.round(params.gstRate * 100);
  const companyName = escapeHtml(params.companyName);
  const companyGstin = escapeHtml(params.companyGstin);
  const customerName = escapeHtml(params.customerName);
  const customerEmail = escapeHtml(params.customerEmail);
  const description = escapeHtml(params.description);
  const paidAt = escapeHtml(formatPaidAt(params.paidAt));
  const logos = brandLogoRow(params.hastvedaLogoSrc, params.valueNestLogoSrc);

  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>GST Invoice ${escapeHtml(params.invoiceNumber)}</title></head>
<body style="font-family: Arial, sans-serif; background: #f5f5f5; margin: 0; padding: 20px;">
  <div style="max-width: 640px; margin: 0 auto; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: #1A0F05; padding: 28px 24px; text-align: center;">
      ${logos}
      <p style="color: #D4A843; margin: 18px 0 0; font-size: 11px; letter-spacing: 1.6px;">HASTVEDA IS A BRAND OF</p>
      <h1 style="color: #ffffff; margin: 8px 0 0; font-size: 22px; line-height: 1.3;">${companyName}</h1>
      <p style="color: #D4A843; margin: 10px 0 0; font-size: 15px; font-weight: bold; letter-spacing: 0.4px;">GSTIN: ${companyGstin}</p>
      <p style="color: rgba(255,255,255,0.7); margin: 8px 0 0; font-size: 12px; letter-spacing: 1px;">TAX INVOICE</p>
    </div>
    <div style="padding: 24px;">
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Invoice Number</td>
          <td style="padding: 4px 0; text-align: right; font-weight: bold; font-size: 13px;">${escapeHtml(params.invoiceNumber)}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Payment time (IST)</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px;">${paidAt}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Transaction ID</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px;">${escapeHtml(params.paymentReference)}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Order ID</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px; color: #888;">${escapeHtml(params.cashfreeOrderId)}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Customer</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px;">${customerName}</td>
        </tr>
        <tr>
          <td style="padding: 4px 0; color: #666; font-size: 13px;">Email</td>
          <td style="padding: 4px 0; text-align: right; font-size: 13px;">${customerEmail}</td>
        </tr>
      </table>

      <table style="width: 100%; border-collapse: collapse;">
        <tr style="background: #f7f1e8;">
          <th style="text-align: left; padding: 8px; font-size: 12px; color: #5C4A38;">Description</th>
          <th style="text-align: right; padding: 8px; font-size: 12px; color: #5C4A38;">Taxable value</th>
          <th style="text-align: right; padding: 8px; font-size: 12px; color: #5C4A38;">GST ${gstPercent}%</th>
          <th style="text-align: right; padding: 8px; font-size: 12px; color: #5C4A38;">Amount</th>
        </tr>
        <tr>
          <td style="padding: 10px 8px; font-size: 14px; color: #333; border-bottom: 1px solid #eee;">
            ${description}<br />
            <span style="font-size: 11px; color: #888;">SAC 998314</span>
          </td>
          <td style="padding: 10px 8px; text-align: right; font-size: 14px; border-bottom: 1px solid #eee;">${formatInr(params.baseAmount)}</td>
          <td style="padding: 10px 8px; text-align: right; font-size: 14px; border-bottom: 1px solid #eee;">${formatInr(params.gstAmount)}</td>
          <td style="padding: 10px 8px; text-align: right; font-size: 14px; border-bottom: 1px solid #eee;">${formatInr(params.totalAmount)}</td>
        </tr>
        <tr>
          <td colspan="3" style="padding: 8px; color: #555; font-size: 14px;">Base amount</td>
          <td style="padding: 8px; text-align: right; font-size: 14px;">${formatInr(params.baseAmount)}</td>
        </tr>
        <tr>
          <td colspan="3" style="padding: 8px; color: #555; font-size: 14px;">GST @ ${gstPercent}%</td>
          <td style="padding: 8px; text-align: right; font-size: 14px;">${formatInr(params.gstAmount)}</td>
        </tr>
        <tr style="background: #fff8ee;">
          <td colspan="3" style="padding: 12px 8px; font-weight: bold; font-size: 16px; color: #2A1200;">Total paid</td>
          <td style="padding: 12px 8px; text-align: right; font-weight: bold; font-size: 16px; color: #D4A843;">${formatInr(params.totalAmount)}</td>
        </tr>
      </table>

      <div style="margin-top: 28px; background: #1A0F05; border-radius: 10px; padding: 20px 16px; text-align: center;">
        ${logos}
        <p style="color: #ffffff; margin: 16px 0 0; font-size: 15px; font-weight: bold;">${companyName}</p>
        <p style="color: #D4A843; margin: 6px 0 0; font-size: 13px; font-weight: bold;">GSTIN: ${companyGstin}</p>
        <p style="color: rgba(255,255,255,0.75); margin: 8px 0 0; font-size: 12px;">
          Legal entity behind the HastVeda brand.
        </p>
      </div>
      <p style="margin-top: 16px; font-size: 12px; color: #888; text-align: center;">
        This is a computer-generated GST invoice issued by ${companyName} (GSTIN ${companyGstin}) for the HastVeda brand.
      </p>
    </div>
  </div>
</body>
</html>`;
}
