// HastVeda PDF Export Edge Function
// Generates a branded HastVeda PDF from SAVED report data in Supabase.
// Supports: detailed_report | couple_reading | palm_reading
// Security: Reads data server-side, enforces entitlement, never exposes Gemini key.
// Hindi support: Fetches Noto Sans Devanagari font for correct Unicode rendering.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, rgb, StandardFonts } from "npm:pdf-lib@1.17.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Brand colors (RGB 0-1) ────────────────────────────────────────────────────
const BRAND = {
  primary: rgb(0.78, 0.49, 0.18),      // #C77D2E — HastVeda gold
  primaryDark: rgb(0.55, 0.31, 0.06),  // #8C4F10
  dark: rgb(0.1, 0.06, 0.02),          // #1A0F05
  text: rgb(0.13, 0.08, 0.04),         // #211408
  subtext: rgb(0.36, 0.29, 0.22),      // #5C4A38
  light: rgb(0.98, 0.96, 0.93),        // #FAF5ED
  accent: rgb(0.98, 0.95, 0.88),       // #FAF2E0
  border: rgb(0.93, 0.89, 0.84),       // #EDE3D6
  success: rgb(0.13, 0.55, 0.33),      // #218C54
  warning: rgb(0.8, 0.5, 0.1),         // #CC8019
  white: rgb(1, 1, 1),
  disclaimer: rgb(0.55, 0.47, 0.38),   // #8C7860
};

// ── Page dimensions (A4) ──────────────────────────────────────────────────────
const PAGE_W = 595;
const PAGE_H = 842;
const MARGIN = 48;
const CONTENT_W = PAGE_W - MARGIN * 2;

// ── Font cache ────────────────────────────────────────────────────────────────
let _notoFontBytes: Uint8Array | null = null;

async function fetchNotoDevanagariFont(): Promise<Uint8Array | null> {
  if (_notoFontBytes) return _notoFontBytes;
  try {
    // Google Fonts CDN — NotoSansDevanagari-Regular subset
    const url =
      "https://fonts.gstatic.com/s/notosansdevanagari/v25/TuGOUUFzXI5FBtUq5a8bjKYTZjtgoo-_Sn0.woff2";
    const res = await fetch(url);
    if (!res.ok) return null;
    const buf = await res.arrayBuffer();
    _notoFontBytes = new Uint8Array(buf);
    return _notoFontBytes;
  } catch {
    return null;
  }
}

// ── Text wrapping helper ──────────────────────────────────────────────────────
function wrapText(text: string, maxCharsPerLine: number): string[] {
  if (!text) return [];
  const words = text.split(" ");
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    if ((current + " " + word).trim().length <= maxCharsPerLine) {
      current = (current + " " + word).trim();
    } else {
      if (current) lines.push(current);
      // Handle very long words
      if (word.length > maxCharsPerLine) {
        let remaining = word;
        while (remaining.length > maxCharsPerLine) {
          lines.push(remaining.slice(0, maxCharsPerLine));
          remaining = remaining.slice(maxCharsPerLine);
        }
        current = remaining;
      } else {
        current = word;
      }
    }
  }
  if (current) lines.push(current);
  return lines;
}

// ── Draw a horizontal rule ────────────────────────────────────────────────────
function drawRule(page: any, y: number, color = BRAND.border, thickness = 0.5) {
  page.drawLine({
    start: { x: MARGIN, y },
    end: { x: PAGE_W - MARGIN, y },
    thickness,
    color,
  });
}

// ── Draw page header (logo area + brand name) ─────────────────────────────────
function drawPageHeader(page: any, font: any, boldFont: any, pageNum: number, totalPages: number) {
  // Header background
  page.drawRectangle({
    x: 0,
    y: PAGE_H - 60,
    width: PAGE_W,
    height: 60,
    color: BRAND.dark,
  });

  // Brand name
  page.drawText("HastVeda", {
    x: MARGIN,
    y: PAGE_H - 38,
    size: 20,
    font: boldFont,
    color: BRAND.primary,
  });

  // Tagline
  page.drawText("Palm Reading Report", {
    x: MARGIN,
    y: PAGE_H - 52,
    size: 9,
    font,
    color: rgb(0.7, 0.6, 0.5),
  });

  // Page number
  const pageStr = `${pageNum} / ${totalPages}`;
  page.drawText(pageStr, {
    x: PAGE_W - MARGIN - pageStr.length * 5,
    y: PAGE_H - 38,
    size: 9,
    font,
    color: rgb(0.6, 0.5, 0.4),
  });
}

// ── Draw page footer ──────────────────────────────────────────────────────────
function drawPageFooter(page: any, font: any, isHindi: boolean) {
  page.drawRectangle({
    x: 0,
    y: 0,
    width: PAGE_W,
    height: 28,
    color: BRAND.dark,
  });
  const footerText = isHindi
    ? "HastVeda — पारंपरिक हस्तरेखा व्याख्या | केवल मनोरंजन एवं आत्म-चिंतन हेतु"
    : "HastVeda — Traditional Palmistry Interpretation | For entertainment & self-reflection only";
  page.drawText(footerText.slice(0, 90), {
    x: MARGIN,
    y: 10,
    size: 7,
    font,
    color: rgb(0.5, 0.4, 0.3),
  });
}

