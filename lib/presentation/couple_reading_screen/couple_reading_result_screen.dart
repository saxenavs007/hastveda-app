// HastVeda Couple Reading Result Screen
// Displays real Gemini-generated compatibility data from the couple-reading Edge Function.
// All content is AI-generated from actual palm feature analysis — no mock values.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/pdf_export_service.dart';
import '../../theme/app_theme.dart';

class CoupleReadingResultScreen extends StatefulWidget {
  final Map<String, dynamic> compatibility;
  final String locale;

  const CoupleReadingResultScreen({
    super.key,
    required this.compatibility,
    this.locale = 'en',
  });

  @override
  State<CoupleReadingResultScreen> createState() =>
      _CoupleReadingResultScreenState();
}

class _CoupleReadingResultScreenState extends State<CoupleReadingResultScreen> {
  bool _isExportingPdf = false;
  String? _pdfError;
  bool _pdfSuccess = false;

  bool get _isHindi => widget.locale == 'hi';

  String _t(String enKey, String hiKey) {
    final en = widget.compatibility[enKey] as String? ?? '';
    final hi = widget.compatibility[hiKey] as String? ?? '';
    if (_isHindi && hi.isNotEmpty) return hi;
    return en;
  }

  List<String> _tList(String enKey, String hiKey) {
    final en = (widget.compatibility[enKey] as List?)?.cast<String>() ?? [];
    final hi = (widget.compatibility[hiKey] as List?)?.cast<String>() ?? [];
    if (_isHindi && hi.isNotEmpty) return hi;
    return en;
  }

