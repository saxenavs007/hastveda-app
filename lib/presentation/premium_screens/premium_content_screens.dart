// HastVeda Premium Content Screens
// These screens display premium palm reading categories.
// Each screen shows a locked premium gate for free users,
// or the AI-generated content for premium users.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/locale_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_lock_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared base widget for all premium content screens
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumContentScreen extends StatefulWidget {
  final String titleEn;
  final String titleHi;
  final String emoji;
  final String descriptionEn;
  final String descriptionHi;

  /// Column on `palm_analysis` this screen renders (e.g. `career_analysis`).
  final String featureKey;

  /// Key from [PremiumFeatures] that decides access. The FINAL FREE/PREMIUM
  /// structure lives there — this screen never decides tiering for itself.
  final String accessFeature;
  final String locale;
  final String analyticsEvent;

  const _PremiumContentScreen({
    required this.titleEn,
    required this.titleHi,
    required this.emoji,
    required this.descriptionEn,
    required this.descriptionHi,
    required this.featureKey,
    required this.accessFeature,
    required this.locale,
    required this.analyticsEvent,
  });

  @override
  State<_PremiumContentScreen> createState() => _PremiumContentScreenState();
}

class _PremiumContentScreenState extends State<_PremiumContentScreen> {
  bool _isCheckingEntitlement = true;
  bool _hasAccess = false;
  Map<String, dynamic>? _analysisData;
  bool _isLoadingData = false;
  bool _appliedLivePremium = false;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    analytics.track(widget.analyticsEvent);
    _checkAccess();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.watch<EntitlementNotifier>().isPremium;
    if (!premium || _hasAccess) return;
    _hasAccess = true;
    _isCheckingEntitlement = false;
    if (_appliedLivePremium || _analysisData != null) return;
    _appliedLivePremium = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  Future<void> _checkAccess() async {
    setState(() => _isCheckingEntitlement = true);
    // Free features short-circuit: no network round-trip, no lock state.
    if (PremiumFeatures.isFree(widget.accessFeature)) {
      setState(() {
        _hasAccess = true;
        _isCheckingEntitlement = false;
      });
      _loadData();
      return;
    }
    try {
      final canUse = await EntitlementService.instance.canUseFeature(
        widget.accessFeature,
        forceRefresh: true,
      );
      if (!mounted) return;
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _hasAccess = canUse || premium;
        _isCheckingEntitlement = false;
      });
      if (canUse || premium) _loadData();
    } catch (_) {
      if (!mounted) return;
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _isCheckingEntitlement = false;
        if (premium) _hasAccess = true;
      });
      if (premium) _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoadingData = false);
        return;
      }
      // Load latest palm_analysis for this user
      final data = await SupabaseService.instance.client
          .from('palm_analysis')
          .select()
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _analysisData = data;
          _isLoadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  String _getContent() {
    if (_analysisData == null) return '';
    final section = _analysisData![widget.featureKey] as Map<String, dynamic>?;
    if (section == null) return '';
    if (_isHindi) {
      return section['interpretation_hi'] as String? ??
          section['summary_hi'] as String? ??
          section['interpretation_en'] as String? ??
          section['summary'] as String? ??
          '';
    }
    return section['interpretation_en'] as String? ??
        section['summary'] as String? ??
        section['interpretation'] as String? ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;

    final title = _isHindi ? widget.titleHi : widget.titleEn;
    final description = _isHindi ? widget.descriptionHi : widget.descriptionEn;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          '${widget.emoji}  $title',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isCheckingEntitlement
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : !_hasAccess
          ? _buildLockedState(context, isDark, textPri, textSec, description)
          : _isLoadingData
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _buildContent(context, isDark, textPri, textSec, description),
    );
  }

  Widget _buildLockedState(
    BuildContext context,
    bool isDark,
    Color textPri,
    Color textSec,
    String description,
  ) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(widget.emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            _isHindi ? widget.titleHi : widget.titleEn,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textPri,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: textSec,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          PremiumLockWidget(
            feature: widget.accessFeature,
            locale: widget.locale,
            child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                '${AppRoutes.premiumPaywall}?locale=${widget.locale}',
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                _isHindi ? 'प्रीमियम अनलॉक करें' : 'Unlock Premium',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool isDark,
    Color textPri,
    Color textSec,
    String description,
  ) {
    final content = _getContent();
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: Row(
              children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isHindi ? widget.titleHi : widget.titleEn,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _TierBadge(
                        isFree: PremiumFeatures.isFree(widget.accessFeature),
                        isHindi: _isHindi,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (content.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isHindi ? 'आपकी व्याख्या' : 'Your Interpretation',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: textPri,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.back_hand_rounded,
                    size: 48,
                    color: isDark
                        ? AppTheme.textMuted
                        : AppTheme.textMutedLight,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isHindi
                        ? 'हथेली स्कैन करें और विस्तृत विश्लेषण प्राप्त करें'
                        : 'Scan your palm to get detailed analysis for this section',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: textSec,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => context.push(AppRoutes.palmScanScreen),
                    icon: const Icon(Icons.back_hand_rounded, size: 18),
                    label: Text(
                      _isHindi ? 'हथेली स्कैन करें' : 'Scan Your Palm',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Disclaimer
          Text(
            _isHindi
                ? 'हस्तरेखा पारंपरिक व्याख्या है — वैज्ञानिक तथ्य नहीं।'
                : 'Palmistry is a traditional interpretation — not scientific fact.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Free / Premium chip — driven by [PremiumFeatures], so a screen can never
/// advertise a tier different from the one that actually gates it.
class _TierBadge extends StatelessWidget {
  final bool isFree;
  final bool isHindi;

  const _TierBadge({required this.isFree, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    final color = isFree ? Colors.green : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isFree ? 40 : 30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(isFree ? 100 : 80)),
      ),
      child: Text(
        isFree
            ? (isHindi ? 'मुफ़्त' : 'Free')
            : (isHindi ? 'प्रीमियम' : 'Premium'),
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Palm Profile Screen
// ─────────────────────────────────────────────────────────────────────────────

class PalmProfileScreen extends StatelessWidget {
  final String locale;
  const PalmProfileScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Palm Profile',
      titleHi: 'हस्त प्रोफ़ाइल',
      emoji: '🖐️',
      descriptionEn:
          'Your complete palm profile — a comprehensive overview of all palm lines, mounts, and marks that define your unique palmistry signature.',
      descriptionHi:
          'आपकी पूर्ण हस्त प्रोफ़ाइल — सभी हथेली रेखाओं, पर्वतों और चिह्नों का व्यापक अवलोकन।',
      featureKey: 'personality_analysis',
      accessFeature: PremiumFeatures.palmProfile,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marriage Indicators Screen
// ─────────────────────────────────────────────────────────────────────────────

class MarriageIndicatorsScreen extends StatelessWidget {
  final String locale;
  const MarriageIndicatorsScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Marriage Indicators',
      titleHi: 'विवाह संकेतक',
      emoji: '💍',
      descriptionEn:
          'Discover what your palm reveals about love, marriage timing, and relationship compatibility through traditional palmistry indicators.',
      descriptionHi:
          'पारंपरिक हस्तरेखा संकेतकों के माध्यम से प्रेम, विवाह समय और संबंध अनुकूलता के बारे में जानें।',
      featureKey: 'love_analysis',
      accessFeature: PremiumFeatures.marriageIndicators,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mount Analysis Screen
// ─────────────────────────────────────────────────────────────────────────────

class MountAnalysisScreen extends StatelessWidget {
  final String locale;
  const MountAnalysisScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Mount Analysis',
      titleHi: 'पर्वत विश्लेषण',
      emoji: '⛰️',
      descriptionEn:
          'The mounts of your palm — raised areas beneath each finger — reveal personality strengths, talents, and life tendencies in traditional palmistry.',
      descriptionHi:
          'आपकी हथेली के पर्वत — प्रत्येक उंगली के नीचे उभरे हुए क्षेत्र — व्यक्तित्व शक्तियों और जीवन प्रवृत्तियों को प्रकट करते हैं।',
      featureKey: 'personality_analysis',
      accessFeature: PremiumFeatures.mountAnalysis,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Palm Marks Screen
// ─────────────────────────────────────────────────────────────────────────────

class PalmMarksScreen extends StatelessWidget {
  final String locale;
  const PalmMarksScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Palm Marks',
      titleHi: 'हस्त चिह्न',
      emoji: '✨',
      descriptionEn:
          'Special marks, stars, crosses, and symbols on your palm carry unique meanings in traditional palmistry — revealing special talents and life events.',
      descriptionHi:
          'आपकी हथेली पर विशेष चिह्न, तारे, क्रॉस और प्रतीक पारंपरिक हस्तरेखा में अद्वितीय अर्थ रखते हैं।',
      featureKey: 'personality_analysis',
      accessFeature: PremiumFeatures.palmMarks,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Personality Screen
// ─────────────────────────────────────────────────────────────────────────────

class PersonalityScreen extends StatefulWidget {
  final String locale;
  const PersonalityScreen({super.key, this.locale = 'en'});

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _analysisData;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    analytics.track(HastVedaEvents.readingViewed);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final data = await SupabaseService.instance.client
          .from('palm_analysis')
          .select()
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _analysisData = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getContent() {
    if (_analysisData == null) return '';
    final section =
        _analysisData!['personality_analysis'] as Map<String, dynamic>?;
    if (section == null) return '';
    if (_isHindi) {
      return section['interpretation_hi'] as String? ??
          section['interpretation_en'] as String? ??
          '';
    }
    return section['interpretation_en'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    final content = _getContent();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          _isHindi ? '🧠  व्यक्तित्व' : '🧠  Personality',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.homeScreen);
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withAlpha(60)),
                    ),
                    child: Row(
                      children: [
                        const Text('🧠', style: TextStyle(fontSize: 40)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isHindi ? 'व्यक्तित्व' : 'Personality',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(40),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.green.withAlpha(100),
                                  ),
                                ),
                                child: Text(
                                  _isHindi ? 'मुफ़्त' : 'Free',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (content.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isHindi ? 'आपकी व्याख्या' : 'Your Interpretation',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            content,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: textPri,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.back_hand_rounded,
                            size: 48,
                            color: isDark
                                ? AppTheme.textMuted
                                : AppTheme.textMutedLight,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isHindi
                                ? 'हथेली स्कैन करें और अपना व्यक्तित्व विश्लेषण प्राप्त करें'
                                : 'Scan your palm to get your personality analysis',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: textSec,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () =>
                                context.push(AppRoutes.palmScanScreen),
                            icon: const Icon(Icons.back_hand_rounded, size: 18),
                            label: Text(
                              _isHindi ? 'हथेली स्कैन करें' : 'Scan Your Palm',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    _isHindi
                        ? 'हस्तरेखा पारंपरिक व्याख्या है — वैज्ञानिक तथ्य नहीं।'
                        : 'Palmistry is a traditional interpretation — not scientific fact.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.textMuted
                          : AppTheme.textMutedLight,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Love & Relationships Screen
// ─────────────────────────────────────────────────────────────────────────────

class LoveRelationshipsScreen extends StatefulWidget {
  final String locale;
  const LoveRelationshipsScreen({super.key, this.locale = 'en'});

  @override
  State<LoveRelationshipsScreen> createState() =>
      _LoveRelationshipsScreenState();
}

class _LoveRelationshipsScreenState extends State<LoveRelationshipsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _analysisData;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    analytics.track(HastVedaEvents.readingViewed);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final data = await SupabaseService.instance.client
          .from('palm_analysis')
          .select()
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _analysisData = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getContent() {
    if (_analysisData == null) return '';
    final section = _analysisData!['love_analysis'] as Map<String, dynamic>?;
    if (section == null) return '';
    if (_isHindi) {
      return section['interpretation_hi'] as String? ??
          section['interpretation_en'] as String? ??
          '';
    }
    return section['interpretation_en'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    final content = _getContent();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          _isHindi ? '❤️  प्रेम और संबंध' : '❤️  Love & Relationships',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.homeScreen);
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withAlpha(60)),
                    ),
                    child: Row(
                      children: [
                        const Text('❤️', style: TextStyle(fontSize: 40)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isHindi
                                    ? 'प्रेम और संबंध'
                                    : 'Love & Relationships',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(40),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.green.withAlpha(100),
                                  ),
                                ),
                                child: Text(
                                  _isHindi ? 'मुफ़्त' : 'Free',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (content.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isHindi ? 'आपकी व्याख्या' : 'Your Interpretation',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            content,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: textPri,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 48,
                            color: isDark
                                ? AppTheme.textMuted
                                : AppTheme.textMutedLight,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isHindi
                                ? 'हथेली स्कैन करें और अपना प्रेम विश्लेषण प्राप्त करें'
                                : 'Scan your palm to get your love & relationships analysis',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: textSec,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () =>
                                context.push(AppRoutes.palmScanScreen),
                            icon: const Icon(Icons.back_hand_rounded, size: 18),
                            label: Text(
                              _isHindi ? 'हथेली स्कैन करें' : 'Scan Your Palm',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    _isHindi
                        ? 'हस्तरेखा पारंपरिक व्याख्या है — वैज्ञानिक तथ्य नहीं।'
                        : 'Palmistry is a traditional interpretation — not scientific fact.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.textMuted
                          : AppTheme.textMutedLight,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wealth & Finances Screen
// ─────────────────────────────────────────────────────────────────────────────

class WealthFinancesScreen extends StatelessWidget {
  final String locale;
  const WealthFinancesScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Wealth & Finances',
      titleHi: 'धन और वित्त',
      emoji: '💰',
      descriptionEn:
          'Discover financial tendencies, wealth potential, and money management patterns indicated by your palm\'s lines and mounts.',
      descriptionHi:
          'आपकी हथेली की रेखाओं और पर्वतों द्वारा संकेतित वित्तीय प्रवृत्तियों, धन क्षमता और धन प्रबंधन पैटर्न की खोज करें।',
      featureKey: 'wealth_analysis',
      accessFeature: PremiumFeatures.wealthFinances,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Career & Business Screen
// ─────────────────────────────────────────────────────────────────────────────

class CareerBusinessScreen extends StatelessWidget {
  final String locale;
  const CareerBusinessScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Career & Business',
      titleHi: 'करियर और व्यवसाय',
      emoji: '💼',
      descriptionEn:
          'Understand your career direction, professional strengths, and business potential as revealed by your Fate Line, Sun Line, and other career indicators.',
      descriptionHi:
          'आपकी भाग्य रेखा, सूर्य रेखा और अन्य करियर संकेतकों द्वारा प्रकट करियर दिशा, पेशेवर शक्तियों और व्यावसायिक क्षमता को समझें।',
      featureKey: 'career_analysis',
      accessFeature: PremiumFeatures.careerBusiness,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Future Tendencies Screen
// ─────────────────────────────────────────────────────────────────────────────

class FutureTendenciesScreen extends StatelessWidget {
  final String locale;
  const FutureTendenciesScreen({super.key, this.locale = 'en'});

  @override
  Widget build(BuildContext context) {
    return _PremiumContentScreen(
      titleEn: 'Future Tendencies',
      titleHi: 'भविष्य की प्रवृत्तियां',
      emoji: '🔮',
      descriptionEn:
          'Explore the tendencies and patterns your palm suggests for your future — areas of growth, potential challenges, and life direction.',
      descriptionHi:
          'आपकी हथेली द्वारा सुझाई गई भविष्य की प्रवृत्तियों और पैटर्न की खोज करें — विकास के क्षेत्र, संभावित चुनौतियां और जीवन दिशा।',
      featureKey: 'health_analysis',
      accessFeature: PremiumFeatures.futureTendencies,
      locale: locale,
      analyticsEvent: HastVedaEvents.readingViewed,
    );
  }
}