// ── Draw a section title bar ──────────────────────────────────────────────────
function drawSectionTitle(
  page: any,
  boldFont: any,
  title: string,
  y: number,
  emoji: string = ""
): number {
  page.drawRectangle({
    x: MARGIN,
    y: y - 18,
    width: CONTENT_W,
    height: 24,
    color: BRAND.accent,
    borderColor: BRAND.primary,
    borderWidth: 0.5,
  });
  const displayTitle = `${emoji} ${title}`.trim();
  page.drawText(displayTitle.slice(0, 70), {
    x: MARGIN + 8,
    y: y - 12,
    size: 11,
    font: boldFont,
    color: BRAND.primaryDark,
  });
  return y - 30;
}

// ── Draw body text with wrapping, returns new Y ───────────────────────────────
function drawBodyText(
  page: any,
  font: any,
  text: string,
  startY: number,
  fontSize = 9,
  color = BRAND.subtext,
  maxChars = 90
): number {
  if (!text) return startY;
  const lines = wrapText(text, maxChars);
  let y = startY;
  for (const line of lines) {
    if (y < 50) break;
    page.drawText(line, { x: MARGIN, y, size: fontSize, font, color });
    y -= fontSize + 3;
  }
  return y - 4;
}

// ── Draw bullet list, returns new Y ──────────────────────────────────────────
function drawBulletList(
  page: any,
  font: any,
  items: string[],
  startY: number,
  color = BRAND.subtext
): number {
  let y = startY;
  for (const item of items) {
    if (y < 50) break;
    page.drawCircle({ x: MARGIN + 6, y: y + 3, size: 2, color: BRAND.primary });
    const lines = wrapText(item, 85);
    for (let i = 0; i < lines.length; i++) {
      if (y < 50) break;
      page.drawText(lines[i], {
        x: MARGIN + 14,
        y,
        size: 9,
        font,
        color,
      });
      y -= 13;
    }
    y -= 2;
  }
  return y - 4;
}

// ── Score bar ─────────────────────────────────────────────────────────────────
function drawScoreBar(
  page: any,
  font: any,
  boldFont: any,
  label: string,
  score: number,
  y: number
): number {
  const barW = CONTENT_W - 80;
  const filled = Math.round((score / 100) * barW);
  const barColor = score >= 80 ? BRAND.success : score >= 60 ? BRAND.primary : BRAND.warning;

  page.drawText(label.slice(0, 22), { x: MARGIN, y, size: 9, font, color: BRAND.subtext });
  page.drawRectangle({ x: MARGIN + 80, y: y - 2, width: barW, height: 8, color: BRAND.border });
  if (filled > 0) {
    page.drawRectangle({ x: MARGIN + 80, y: y - 2, width: filled, height: 8, color: barColor });
  }
  page.drawText(`${score}%`, {
    x: MARGIN + 80 + barW + 6,
    y,
    size: 9,
    font: boldFont,
    color: barColor,
  });
  return y - 18;
}