  Future<void> _downloadPdf() async {
    final coupleReadingId = widget.compatibility['id'] as String?;
    if (coupleReadingId == null) {
      setState(
        () => _pdfError = _isHindi
            ? 'युगल पठन ID उपलब्ध नहीं है।'
            : 'Couple reading ID not available.',
      );
      return;
    }
    setState(() {
      _isExportingPdf = true;
      _pdfError = null;
      _pdfSuccess = false;
    });
    try {
      final result = await PdfExportService.instance.exportCoupleReading(
        coupleReadingId: coupleReadingId,
        locale: widget.locale,
      );
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _isExportingPdf = false;
          _pdfSuccess = true;
        });
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _pdfSuccess = false);
        });
      } else if (result.entitlementRequired) {
        setState(() {
          _isExportingPdf = false;
          _pdfError = result.errorMessage;
        });
      } else {
        setState(() {
          _isExportingPdf = false;
          _pdfError = result.errorMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExportingPdf = false;
          _pdfError = _isHindi
              ? 'PDF उत्पन्न नहीं हो सका।'
              : 'Could not generate PDF.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final person1Name =
        widget.compatibility['person1_name'] as String? ??
        (_isHindi ? 'व्यक्ति १' : 'Person 1');
    final person2Name =
        widget.compatibility['person2_name'] as String? ??
        (_isHindi ? 'व्यक्ति २' : 'Person 2');
    final overallScore =
        (widget.compatibility['overall_compatibility_score'] as num?)
            ?.toInt() ??
        75;

    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final cardBg = isDark ? AppTheme.surfaceElevated : Colors.white;
    final borderColor = isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF);
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subTextColor = isDark
        ? AppTheme.textSecondary
        : const Color(0xFF5C4A3A);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: isDark
                ? AppTheme.surfaceDark
                : const Color(0xFF1A0E06),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
              onPressed: popOrHome,
            ),
            actions: [
              IconButton(
                icon: _isExportingPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Colors.white,
                      ),
                tooltip: _isHindi ? 'PDF डाउनलोड करें' : 'Download PDF',
                onPressed: _isExportingPdf ? null : _downloadPdf,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [AppTheme.surfaceDark, AppTheme.backgroundDark]
                        : [const Color(0xFF2A1200), const Color(0xFF0F0A06)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _NameBadge(name: person1Name),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  color: AppTheme.primary,
                                  size: 28,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '&',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _NameBadge(name: person2Name),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _OverallScoreRing(score: overallScore, isHindi: _isHindi),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PDF status banners
                  if (_pdfSuccess)
                    _CoupleResultPdfBanner(
                      isSuccess: true,
                      isHindi: _isHindi,
                      isDark: isDark,
                    ),
                  if (_pdfError != null)
                    _CoupleResultPdfBanner(
                      isSuccess: false,
                      isHindi: _isHindi,
                      isDark: isDark,
                      message: _pdfError,
                    ),
                  if (_pdfSuccess || _pdfError != null)
                    const SizedBox(height: 12),

                  // AI analysis badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.cyanMuted,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.cyan.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: AppTheme.cyan,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isHindi
                              ? 'Gemini AI द्वारा वास्तविक हथेली विश्लेषण'
                              : 'Real palm analysis by Gemini AI',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.cyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Relationship Overview ─────────────────────────────────
                  _SectionHeader(
                    emoji: '🔮',
                    title: _isHindi
                        ? 'रिश्ते का अवलोकन'
                        : 'Relationship Overview',
                  ),
                  const SizedBox(height: 12),
                  _OverviewCard(
                    person1Name: person1Name,
                    person2Name: person2Name,
                    score: overallScore,
                    overview: _t('overview_en', 'overview_hi'),
                    basisNote: _t(
                      'compatibility_basis_en',
                      'compatibility_basis_hi',
                    ),
                    isHindi: _isHindi,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Individual Palm Observations ──────────────────────────
                  _SectionHeader(
                    emoji: '🖐️',
                    title: _isHindi ? 'हथेली अवलोकन' : 'Palm Observations',
                  ),
                  const SizedBox(height: 12),
                  _PersonObservationCard(
                    name: person1Name,
                    observation: _t(
                      'person1_observations_en',
                      'person1_observations_hi',
                    ),
                    keyTraits: _tList(
                      'person1_key_traits_en',
                      'person1_key_traits_hi',
                    ),
                    personNumber: 1,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _PersonObservationCard(
                    name: person2Name,
                    observation: _t(
                      'person2_observations_en',
                      'person2_observations_hi',
                    ),
                    keyTraits: _tList(
                      'person2_key_traits_en',
                      'person2_key_traits_hi',
                    ),
                    personNumber: 2,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Compatibility Breakdown ───────────────────────────────
                  _SectionHeader(
                    emoji: '📊',
                    title: _isHindi
                        ? 'अनुकूलता विश्लेषण'
                        : 'Compatibility Breakdown',
                  ),
                  const SizedBox(height: 12),
                  _CompatibilityGrid(
                    compatibility: widget.compatibility,
                    isHindi: _isHindi,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Emotional Tendencies ──────────────────────────────────
                  _SectionHeader(
                    emoji: '💞',
                    title: _isHindi
                        ? 'भावनात्मक प्रवृत्तियां'
                        : 'Emotional Tendencies',
                  ),
                  const SizedBox(height: 12),
                  _TextCard(
                    content: _t(
                      'emotional_tendencies_en',
                      'emotional_tendencies_hi',
                    ),
                    accentColor: const Color(0xFFEC4899),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Communication Tendencies ──────────────────────────────
                  _SectionHeader(
                    emoji: '💬',
                    title: _isHindi
                        ? 'संचार प्रवृत्तियां'
                        : 'Communication Tendencies',
                  ),
                  const SizedBox(height: 12),
                  _TextCard(
                    content: _t(
                      'communication_tendencies_en',
                      'communication_tendencies_hi',
                    ),
                    accentColor: AppTheme.cyan,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Relationship Strengths ────────────────────────────────
                  _SectionHeader(
                    emoji: '🤝',
                    title: _isHindi
                        ? 'रिश्ते की शक्तियां'
                        : 'Relationship Strengths',
                  ),
                  const SizedBox(height: 12),
                  _BulletCard(
                    items: _tList('strengths_en', 'strengths_hi'),
                    accentColor: AppTheme.success,
                    bgColor: isDark
                        ? AppTheme.successContainer
                        : const Color(0xFFF0FFF8),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Potential Challenges ──────────────────────────────────
                  _SectionHeader(
                    emoji: '⚠️',
                    title: _isHindi
                        ? 'संभावित चुनौतियां'
                        : 'Potential Challenges',
                  ),
                  const SizedBox(height: 12),
                  _BulletCard(
                    items: _tList('challenges_en', 'challenges_hi'),
                    accentColor: AppTheme.warning,
                    bgColor: isDark
                        ? AppTheme.warningContainer
                        : const Color(0xFFFFFBEB),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Marriage Indicators ───────────────────────────────────
                  _SectionHeader(
                    emoji: '💍',
                    title: _isHindi ? 'विवाह संकेतक' : 'Marriage Indicators',
                  ),
                  const SizedBox(height: 12),
                  _MarriageCard(
                    score:
                        (widget.compatibility['marriage_score'] as num?)
                            ?.toInt() ??
                        72,
                    interpretation: _t(
                      'marriage_interpretation_en',
                      'marriage_interpretation_hi',
                    ),
                    isHindi: _isHindi,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Growth Together ───────────────────────────────────────
                  _SectionHeader(
                    emoji: '🌱',
                    title: _isHindi ? 'साथ में विकास' : 'Growth Together',
                  ),
                  const SizedBox(height: 12),
                  _BulletCard(
                    items: _tList('growth_together_en', 'growth_together_hi'),
                    accentColor: AppTheme.success,
                    bgColor: isDark
                        ? AppTheme.successContainer
                        : const Color(0xFFF0FFF8),
                    isDark: isDark,
                    bulletEmoji: '🌱',
                  ),
                  const SizedBox(height: 24),

                  // ── Future Tendencies ─────────────────────────────────────
                  _SectionHeader(
                    emoji: '🔮',
                    title: _isHindi
                        ? 'भविष्य की प्रवृत्तियां'
                        : 'Future Tendencies',
                  ),
                  const SizedBox(height: 12),
                  _BulletCard(
                    items: _tList(
                      'future_tendencies_en',
                      'future_tendencies_hi',
                    ),
                    accentColor: const Color(0xFF8B5CF6),
                    bgColor: isDark
                        ? const Color(0xFF1A0A2E)
                        : const Color(0xFFF5F3FF),
                    isDark: isDark,
                    bulletEmoji: '🔮',
                  ),
                  const SizedBox(height: 24),

                  // ── Personalized Recommendations ──────────────────────────
                  _SectionHeader(
                    emoji: '💡',
                    title: _isHindi
                        ? 'व्यक्तिगत सुझाव'
                        : 'Personalized Recommendations',
                  ),
                  const SizedBox(height: 12),
                  _BulletCard(
                    items: _tList('recommendations_en', 'recommendations_hi'),
                    accentColor: AppTheme.primary,
                    bgColor: isDark
                        ? AppTheme.goldMuted
                        : const Color(0xFFFFF8E7),
                    isDark: isDark,
                    bulletEmoji: '💡',
                  ),
                  const SizedBox(height: 24),

                  // ── Disclaimer ────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withAlpha(8)
                          : Colors.black.withAlpha(5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withAlpha(20)
                            : Colors.black.withAlpha(15),
                      ),
                    ),
                    child: Text(
                      _isHindi
                          ? '⚠️ यह पठन हस्तरेखा शास्त्र की पारंपरिक व्याख्या पर आधारित है। Gemini AI ने वास्तविक हथेली की विशेषताओं का विश्लेषण किया है, लेकिन यह वैज्ञानिक रूप से सिद्ध नहीं है। इसे मनोरंजन एवं आत्म-चिंतन के लिए उपयोग करें। यह चिकित्सीय, कानूनी या वित्तीय सलाह नहीं है।'
                          : '⚠️ This reading is based on traditional palmistry interpretation. Gemini AI analyzed actual palm features, but palmistry is not scientifically proven. Use for entertainment and self-reflection only. This is not medical, legal, or financial advice.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

class _NameBadge extends StatelessWidget {
  final String name;
  const _NameBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Text(
        name,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _OverallScoreRing extends StatelessWidget {
  final int score;
  final bool isHindi;
  const _OverallScoreRing({required this.score, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppTheme.success
        : score >= 60
        ? AppTheme.primary
        : AppTheme.warning;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: score / 100,
                strokeWidth: 6,
                backgroundColor: Colors.white.withAlpha(20),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isHindi ? 'समग्र अनुकूलता' : 'Overall Compatibility',
          style: GoogleFonts.outfit(fontSize: 13, color: Colors.white60),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  const _SectionHeader({required this.emoji, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDark ? AppTheme.textPrimary : const Color(0xFF1A1410),
          ),
        ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String person1Name;
  final String person2Name;
  final int score;
  final String overview;
  final String basisNote;
  final bool isHindi;
  final bool isDark;

  const _OverviewCard({
    required this.person1Name,
    required this.person2Name,
    required this.score,
    required this.overview,
    required this.basisNote,
    required this.isHindi,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final label = score >= 85
        ? (isHindi ? 'उत्कृष्ट अनुकूलता' : 'Excellent Compatibility')
        : score >= 70
        ? (isHindi ? 'अच्छी अनुकूलता' : 'Good Compatibility')
        : (isHindi ? 'मध्यम अनुकूलता' : 'Moderate Compatibility');

    final displayText = overview.isNotEmpty
        ? overview
        : (isHindi
              ? 'हस्तरेखा शास्त्र की पारंपरिक व्याख्या के अनुसार, $person1Name और $person2Name की हथेलियों में $label की प्रवृत्ति दिखती है।'
              : 'Traditional palmistry interpretation suggests $person1Name and $person2Name\'s palms show a tendency toward $label.');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withAlpha(20),
            AppTheme.primary.withAlpha(8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayText,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: isDark ? Colors.white70 : const Color(0xFF5C4A3A),
              height: 1.6,
            ),
          ),
          if (basisNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              basisNote,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonObservationCard extends StatelessWidget {
  final String name;
  final String observation;
  final List<String> keyTraits;
  final int personNumber;
  final bool isDark;

  const _PersonObservationCard({
    required this.name,
    required this.observation,
    required this.keyTraits,
    required this.personNumber,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = personNumber == 1 ? AppTheme.primary : AppTheme.cyan;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withAlpha(20),
                  border: Border.all(color: accentColor.withAlpha(60)),
                ),
                child: Center(
                  child: Text(
                    '$personNumber',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.textPrimary
                        : const Color(0xFF1A1410),
                  ),
                ),
              ),
            ],
          ),
          if (observation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              observation,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: isDark
                    ? AppTheme.textSecondary
                    : const Color(0xFF5C4A3A),
                height: 1.5,
              ),
            ),
          ],
          if (keyTraits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keyTraits
                  .map(
                    (trait) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accentColor.withAlpha(40)),
                      ),
                      child: Text(
                        trait,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompatibilityGrid extends StatelessWidget {
  final Map<String, dynamic> compatibility;
  final bool isHindi;
  final bool isDark;

  const _CompatibilityGrid({
    required this.compatibility,
    required this.isHindi,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final aspects = [
      {
        'emoji': '❤️',
        'label': isHindi ? 'प्रेम' : 'Love',
        'score': (compatibility['love_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '💞',
        'label': isHindi ? 'भावनात्मक' : 'Emotional',
        'score': (compatibility['emotional_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '💬',
        'label': isHindi ? 'संचार' : 'Communication',
        'score': (compatibility['communication_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '💰',
        'label': isHindi ? 'वित्तीय' : 'Financial',
        'score': (compatibility['financial_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '💼',
        'label': isHindi ? 'करियर' : 'Career',
        'score': (compatibility['career_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '🧠',
        'label': isHindi ? 'व्यक्तित्व' : 'Personality',
        'score': (compatibility['personality_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '🔥',
        'label': isHindi ? 'आकर्षण' : 'Attraction',
        'score': (compatibility['attraction_score'] as num?)?.toInt() ?? 75,
      },
      {
        'emoji': '💍',
        'label': isHindi ? 'विवाह' : 'Marriage',
        'score': (compatibility['marriage_score'] as num?)?.toInt() ?? 72,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: aspects.length,
      itemBuilder: (context, index) {
        final aspect = aspects[index];
        final score = aspect['score'] as int;
        final color = score >= 80
            ? AppTheme.success
            : score >= 65
            ? AppTheme.primary
            : AppTheme.warning;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceElevated : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    aspect['emoji'] as String,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      aspect['label'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.textSecondary
                            : const Color(0xFF5C4A3A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$score%',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      backgroundColor: isDark
                          ? Colors.white.withAlpha(20)
                          : Colors.black.withAlpha(10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TextCard extends StatelessWidget {
  final String content;
  final Color accentColor;
  final bool isDark;

  const _TextCard({
    required this.content,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withAlpha(50)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withAlpha(10), accentColor.withAlpha(4)],
        ),
      ),
      child: Text(
        content,
        style: GoogleFonts.outfit(
          fontSize: 14,
          color: isDark ? Colors.white70 : const Color(0xFF5C4A3A),
          height: 1.6,
        ),
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  final List<String> items;
  final Color accentColor;
  final Color bgColor;
  final bool isDark;
  final String? bulletEmoji;

  const _BulletCard({
    required this.items,
    required this.accentColor,
    required this.bgColor,
    required this.isDark,
    this.bulletEmoji,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withAlpha(60)),
      ),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bulletEmoji != null
                        ? Text(
                            bulletEmoji!,
                            style: const TextStyle(fontSize: 14),
                          )
                        : Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor,
                            ),
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF5C4A3A),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MarriageCard extends StatelessWidget {
  final int score;
  final String interpretation;
  final bool isHindi;
  final bool isDark;

  const _MarriageCard({
    required this.score,
    required this.interpretation,
    required this.isHindi,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF8B5CF6);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [purple.withAlpha(20), purple.withAlpha(8)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: purple.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💍', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(
                '$score%',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: purple,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isHindi ? 'विवाह अनुकूलता' : 'Marriage Compatibility',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF5C4A3A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(10),
              valueColor: const AlwaysStoppedAnimation<Color>(purple),
              minHeight: 6,
            ),
          ),
          if (interpretation.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              interpretation,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF5C4A3A),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── PDF Status Banner ─────────────────────────────────────────────────────────

class _CoupleResultPdfBanner extends StatelessWidget {
  final bool isSuccess;
  final bool isHindi;
  final bool isDark;
  final String? message;

  const _CoupleResultPdfBanner({
    required this.isSuccess,
    required this.isHindi,
    required this.isDark,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSuccess ? AppTheme.success : AppTheme.error;
    final bgColor = isSuccess
        ? (isDark ? AppTheme.successContainer : const Color(0xFFF0FFF8))
        : (isDark ? AppTheme.error.withAlpha(30) : const Color(0xFFFFF0F0));
    final icon = isSuccess
        ? Icons.check_circle_rounded
        : Icons.error_outline_rounded;
    final text = isSuccess
        ? (isHindi
              ? '✅ PDF सफलतापूर्वक डाउनलोड हो गई!'
              : '✅ PDF downloaded successfully!')
        : (message ??
              (isHindi
                  ? 'PDF उत्पन्न नहीं हो सकी।'
                  : 'Could not generate PDF.'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
