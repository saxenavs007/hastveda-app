// HastVeda Email Report Edge Function
// Sends the complete PDF report to the user's registered email address.
// Uses Resend for email delivery. PDF is generated server-side from saved report data.
// Security: Never exposes email credentials to client. Verifies user ownership.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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
    const resendApiKey = Deno.env.get("RESEND_API_KEY");

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

    const body = await req.json();
    const { report_id, locale = "en" } = body;

    if (!report_id) {
      return new Response(
        JSON.stringify({ error: "report_id is required", code: "MISSING_REPORT_ID" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Verify report ownership ─────────────────────────────────────────────
    const { data: reportRow, error: reportError } = await serviceClient
      .from("reports")
      .select("content, generated_at, created_at, user_id")
      .eq("id", report_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (reportError || !reportRow) {
      return new Response(
        JSON.stringify({ error: "Report not found or access denied.", code: "REPORT_NOT_FOUND" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Get user email and name ─────────────────────────────────────────────
    const userEmail = user.email;
    if (!userEmail) {
      return new Response(
        JSON.stringify({ error: "No email address on file.", code: "NO_EMAIL" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let userName = "";
    try {
      const { data: profile } = await serviceClient
        .from("user_profiles")
        .select("full_name")
        .eq("id", user.id)
        .maybeSingle();
      userName = profile?.full_name || "";
    } catch (_) {}

    // ── Check Resend API key ────────────────────────────────────────────────
    if (!resendApiKey) {
      console.error("[email-report] RESEND_API_KEY not configured");
      return new Response(
        JSON.stringify({
          error: "Email service not configured. Please contact support.",
          code: "EMAIL_NOT_CONFIGURED",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Generate PDF via pdf-export function ────────────────────────────────
    const pdfFunctionUrl = `${supabaseUrl}/functions/v1/pdf-export`;
    const pdfResponse = await fetch(pdfFunctionUrl, {
      method: "POST",
      headers: {
        "Authorization": authHeader,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        report_type: "detailed_report",
        report_id,
        locale,
      }),
    });

    if (!pdfResponse.ok) {
      let errMsg = "PDF generation failed.";
      try {
        const errData = await pdfResponse.json();
        errMsg = errData.error || errMsg;
      } catch (_) {}
      console.error("[email-report] PDF generation failed:", pdfResponse.status, errMsg);
      return new Response(
        JSON.stringify({ error: `Could not generate PDF: ${errMsg}`, code: "PDF_FAILED" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const pdfBytes = new Uint8Array(await pdfResponse.arrayBuffer());
    if (pdfBytes.length === 0) {
      return new Response(
        JSON.stringify({ error: "Generated PDF is empty.", code: "PDF_EMPTY" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Convert PDF to base64 for email attachment ──────────────────────────
    const pdfBase64 = btoa(String.fromCharCode(...pdfBytes));

    const isHindi = locale === "hi";
    const dateStr = new Date().toLocaleDateString(isHindi ? "hi-IN" : "en-IN", {
      day: "2-digit",
      month: "long",
      year: "numeric",
    });

    const filename = `hastveda-palm-report-${new Date().toISOString().split("T")[0]}.pdf`;
    const greeting = userName ? (isHindi ? `प्रिय ${userName}` : `Dear ${userName}`) : (isHindi ? "प्रिय उपयोगकर्ता" : "Dear HastVeda Member");

    const emailSubject = isHindi
      ? `HastVeda — आपकी विस्तृत हस्तरेखा रिपोर्ट`
      : `HastVeda — Your Detailed Palm Reading Report`;

    const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HastVeda Palm Reading Report</title>
</head>
<body style="margin:0;padding:0;background:#f5f0eb;font-family:Georgia,serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f0eb;padding:32px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
          <!-- Header -->
          <tr>
            <td style="background:#1A0F05;padding:32px 40px;text-align:center;">
              <h1 style="margin:0;color:#C77D2E;font-size:28px;font-family:Georgia,serif;letter-spacing:2px;">HastVeda</h1>
              <p style="margin:8px 0 0;color:#8B7355;font-size:13px;font-family:Arial,sans-serif;">Ancient Wisdom. Intelligent Insights.</p>
            </td>
          </tr>
          <!-- Gold bar -->
          <tr><td style="background:#C77D2E;height:3px;"></td></tr>
          <!-- Body -->
          <tr>
            <td style="padding:40px;">
              <p style="color:#5C4A38;font-size:16px;margin:0 0 16px;">${greeting},</p>
              <p style="color:#211408;font-size:15px;line-height:1.7;margin:0 0 20px;">
                ${isHindi
                  ? "आपकी विस्तृत हस्तरेखा रिपोर्ट तैयार है। यह रिपोर्ट आपके वास्तविक हस्तरेखा विश्लेषण से उत्पन्न की गई है और इसमें 19 व्यापक खंड शामिल हैं।"
                  : "Your Detailed Palm Reading Report is ready. This comprehensive report has been generated from your real palm analysis and includes 19 in-depth sections covering every aspect of your reading."
                }
              </p>
              <p style="color:#5C4A38;font-size:14px;line-height:1.6;margin:0 0 24px;">
                ${isHindi
                  ? "रिपोर्ट में शामिल है: कार्यकारी सारांश, व्यक्तित्व विश्लेषण, हस्तरेखा विश्लेषण, करियर, वित्त, प्रेम, स्वास्थ्य, और बहुत कुछ।"
                  : "The report covers: Executive Summary, Personality & Character, Head/Heart/Life/Fate Line Analysis, Career, Finance, Love & Relationships, Marriage, Health, Strengths, Challenges, Future Tendencies, Practical Guidance, and Final Guidance."
                }
              </p>
              <!-- CTA Box -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background:#FFF8F0;border:1px solid #EDE3D6;border-radius:8px;margin:0 0 24px;">
                <tr>
                  <td style="padding:20px;">
                    <p style="margin:0 0 8px;color:#8C4F10;font-size:13px;font-weight:bold;font-family:Arial,sans-serif;">📎 ${isHindi ? "संलग्न PDF" : "Attached PDF"}</p>
                    <p style="margin:0;color:#5C4A38;font-size:13px;font-family:Arial,sans-serif;">${filename}</p>
                    <p style="margin:8px 0 0;color:#8B7355;font-size:12px;font-family:Arial,sans-serif;">${isHindi ? "उत्पन्न:" : "Generated:"} ${dateStr}</p>
                  </td>
                </tr>
              </table>
              <p style="color:#8B7355;font-size:12px;line-height:1.6;margin:0 0 24px;font-style:italic;">
                ${isHindi
                  ? "अस्वीकरण: यह रिपोर्ट हस्तरेखा शास्त्र की पारंपरिक व्याख्या पर आधारित है। यह चिकित्सीय, कानूनी या वित्तीय सलाह नहीं है। केवल आत्म-चिंतन के लिए उपयोग करें।"
                  : "Disclaimer: This report is based on traditional palmistry interpretation. It is not medical, legal, or financial advice. Use for self-reflection and entertainment only."
                }
              </p>
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="background:#1A0F05;padding:24px 40px;text-align:center;">
              <p style="margin:0;color:#8B7355;font-size:12px;font-family:Arial,sans-serif;">© HastVeda — Ancient Wisdom. Intelligent Insights.</p>
              <p style="margin:8px 0 0;color:#5C4A38;font-size:11px;font-family:Arial,sans-serif;">hastveda.app</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

    // ── Send email via Resend ───────────────────────────────────────────────
    const resendPayload = {
      from: "HastVeda <reports@hastveda.co>",
      to: [userEmail],
      subject: emailSubject,
      html: emailHtml,
      attachments: [
        {
          filename,
          content: pdfBase64,
        },
      ],
    };

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(resendPayload),
    });

    if (!resendResponse.ok) {
      const resendError = await resendResponse.text();
      console.error("[email-report] Resend error:", resendResponse.status, resendError);
      return new Response(
        JSON.stringify({
          error: "Failed to send email. Please try again.",
          code: "EMAIL_SEND_FAILED",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const resendResult = await resendResponse.json();
    console.log("[email-report] Email sent successfully:", resendResult.id);

    return new Response(
      JSON.stringify({
        success: true,
        message: `Report sent to ${userEmail}`,
        email: userEmail,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("[email-report] Unexpected error:", err);
    return new Response(
      JSON.stringify({ error: err.message || "An unexpected error occurred.", code: "INTERNAL_ERROR" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