// ── Cover page ────────────────────────────────────────────────────────────────
function buildCoverPage(
  pdfDoc: PDFDocument,
  font: any,
  boldFont: any,
  title: string,
  subtitle: string,
  dateStr: string,
  isHindi: boolean
) {
  const page = pdfDoc.addPage([PAGE_W, PAGE_H]);

  // Dark background header
  page.drawRectangle({ x: 0, y: PAGE_H - 200, width: PAGE_W, height: 200, color: BRAND.dark });

  // Gold accent bar
  page.drawRectangle({ x: 0, y: PAGE_H - 202, width: PAGE_W, height: 3, color: BRAND.primary });

  // Brand name large
  page.drawText("HastVeda", { x: MARGIN, y: PAGE_H - 80, size: 36, font: boldFont, color: BRAND.primary });

  // Tagline
  const tagline = isHindi ? "हस्तरेखा शास्त्र की पारंपरिक व्याख्या" : "Traditional Palm Reading Interpretation";
  page.drawText(tagline.slice(0, 60), { x: MARGIN, y: PAGE_H - 105, size: 12, font, color: rgb(0.7, 0.6, 0.5) });

  // Decorative line
  page.drawLine({
    start: { x: MARGIN, y: PAGE_H - 120 },
    end: { x: PAGE_W - MARGIN, y: PAGE_H - 120 },
    thickness: 0.5,
    color: BRAND.primary,
  });

  // Report type badge
  page.drawRectangle({
    x: MARGIN,
    y: PAGE_H - 160,
    width: 120,
    height: 20,
    color: BRAND.primary,
  });
  const badgeText = isHindi ? "प्रीमियम रिपोर्ट" : "PREMIUM REPORT";
  page.drawText(badgeText.slice(0, 18), { x: MARGIN + 8, y: PAGE_H - 153, size: 9, font: boldFont, color: BRAND.white });

  // Report title
  page.drawText(title.slice(0, 55), { x: MARGIN, y: PAGE_H - 280, size: 22, font: boldFont, color: BRAND.text });

  // Subtitle
  const subLines = wrapText(subtitle, 70);
  let sy = PAGE_H - 310;
  for (const line of subLines) {
    page.drawText(line, { x: MARGIN, y: sy, size: 12, font, color: BRAND.subtext });
    sy -= 18;
  }

  // Date
  const dateLabel = isHindi ? `उत्पन्न: ${dateStr}` : `Generated: ${dateStr}`;
  page.drawText(dateLabel, { x: MARGIN, y: PAGE_H - 380, size: 10, font, color: BRAND.subtext });

  // Decorative divider
  drawRule(page, PAGE_H - 400, BRAND.primary, 1);

  // AI badge
  const aiBadge = isHindi ? "✦ Gemini AI द्वारा वास्तविक हस्तरेखा विश्लेषण" : "✦ Real palm analysis powered by Gemini AI";
  page.drawText(aiBadge.slice(0, 65), { x: MARGIN, y: PAGE_H - 420, size: 10, font, color: BRAND.primary });

  // Disclaimer box
  page.drawRectangle({
    x: MARGIN,
    y: 80,
    width: CONTENT_W,
    height: 70,
    color: BRAND.accent,
    borderColor: BRAND.border,
    borderWidth: 0.5,
  });
  const disc1 = isHindi
    ? "अस्वीकरण: यह रिपोर्ट हस्तरेखा शास्त्र की पारंपरिक/आध्यात्मिक व्याख्या पर आधारित है।"
    : "Disclaimer: This report is based on traditional/spiritual palmistry interpretation.";
  const disc2 = isHindi
    ? "यह वैज्ञानिक रूप से सिद्ध भविष्यवाणी नहीं है। चिकित्सीय, कानूनी या वित्तीय सलाह नहीं।"
    : "It is not scientifically proven prediction. Not medical, legal, or financial advice.";
  const disc3 = isHindi
    ? "केवल आत्म-चिंतन एवं मनोरंजन के लिए उपयोग करें।"
    : "Use for self-reflection and entertainment purposes only.";
  page.drawText(disc1.slice(0, 85), { x: MARGIN + 8, y: 135, size: 8, font, color: BRAND.disclaimer });
  page.drawText(disc2.slice(0, 85), { x: MARGIN + 8, y: 122, size: 8, font, color: BRAND.disclaimer });
  page.drawText(disc3.slice(0, 85), { x: MARGIN + 8, y: 109, size: 8, font, color: BRAND.disclaimer });

  // Footer
  page.drawRectangle({ x: 0, y: 0, width: PAGE_W, height: 28, color: BRAND.dark });
  page.drawText("hastveda.app", { x: MARGIN, y: 10, size: 8, font, color: rgb(0.5, 0.4, 0.3) });
}

