// HastVeda — Couple Tab Hub Screen
// Landing screen for the Couple tab in the bottom navigation.
// Shows: New Couple Reading + Couple Reading History access.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/app_strings.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';

class CoupleTabScreen extends StatefulWidget {
  const CoupleTabScreen({super.key});

  @override
  State<CoupleTabScreen> createState() => _CoupleTabScreenState();
}

class _CoupleTabScreenState extends State<CoupleTabScreen> {
  int _recentCount = 0;
  bool _countLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRecentCount();
  }

  Future<void> _loadRecentCount() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('couple_readings')
          .select('id')
          .eq('user_id', userId)
          .limit(99);
      if (mounted) {
        setState(() {
          _recentCount = (data as List).length;
          _countLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _countLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final locale = localeProvider.languageCode;
    final isDark = themeProvider.isDark;
    final isHindi = locale == 'hi';

    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final cardBg = isDark ? AppTheme.surfaceElevated : Colors.white;
    final borderColor = isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF);
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF8B7355);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: isDark
                ? AppTheme.surfaceDark
                : const Color(0xFF1A0E06),
            automaticallyImplyLeading: false,
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFEC4899).withAlpha(40),
                                    AppTheme.primary.withAlpha(30),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFFEC4899),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isHindi ? 'युगल पठन' : 'Couple Reading',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    isHindi
                                        ? 'हथेली से अनुकूलता जानें'
                                        : 'Discover compatibility through palms',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // AI badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.cyanMuted,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.cyan.withAlpha(60),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 12,
                                color: AppTheme.cyan,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isHindi
                                    ? 'Gemini AI द्वारा संचालित'
                                    : 'Powered by Gemini AI',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.cyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── New Reading CTA ──────────────────────────────────────
                  GestureDetector(
                    onTap: () => context.push(
                      '${AppRoutes.coupleReading}?locale=$locale',
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xFF2A0A1A),
                                  const Color(0xFF1A0A14),
                                ]
                              : [
                                  const Color(0xFFFFE4F0),
                                  const Color(0xFFFFF0F8),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFEC4899).withAlpha(60),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFEC4899,
                            ).withAlpha(isDark ? 20 : 10),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFEC4899), Color(0xFFBE185D)],
                              ),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isHindi
                                      ? 'नया युगल पठन'
                                      : 'New Couple Reading',
                                  style: GoogleFonts.outfit(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1410),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isHindi
                                      ? 'दोनों हथेलियों का विश्लेषण करें'
                                      : 'Analyze both palms for compatibility',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: isDark
                                        ? const Color(0xFFEC4899).withAlpha(200)
                                        : const Color(0xFFBE185D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFEC4899).withAlpha(20),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFFEC4899),
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── History CTA ──────────────────────────────────────────
                  GestureDetector(
                    onTap: () => context.push(
                      '${AppRoutes.coupleReadingHistory}?locale=$locale',
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 30 : 8),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primary.withAlpha(15),
                              border: Border.all(
                                color: AppTheme.primary.withAlpha(40),
                              ),
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              color: AppTheme.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isHindi
                                      ? 'युगल पठन इतिहास'
                                      : 'Couple Reading History',
                                  style: GoogleFonts.outfit(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _countLoaded && _recentCount > 0
                                      ? (isHindi
                                            ? '$_recentCount पिछले पठन'
                                            : '$_recentCount previous reading${_recentCount == 1 ? '' : 's'}')
                                      : (isHindi
                                            ? 'पिछले पठन देखें'
                                            : 'View previous readings'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_countLoaded && _recentCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withAlpha(15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$_recentCount',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: subColor,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── How it works ─────────────────────────────────────────
                  Text(
                    isHindi ? 'यह कैसे काम करता है' : 'How it works',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._steps(isHindi).asMap().entries.map(
                    (entry) => _StepTile(
                      step: entry.key + 1,
                      emoji: entry.value['emoji']!,
                      title: entry.value['title']!,
                      desc: entry.value['desc']!,
                      isDark: isDark,
                      isLast: entry.key == _steps(isHindi).length - 1,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Disclaimer ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withAlpha(6)
                          : Colors.black.withAlpha(4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withAlpha(15)
                            : Colors.black.withAlpha(10),
                      ),
                    ),
                    child: Text(
                      isHindi
                          ? '⚠️ युगल पठन हस्तरेखा शास्त्र की पारंपरिक व्याख्या पर आधारित है। यह वैज्ञानिक रूप से सिद्ध नहीं है। मनोरंजन एवं आत्म-चिंतन के लिए उपयोग करें।'
                          : '⚠️ Couple Reading is based on traditional palmistry interpretation. It is not scientifically proven. Use for entertainment and self-reflection only.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _steps(bool isHindi) => [
    {
      'emoji': '🖐️',
      'title': isHindi ? 'दोनों हथेलियां अपलोड करें' : 'Upload Both Palms',
      'desc': isHindi
          ? 'व्यक्ति १ और व्यक्ति २ की स्पष्ट हथेली की फोटो अपलोड करें'
          : 'Upload clear palm photos for Person 1 and Person 2',
    },
    {
      'emoji': '🤖',
      'title': isHindi ? 'Gemini AI विश्लेषण' : 'Gemini AI Analysis',
      'desc': isHindi
          ? 'AI प्रत्येक हथेली की रेखाओं और विशेषताओं का अलग-अलग विश्लेषण करता है'
          : 'AI analyzes each palm\'s lines and features separately',
    },
    {
      'emoji': '💞',
      'title': isHindi ? 'अनुकूलता रिपोर्ट' : 'Compatibility Report',
      'desc': isHindi
          ? 'दोनों विश्लेषणों के आधार पर वास्तविक अनुकूलता रिपोर्ट तैयार होती है'
          : 'A real compatibility report is generated from both analyses',
    },
    {
      'emoji': '📚',
      'title': isHindi ? 'इतिहास में सहेजा जाता है' : 'Saved to History',
      'desc': isHindi
          ? 'रिपोर्ट सुरक्षित रूप से सहेजी जाती है — कभी भी दोबारा देखें'
          : 'Report is securely saved — view again anytime without re-analysis',
    },
  ];
}

class _StepTile extends StatelessWidget {
  final int step;
  final String emoji;
  final String title;
  final String desc;
  final bool isDark;
  final bool isLast;

  const _StepTile({
    required this.step,
    required this.emoji,
    required this.title,
    required this.desc,
    required this.isDark,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF8B7355);
    final lineColor = isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step indicator + line
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withAlpha(15),
                  border: Border.all(color: AppTheme.primary.withAlpha(60)),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 16)),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: subColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