// ── Build Detailed Report PDF ─────────────────────────────────────────────────
async function buildDetailedReportPdf(
  reportData: any,
  locale: string,
  generatedAt: string
): Promise<Uint8Array> {
  const isHindi = locale === "hi";
  const pdfDoc = await PDFDocument.create();

  // Embed fonts
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  const dateStr = generatedAt
    ? new Date(generatedAt).toLocaleDateString(isHindi ? "hi-IN" : "en-IN", {
        day: "2-digit",
        month: "long",
        year: "numeric",
      })
    : new Date().toLocaleDateString("en-IN");

  const title = isHindi ? "विस्तृत हस्तरेखा रिपोर्ट" : "Detailed Palm Reading Report";
  const subtitle = isHindi
    ? "आपके वास्तविक हस्तरेखा विश्लेषण से उत्पन्न व्यक्तिगत रिपोर्ट"
    : "Personalized report generated from your real palm analysis";

  // Cover page
  buildCoverPage(pdfDoc, font, boldFont, title, subtitle, dateStr, isHindi);

  // Section definitions
  const sections = [
    { key: "overall_overview", emoji: "🌿", titleEn: "Overall Palm Overview", titleHi: "समग्र हस्तरेखा अवलोकन", highlightsKey: "key_highlights" },
    { key: "personality_character", emoji: "🧠", titleEn: "Personality & Character", titleHi: "व्यक्तित्व और चरित्र", highlightsKey: "traits" },
    { key: "life_vitality", emoji: "✋", titleEn: "Life & Vitality", titleHi: "जीवन और जीवन शक्ति", highlightsKey: "observations" },
    { key: "mind_intelligence", emoji: "💡", titleEn: "Mind & Intelligence", titleHi: "मन और बुद्धि", highlightsKey: "observations" },
    { key: "emotions_relationships", emoji: "❤️", titleEn: "Emotions & Relationships", titleHi: "भावनाएं और रिश्ते", highlightsKey: "observations" },
    { key: "career_professional", emoji: "💼", titleEn: "Career & Professional Tendencies", titleHi: "करियर और पेशेवर प्रवृत्तियां", highlightsKey: "observations" },
    { key: "finance_wealth", emoji: "💰", titleEn: "Finance & Wealth Tendencies", titleHi: "वित्त और धन प्रवृत्तियां", highlightsKey: "observations" },
    { key: "important_observations", emoji: "⭐", titleEn: "Important Observations", titleHi: "महत्वपूर्ण अवलोकन", highlightsKey: "observations" },
    { key: "key_strengths", emoji: "💪", titleEn: "Key Strengths", titleHi: "प्रमुख शक्तियां", highlightsKey: "strengths" },
    { key: "areas_mindful", emoji: "🌱", titleEn: "Areas to Be Mindful Of", titleHi: "सावधान रहने के क्षेत्र", highlightsKey: "areas" },
  ];

  // Estimate total pages (rough)
  const totalPages = Math.ceil(sections.length / 3) + 3;

  let pageNum = 1;
  let page = pdfDoc.addPage([PAGE_W, PAGE_H]);
  pageNum++;
  drawPageHeader(page, font, boldFont, pageNum, totalPages);
  drawPageFooter(page, font, isHindi);
  let y = PAGE_H - 80;

  // Report header on first content page
  page.drawText(title, { x: MARGIN, y, size: 18, font: boldFont, color: BRAND.text });
  y -= 22;
  page.drawText(dateStr, { x: MARGIN, y, size: 10, font, color: BRAND.subtext });
  y -= 8;
  drawRule(page, y, BRAND.primary, 1.5);
  y -= 20;

  const addNewPage = () => {
    page = pdfDoc.addPage([PAGE_W, PAGE_H]);
    pageNum++;
    drawPageHeader(page, font, boldFont, pageNum, totalPages);
    drawPageFooter(page, font, isHindi);
    y = PAGE_H - 80;
  };

  // Render each section
  for (const sec of sections) {
    const sectionData = reportData[sec.key] as any;
    if (!sectionData) continue;

    const sectionTitle = sectionData.title || (isHindi ? sec.titleHi : sec.titleEn);
    const content = (sectionData.content as string) || "";
    const highlights = ((sectionData[sec.highlightsKey] as string[]) || []).slice(0, 8);
    const score = sectionData.score as number | undefined;

    // Estimate space needed
    const contentLines = wrapText(content, 90).length;
    const spaceNeeded = 40 + contentLines * 13 + highlights.length * 15 + 20;
    if (y - spaceNeeded < 60) addNewPage();

    y = drawSectionTitle(page, boldFont, sectionTitle, y);
    y -= 6;

    if (score !== undefined) {
      y = drawScoreBar(page, font, boldFont, isHindi ? "स्कोर" : "Score", score, y);
    }

    if (content) {
      // Strip markdown bold markers for PDF
      const cleanContent = content.replace(/\*\*/g, "");
      y = drawBodyText(page, font, cleanContent, y);
    }

    if (highlights.length > 0) {
      y -= 4;
      y = drawBulletList(page, font, highlights, y);
    }

    y -= 12;
    if (y < 80) addNewPage();
  }

  // Major Palm Lines section
  const palmLines = reportData["major_palm_lines"] as any;
  if (palmLines) {
    const linesTitle = palmLines.title || (isHindi ? "प्रमुख हस्तरेखाएं" : "Major Palm Lines");
    const linesContent = (palmLines.content as string) || "";
    const lines = ((palmLines.lines as any[]) || []).slice(0, 6);

    const spaceNeeded = 40 + wrapText(linesContent, 90).length * 13 + lines.length * 30;
    if (y - spaceNeeded < 80) addNewPage();

    y = drawSectionTitle(page, boldFont, linesTitle, y, "🔍");
    y -= 6;
    if (linesContent) {
      y = drawBodyText(page, font, linesContent.replace(/\*\*/g, ""), y);
    }
    for (const line of lines) {
      if (y < 80) addNewPage();
      const lineName = (line.name as string) || "";
      const lineDesc = (line.description as string) || "";
      const visible = line.visible as boolean;
      const dotColor = visible ? BRAND.success : BRAND.warning;
      page.drawCircle({ x: MARGIN + 6, y: y + 3, size: 4, color: dotColor });
      page.drawText(lineName.slice(0, 30), { x: MARGIN + 16, y, size: 9, font: boldFont, color: BRAND.text });
      y -= 13;
      if (lineDesc) {
        y = drawBodyText(page, font, lineDesc.replace(/\*\*/g, ""), y, 8, BRAND.subtext, 88);
      }
      y -= 4;
    }
    y -= 12;
  }

  // Reading Summary section
  const summary = reportData["reading_summary"] as any;
  if (summary) {
    const summaryTitle = summary.title || (isHindi ? "समग्र पठन सारांश" : "Overall Reading Summary");
    const summaryContent = (summary.content as string) || "";
    const closingNote = (summary.closing_note as string) || "";

    const spaceNeeded = 60 + wrapText(summaryContent, 90).length * 13 + wrapText(closingNote, 85).length * 13;
    if (y - spaceNeeded < 80) addNewPage();

    y = drawSectionTitle(page, boldFont, summaryTitle, y, "📋");
    y -= 6;
    if (summaryContent) {
      y = drawBodyText(page, font, summaryContent.replace(/\*\*/g, ""), y);
    }
    if (closingNote) {
      y -= 6;
      page.drawRectangle({ x: MARGIN, y: y - 4, width: CONTENT_W, height: wrapText(closingNote, 85).length * 14 + 12, color: BRAND.accent });
      y = drawBodyText(page, font, closingNote, y - 2, 9, BRAND.primaryDark, 85);
    }
    y -= 12;
  }

  // Disclaimer page
  if (y < 150) addNewPage();
  y -= 10;
  drawRule(page, y, BRAND.primary, 1);
  y -= 20;
  const discTitle = isHindi ? "महत्वपूर्ण अस्वीकरण" : "Important Disclaimer";
  page.drawText(discTitle, { x: MARGIN, y, size: 12, font: boldFont, color: BRAND.primaryDark });
  y -= 18;
  const discText = isHindi
    ? "यह रिपोर्ट हस्तरेखा शास्त्र की पारंपरिक एवं आध्यात्मिक व्याख्या पर आधारित है। Gemini AI ने वास्तविक हथेली की विशेषताओं का विश्लेषण किया है, परंतु हस्तरेखा शास्त्र वैज्ञानिक रूप से सिद्ध नहीं है। इसे वैज्ञानिक तथ्य के रूप में न लें। यह चिकित्सीय, कानूनी, मनोवैज्ञानिक या वित्तीय सलाह नहीं है। इसे केवल आत्म-चिंतन, व्यक्तिगत अन्वेषण एवं मनोरंजन के लिए उपयोग करें।"
    : "This report is based on traditional and spiritual palmistry interpretation. Gemini AI analyzed actual palm features, but palmistry is not scientifically proven. Do not treat this as scientific fact. This is not medical, legal, psychological, or financial advice. Use it only for self-reflection, personal exploration, and entertainment.";
  y = drawBodyText(page, font, discText, y, 9, BRAND.disclaimer, 88);

  // Update total pages in all headers (approximate — pdf-lib doesn't support this natively, so we accept the estimate)
  const bytes = await pdfDoc.save();
  return bytes;
}

// ── Build Couple Reading PDF ──────────────────────────────────────────────────
async function buildCoupleReadingPdf(
  compatibility: any,
  locale: string
): Promise<Uint8Array> {
  const isHindi = locale === "hi";
  const pdfDoc = await PDFDocument.create();
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  const person1Name = (compatibility.person1_name as string) || (isHindi ? "व्यक्ति १" : "Person 1");
  const person2Name = (compatibility.person2_name as string) || (isHindi ? "व्यक्ति २" : "Person 2");
  const overallScore = (compatibility.overall_compatibility_score as number) || 75;
  const createdAt = (compatibility.created_at as string) || new Date().toISOString();

  const t = (enKey: string, hiKey: string): string => {
    const en = (compatibility[enKey] as string) || "";
    const hi = (compatibility[hiKey] as string) || "";
    return isHindi && hi ? hi : en;
  };
  const tList = (enKey: string, hiKey: string): string[] => {
    const en = ((compatibility[enKey] as string[]) || []);
    const hi = ((compatibility[hiKey] as string[]) || []);
    return isHindi && hi.length > 0 ? hi : en;
  };

  const dateStr = new Date(createdAt).toLocaleDateString(isHindi ? "hi-IN" : "en-IN", {
    day: "2-digit", month: "long", year: "numeric",
  });

  const title = isHindi
    ? `${person1Name} & ${person2Name} — युगल पठन`
    : `${person1Name} & ${person2Name} — Couple Reading`;
  const subtitle = isHindi
    ? "Gemini AI द्वारा वास्तविक हस्तरेखा विश्लेषण पर आधारित अनुकूलता रिपोर्ट"
    : "Compatibility report based on real palm analysis by Gemini AI";

  // Cover page
  buildCoverPage(pdfDoc, font, boldFont, title, subtitle, dateStr, isHindi);

  let pageNum = 1;
  let page = pdfDoc.addPage([PAGE_W, PAGE_H]);
  pageNum++;
  const totalPages = 5;
  drawPageHeader(page, font, boldFont, pageNum, totalPages);
  drawPageFooter(page, font, isHindi);
  let y = PAGE_H - 80;

  const addNewPage = () => {
    page = pdfDoc.addPage([PAGE_W, PAGE_H]);
    pageNum++;
    drawPageHeader(page, font, boldFont, pageNum, totalPages);
    drawPageFooter(page, font, isHindi);
    y = PAGE_H - 80;
  };

  // Report title
  page.drawText(title.slice(0, 60), { x: MARGIN, y, size: 16, font: boldFont, color: BRAND.text });
  y -= 20;
  page.drawText(dateStr, { x: MARGIN, y, size: 10, font, color: BRAND.subtext });
  y -= 8;
  drawRule(page, y, BRAND.primary, 1.5);
  y -= 20;

  // Overall score
  const scoreLabel = isHindi ? `समग्र अनुकूलता: ${overallScore}%` : `Overall Compatibility: ${overallScore}%`;
  page.drawText(scoreLabel, { x: MARGIN, y, size: 14, font: boldFont, color: BRAND.primary });
  y -= 20;

  // Overview
  const overview = t("overview_en", "overview_hi");
  if (overview) {
    y = drawSectionTitle(page, boldFont, isHindi ? "रिश्ते का अवलोकन" : "Relationship Overview", y, "🔮");
    y -= 6;
    y = drawBodyText(page, font, overview.replace(/\*\*/g, ""), y);
    y -= 12;
  }

  // Person 1 observations
  const p1obs = t("person1_observations_en", "person1_observations_hi");
  const p1traits = tList("person1_key_traits_en", "person1_key_traits_hi");
  if (p1obs || p1traits.length > 0) {
    if (y < 120) addNewPage();
    y = drawSectionTitle(page, boldFont, `${isHindi ? "हथेली अवलोकन" : "Palm Observations"} — ${person1Name}`, y, "🖐️");
    y -= 6;
    if (p1obs) y = drawBodyText(page, font, p1obs.replace(/\*\*/g, ""), y);
    if (p1traits.length > 0) {
      y -= 4;
      y = drawBulletList(page, font, p1traits.slice(0, 6), y);
    }
    y -= 12;
  }

  // Person 2 observations
  const p2obs = t("person2_observations_en", "person2_observations_hi");
  const p2traits = tList("person2_key_traits_en", "person2_key_traits_hi");
  if (p2obs || p2traits.length > 0) {
    if (y < 120) addNewPage();
    y = drawSectionTitle(page, boldFont, `${isHindi ? "हथेली अवलोकन" : "Palm Observations"} — ${person2Name}`, y, "🖐️");
    y -= 6;
    if (p2obs) y = drawBodyText(page, font, p2obs.replace(/\*\*/g, ""), y);
    if (p2traits.length > 0) {
      y -= 4;
      y = drawBulletList(page, font, p2traits.slice(0, 6), y);
    }
    y -= 12;
  }

  // Compatibility scores
  if (y < 180) addNewPage();
  y = drawSectionTitle(page, boldFont, isHindi ? "अनुकूलता विश्लेषण" : "Compatibility Breakdown", y, "📊");
  y -= 10;
  const scoreFields = [
    { label: isHindi ? "प्रेम" : "Love", key: "love_score" },
    { label: isHindi ? "भावनात्मक" : "Emotional", key: "emotional_score" },
    { label: isHindi ? "संचार" : "Communication", key: "communication_score" },
    { label: isHindi ? "वित्तीय" : "Financial", key: "financial_score" },
    { label: isHindi ? "करियर" : "Career", key: "career_score" },
    { label: isHindi ? "व्यक्तित्व" : "Personality", key: "personality_score" },
    { label: isHindi ? "आकर्षण" : "Attraction", key: "attraction_score" },
    { label: isHindi ? "विवाह" : "Marriage", key: "marriage_score" },
  ];
  for (const sf of scoreFields) {
    if (y < 60) addNewPage();
    const score = (compatibility[sf.key] as number) || 75;
    y = drawScoreBar(page, font, boldFont, sf.label, score, y);
  }
  y -= 12;

  // Emotional tendencies
  const emotional = t("emotional_tendencies_en", "emotional_tendencies_hi");
  if (emotional) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "भावनात्मक प्रवृत्तियां" : "Emotional Tendencies", y, "💞");
    y -= 6;
    y = drawBodyText(page, font, emotional.replace(/\*\*/g, ""), y);
    y -= 12;
  }

  // Communication tendencies
  const communication = t("communication_tendencies_en", "communication_tendencies_hi");
  if (communication) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "संचार प्रवृत्तियां" : "Communication Tendencies", y, "💬");
    y -= 6;
    y = drawBodyText(page, font, communication.replace(/\*\*/g, ""), y);
    y -= 12;
  }

  // Strengths
  const strengths = tList("strengths_en", "strengths_hi");
  if (strengths.length > 0) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "रिश्ते की शक्तियां" : "Relationship Strengths", y, "🤝");
    y -= 6;
    y = drawBulletList(page, font, strengths.slice(0, 8), y, BRAND.success);
    y -= 12;
  }

  // Challenges
  const challenges = tList("challenges_en", "challenges_hi");
  if (challenges.length > 0) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "संभावित चुनौतियां" : "Potential Challenges", y, "⚠️");
    y -= 6;
    y = drawBulletList(page, font, challenges.slice(0, 8), y, BRAND.warning);
    y -= 12;
  }

  // Marriage interpretation
  const marriageInterp = t("marriage_interpretation_en", "marriage_interpretation_hi");
  const marriageScore = (compatibility.marriage_score as number) || 72;
  if (marriageInterp) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "विवाह संकेतक" : "Marriage Indicators", y, "💍");
    y -= 6;
    y = drawScoreBar(page, font, boldFont, isHindi ? "विवाह अनुकूलता" : "Marriage Compatibility", marriageScore, y);
    y = drawBodyText(page, font, marriageInterp.replace(/\*\*/g, ""), y);
    y -= 12;
  }

  // Growth together
  const growth = tList("growth_together_en", "growth_together_hi");
  if (growth.length > 0) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "साथ में विकास" : "Growth Together", y, "🌱");
    y -= 6;
    y = drawBulletList(page, font, growth.slice(0, 6), y, BRAND.success);
    y -= 12;
  }

  // Future tendencies
  const future = tList("future_tendencies_en", "future_tendencies_hi");
  if (future.length > 0) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "भविष्य की प्रवृत्तियां" : "Future Tendencies", y, "🔮");
    y -= 6;
    y = drawBulletList(page, font, future.slice(0, 6), y);
    y -= 12;
  }

  // Recommendations
  const recs = tList("recommendations_en", "recommendations_hi");
  if (recs.length > 0) {
    if (y < 100) addNewPage();
    y = drawSectionTitle(page, boldFont, isHindi ? "व्यक्तिगत सुझाव" : "Personalized Recommendations", y, "💡");
    y -= 6;
    y = drawBulletList(page, font, recs.slice(0, 6), y, BRAND.primary);
    y -= 12;
  }

  // Disclaimer
  if (y < 120) addNewPage();
  y -= 10;
  drawRule(page, y, BRAND.primary, 1);
  y -= 20;
  const discTitle = isHindi ? "महत्वपूर्ण अस्वीकरण" : "Important Disclaimer";
  page.drawText(discTitle, { x: MARGIN, y, size: 12, font: boldFont, color: BRAND.primaryDark });
  y -= 18;
  const discText = isHindi
    ? "यह पठन हस्तरेखा शास्त्र की पारंपरिक व्याख्या पर आधारित है। Gemini AI ने वास्तविक हथेली की विशेषताओं का विश्लेषण किया है, परंतु यह वैज्ञानिक रूप से सिद्ध नहीं है। इसे मनोरंजन एवं आत्म-चिंतन के लिए उपयोग करें। यह चिकित्सीय, कानूनी या वित्तीय सलाह नहीं है।"
    : "This reading is based on traditional palmistry interpretation. Gemini AI analyzed actual palm features, but palmistry is not scientifically proven. Use for entertainment and self-reflection only. This is not medical, legal, or financial advice.";
  drawBodyText(page, font, discText, y, 9, BRAND.disclaimer, 88);

  const bytes = await pdfDoc.save();
  return bytes;
}

function printableReading(preferred: string, fallback: string): string {
  const source = preferred?.trim() ? preferred : fallback;
  if (!source) return "";
  if (/[^\u0000-\u00ff]/.test(source)) {
    return (fallback || "").replace(/[^\u0000-\u00ff]/g, " ").trim();
  }
  return source;
}

async function buildPalmReadingPdf(
  row: any,
  locale: string,
  hasPremium: boolean,
): Promise<Uint8Array> {
  const isHindi = locale === "hi" || locale === "hi-Latn";
  const pdfDoc = await PDFDocument.create();
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  let page = pdfDoc.addPage([PAGE_W, PAGE_H]);
  let y = PAGE_H - 56;

  const newPage = () => {
    page = pdfDoc.addPage([PAGE_W, PAGE_H]);
    y = PAGE_H - 56;
  };
  const ensure = (needed: number) => {
    if (y < needed) newPage();
  };
  const write = (text: string, size = 10, color = BRAND.text) => {
    for (const line of wrapText(text, 88)) {
      ensure(36);
      page.drawText(line, { x: MARGIN, y, size, font, color });
      y -= size + 4;
    }
    y -= 6;
  };
  const section = (title: string, body: string) => {
    if (!body.trim()) return;
    ensure(64);
    page.drawText(title.slice(0, 70), {
      x: MARGIN,
      y,
      size: 13,
      font: boldFont,
      color: BRAND.primaryDark,
    });
    y -= 18;
    write(body);
  };
  const pick = (en: string, hi: string) =>
    printableReading(isHindi ? hi : en, en);

  page.drawText("HastVeda Palm Reading", {
    x: MARGIN,
    y,
    size: 20,
    font: boldFont,
    color: BRAND.primaryDark,
  });
  y -= 22;
  write(
    `Score ${row.overall_score ?? ""}  |  ${new Date().toLocaleDateString("en-IN")}`,
    10,
    BRAND.subtext,
  );
  if (isHindi) {
    write(
      "This PDF uses the English reading so every character prints. The Hindi reading is in the app.",
      9,
      BRAND.disclaimer,
    );
  }

  section("Overall reading", pick(row.summary || "", row.summary_hi || ""));
  section(
    "Today's insight",
    pick(row.daily_insight_en || "", row.daily_insight_hi || ""),
  );

  const blocks: Array<[string, any, string, string, string]> = [
    ["Personality", row.personality_analysis, "interpretation_en", "interpretation_hi", "is_premium_locked"],
    ["Love and relationships", row.love_analysis, "interpretation_en", "interpretation_hi", "is_premium_locked"],
    ["Life path", row.life_analysis, "interpretation_en", "interpretation_hi", "is_premium_locked"],
    ["Health", row.health_analysis, "interpretation_en", "interpretation_hi", "is_premium_locked"],
    ["Career", row.career_analysis, "interpretation_en", "interpretation_hi", "is_premium_locked"],
    ["Wealth", row.wealth_analysis, "interpretation_en", "interpretation_hi", "is_premium_locked"],
  ];
  for (const [title, block, enKey, hiKey, lockKey] of blocks) {
    if (!block) continue;
    if (!hasPremium && block[lockKey]) continue;
    section(title, pick(block[enKey] || "", block[hiKey] || ""));
  }

  const personality = row.personality_analysis || {};
  if (hasPremium || !personality.future_tendencies_locked) {
    section(
      "5-10 year outlook",
      pick(
        personality.future_tendencies_en || "",
        personality.future_tendencies_hi || "",
      ),
    );
  }
  if (hasPremium || !personality.remedies_locked) {
    section(
      "Vedic remedies",
      pick(personality.remedies_en || "", personality.remedies_hi || ""),
    );
  }

  ensure(80);
  write(
    "This reading is traditional palmistry for reflection. It is not medical, legal, or financial advice.",
    9,
    BRAND.disclaimer,
  );

  return await pdfDoc.save();
}

// ── Main handler ──────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Auth client (user context)
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Service client (for privileged reads)
    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    // Verify user
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized", code: "AUTH_REQUIRED" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const reportType = body.report_type as string; // "detailed_report" | "couple_reading"
    const locale = (body.locale as string) || "en";
    const reportId = body.report_id as string | undefined;
    const coupleReadingId = body.couple_reading_id as string | undefined;

    if (!reportType) {
      return new Response(JSON.stringify({ error: "report_type is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Entitlement check ─────────────────────────────────────────────────────
    const { data: entitlements } = await serviceClient
      .from("entitlements")
      .select("entitlement_type, is_active, expires_at")
      .eq("user_id", user.id)
      .eq("is_active", true);

    const activeTypes = (entitlements || [])
      .filter((e: any) => !e.expires_at || new Date(e.expires_at) > new Date())
      .map((e: any) => e.entitlement_type as string);

    const hasPremium = activeTypes.includes("PREMIUM");
    const hasDetailedReport = activeTypes.includes("DETAILED_REPORT");
    const hasCoupleReading = activeTypes.includes("COUPLE_READING");

    if (reportType === "detailed_report" && !hasPremium && !hasDetailedReport) {
      return new Response(
        JSON.stringify({ error: "Detailed Report PDF requires Premium subscription.", code: "ENTITLEMENT_REQUIRED" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (reportType === "couple_reading" && !hasPremium && !hasCoupleReading) {
      return new Response(
        JSON.stringify({ error: "Couple Reading PDF requires Premium subscription.", code: "ENTITLEMENT_REQUIRED" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let pdfBytes: Uint8Array;
    let filename: string;

    if (reportType === "detailed_report") {
      // Fetch saved report from Supabase
      if (!reportId) {
        return new Response(JSON.stringify({ error: "report_id is required for detailed_report" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: reportRow, error: reportError } = await serviceClient
        .from("reports")
        .select("content, generated_at, created_at")
        .eq("id", reportId)
        .eq("user_id", user.id)
        .maybeSingle();

      if (reportError || !reportRow) {
        return new Response(JSON.stringify({ error: "Report not found or access denied." }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const reportData = reportRow.content as any;
      const generatedAt = (reportRow.generated_at || reportRow.created_at) as string;

      pdfBytes = await buildDetailedReportPdf(reportData, locale, generatedAt);
      filename = `hastveda-palm-report-${new Date().toISOString().split("T")[0]}.pdf`;

    } else if (reportType === "couple_reading") {
      if (!coupleReadingId) {
        return new Response(JSON.stringify({ error: "couple_reading_id is required for couple_reading" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: coupleRow, error: coupleError } = await serviceClient
        .from("couple_readings")
        .select("*")
        .eq("id", coupleReadingId)
        .eq("user_id", user.id)
        .maybeSingle();

      if (coupleError || !coupleRow) {
        return new Response(JSON.stringify({ error: "Couple reading not found or access denied." }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Merge compatibility_data JSONB with top-level columns
      const compatData = { ...coupleRow, ...(coupleRow.compatibility_data || {}) };
      pdfBytes = await buildCoupleReadingPdf(compatData, locale);
      filename = `hastveda-couple-reading-${new Date().toISOString().split("T")[0]}.pdf`;

    } else if (reportType === "palm_reading") {
      const analysisId = body.analysis_id as string | undefined;
      if (!analysisId) {
        return new Response(JSON.stringify({ error: "analysis_id is required for palm_reading" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: analysisRow, error: analysisError } = await serviceClient
        .from("palm_analysis")
        .select("*")
        .eq("id", analysisId)
        .eq("user_id", user.id)
        .maybeSingle();

      if (analysisError || !analysisRow) {
        return new Response(JSON.stringify({ error: "Reading not found or access denied." }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      pdfBytes = await buildPalmReadingPdf(analysisRow, locale, hasPremium);
      filename = `hastveda-palm-reading-${new Date().toISOString().split("T")[0]}.pdf`;

    } else {
      return new Response(JSON.stringify({ error: "Invalid report_type" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(pdfBytes, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="${filename}"`,
        "Content-Length": String(pdfBytes.length),
      },
    });

  } catch (err) {
    console.error("PDF export error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message || "PDF generation failed" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
