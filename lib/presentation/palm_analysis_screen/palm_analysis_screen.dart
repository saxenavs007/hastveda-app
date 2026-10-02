import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/locale_provider.dart';
import '../../theme/app_theme.dart';

class PalmAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic>? analysisData;
  final String locale;
  // Optional: load from DB by analysisId (used when navigating from history)
  final String? analysisId;

  const PalmAnalysisScreen({
    super.key,
    this.analysisData,
    this.locale = 'en',
    this.analysisId,
  });

  @override
  State<PalmAnalysisScreen> createState() => _PalmAnalysisScreenState();
}

class _PalmAnalysisScreenState extends State<PalmAnalysisScreen> {
  late String _locale;
  Map<String, dynamic>? _loadedData;
  bool _isLoadingFromDb = false;

  /// Whether the signed-in user holds Premium. Locks are `policy && !premium`,
  /// so a Premium user never sees a lock and a free user always sees the same
  /// locks regardless of what the AI wrote into the analysis row.
  bool _hasPremium = false;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
    analytics.track(
      HastVedaEvents.readingViewed,
      properties: {
        'reading_type': 'single',
        'has_real_data': widget.analysisData != null,
      },
    );
    // If no analysisData passed but analysisId is provided, load from DB
    if (widget.analysisData == null && widget.analysisId != null) {
      _loadAnalysisFromDb(widget.analysisId!);
    }
    _loadEntitlement();
  }

  Future<void> _loadEntitlement() async {
    final premium = await EntitlementService.instance.isPremiumUser(
      forceRefresh: true,
    );
    if (!mounted) return;
    final livePremium = context.read<EntitlementNotifier>().isPremium;
    setState(() => _hasPremium = premium || livePremium);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync locale from provider on first dependency resolution and on changes.
    // This ensures the screen always uses the current app language, regardless
    // of what locale was passed via the route parameter (e.g. history navigation
    // where widget.locale may default to 'en').
    final providerLocale = context.watch<LocaleProvider>().languageCode;
    if (_locale != providerLocale) {
      _locale = providerLocale;
    }
    // Premium granted while this route is under the paywall.
    if (context.watch<EntitlementNotifier>().isPremium) {
      _hasPremium = true;
    }
  }

  Future<void> _loadAnalysisFromDb(String analysisId) async {
    setState(() => _isLoadingFromDb = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('palm_analysis')
          .select()
          .eq('id', analysisId)
          .eq('user_id', userId)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _loadedData = _buildDataFromDbRecord(data);
          _isLoadingFromDb = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingFromDb = false);
      }
    } catch (e) {
      debugPrint('PalmAnalysisScreen load error: $e');
      if (mounted) setState(() => _isLoadingFromDb = false);
    }
  }

  /// Build display data map from a raw palm_analysis DB record
  Map<String, dynamic> _buildDataFromDbRecord(Map<String, dynamic> record) {
    final pa = record['personality_analysis'] as Map<String, dynamic>? ?? {};
    final la = record['love_analysis'] as Map<String, dynamic>? ?? {};
    final ca = record['career_analysis'] as Map<String, dynamic>? ?? {};
    final wa = record['wealth_analysis'] as Map<String, dynamic>? ?? {};
    final ha = record['health_analysis'] as Map<String, dynamic>? ?? {};
    final lfa = record['life_analysis'] as Map<String, dynamic>? ?? {};

    return {
      'analysis_id': record['id'],
      'scan_id': record['scan_id'],
      'hand_side': record['hand_side'] ?? 'right',
      'overall_score': (record['overall_score'] as num?)?.toInt() ?? 75,
      'summary': record['summary'] ?? '',
      'summary_en': record['summary'] ?? '',
      'summary_hi': record['summary_hi'] ?? record['summary'] ?? '',
      'confidence_score':
          (record['confidence_score'] as num?)?.toDouble() ?? 75.0,
      'is_premium': record['is_premium'] ?? false,
      'key_traits': (pa['key_traits_en'] as List?)?.cast<String>() ?? [],
      'key_traits_en': (pa['key_traits_en'] as List?)?.cast<String>() ?? [],
      'key_traits_hi': (pa['key_traits_hi'] as List?)?.cast<String>() ?? [],
      // Read daily_insight from DB record — these fields are stored by the Edge Function
      'daily_insight': record['daily_insight_en'] ?? '',
      'daily_insight_en': record['daily_insight_en'] ?? '',
      'daily_insight_hi': record['daily_insight_hi'] ?? '',
      'confidence_note': null,
      'confidence_note_en': null,
      'confidence_note_hi': null,
      'personality': {
        'title': 'Personality',
        'title_en': 'Personality',
        'title_hi': 'व्यक्तित्व',
        'content': pa['interpretation_en'] ?? '',
        'content_en': pa['interpretation_en'] ?? '',
        'content_hi': pa['interpretation_hi'] ?? '',
        'score': (pa['score'] as num?)?.toInt() ?? 75,
        'locked': pa['is_premium_locked'] ?? false,
      },
      'love_relationships': {
        'title': 'Love & Relationships',
        'title_en': 'Love & Relationships',
        'title_hi': 'प्रेम और रिश्ते',
        'content': la['interpretation_en'] ?? '',
        'content_en': la['interpretation_en'] ?? '',
        'content_hi': la['interpretation_hi'] ?? '',
        'score': (la['score'] as num?)?.toInt() ?? 75,
        'locked': la['is_premium_locked'] ?? false,
      },
      'career': {
        'title': 'Career',
        'title_en': 'Career',
        'title_hi': 'करियर',
        'content': ca['interpretation_en'] ?? '',
        'content_en': ca['interpretation_en'] ?? '',
        'content_hi': ca['interpretation_hi'] ?? '',
        'score': (ca['score'] as num?)?.toInt() ?? 75,
        'locked': ca['is_premium_locked'] ?? false,
      },
      'wealth': {
        'title': 'Wealth',
        'title_en': 'Wealth',
        'title_hi': 'धन',
        'content': wa['interpretation_en'] ?? '',
        'content_en': wa['interpretation_en'] ?? '',
        'content_hi': wa['interpretation_hi'] ?? '',
        'score': (wa['score'] as num?)?.toInt() ?? 75,
        'locked': wa['is_premium_locked'] ?? false,
      },
      'health': {
        'title': 'Health',
        'title_en': 'Health',
        'title_hi': 'स्वास्थ्य',
        'content': ha['interpretation_en'] ?? '',
        'content_en': ha['interpretation_en'] ?? '',
        'content_hi': ha['interpretation_hi'] ?? '',
        'score': (ha['score'] as num?)?.toInt() ?? 75,
        'locked': ha['is_premium_locked'] ?? false,
      },
      'life_path': {
        'title': 'Life Path',
        'title_en': 'Life Path',
        'title_hi': 'जीवन पथ',
        'content': lfa['interpretation_en'] ?? '',
        'content_en': lfa['interpretation_en'] ?? '',
        'content_hi': lfa['interpretation_hi'] ?? '',
        'score': (lfa['score'] as num?)?.toInt() ?? 75,
        'locked': lfa['is_premium_locked'] ?? false,
      },
      'future_tendencies': {
        'title': 'Future Tendencies',
        'title_en': 'Future Tendencies',
        'title_hi': 'भविष्य की प्रवृत्तियां',
        'content': pa['future_tendencies_en'] ?? '',
        'content_en': pa['future_tendencies_en'] ?? '',
        'content_hi': pa['future_tendencies_hi'] ?? '',
        'score': (pa['future_tendencies_score'] as num?)?.toInt() ?? 75,
        'locked': pa['future_tendencies_locked'] ?? true,
      },
    };
  }

  bool get _isHindi => _locale == 'hi';

  Map<String, dynamic> get _data => widget.analysisData ?? _loadedData ?? {};

  bool get _hasRealData => _data.isNotEmpty && _data['analysis_id'] != null;

  // ── Category helpers ──────────────────────────────────────────────────────
  // Returns language-aware content from category map

  int _getScore(String key, {int fallback = 75}) {
    final cat = _data[key];
    if (cat is Map) return (cat['score'] as num?)?.toInt() ?? fallback;
    return fallback;
  }

  /// Lock state for a `palm_analysis` category (personality, career, …).
  ///
  /// Resolved from [PremiumFeatures] plus the user's entitlement — never from
  /// the row's `is_premium_locked` flag, which is AI-authored and drifts.
  bool _isLocked(String categoryKey) {
    final feature = PremiumFeatures.analysisCategoryFeature[categoryKey];
    if (feature == null) return false;
    return _isFeatureLocked(feature);
  }

  /// Lock state for a surface that has no analysis category of its own
  /// (Sun Line, Mercury Line, Marriage Indicators, Mount Analysis, Palm Marks).
  bool _isFeatureLocked(String feature) =>
      !PremiumFeatures.isFree(feature) && !_hasPremium;

  String _getCategoryContent(String key) {
    final cat = _data[key];
    if (cat is Map) {
      // Prefer language-specific content
      if (_isHindi) {
        final hi = cat['content_hi'] as String?;
        if (hi != null && hi.isNotEmpty) return hi;
      }
      final en = cat['content_en'] as String?;
      if (en != null && en.isNotEmpty) return en;
      return cat['content'] as String? ?? '';
    }
    return '';
  }

  String _getSummary() {
    if (_isHindi) {
      final hi = _data['summary_hi'] as String?;
      if (hi != null && hi.isNotEmpty) return hi;
    }
    final en = _data['summary_en'] as String?;
    if (en != null && en.isNotEmpty) return en;
    return _data['summary'] as String? ??
        (_isHindi
            ? 'आपका हस्तरेखा विश्लेषण तैयार है। प्रत्येक अनुभाग में विस्तृत जानकारी देखें।'
            : 'Your palm analysis is ready. Explore each section for detailed insights.');
  }

  List<String> _getKeyTraits() {
    if (_isHindi) {
      final hi = (_data['key_traits_hi'] as List?)?.cast<String>();
      if (hi != null && hi.isNotEmpty) return hi;
    }
    final en = (_data['key_traits_en'] as List?)?.cast<String>();
    if (en != null && en.isNotEmpty) return en;
    return (_data['key_traits'] as List?)?.cast<String>() ?? [];
  }

  String _getDailyInsight() {
    if (_isHindi) {
      final hi = _data['daily_insight_hi'] as String?;
      if (hi != null && hi.isNotEmpty) return hi;
    }
    final en = _data['daily_insight_en'] as String?;
    if (en != null && en.isNotEmpty) return en;
    return _data['daily_insight'] as String? ?? '';
  }

  String? _getConfidenceNote() {
    if (_isHindi) {
      final hi = _data['confidence_note_hi'] as String?;
      if (hi != null && hi.isNotEmpty) return hi;
    }
    final en = _data['confidence_note_en'] as String?;
    if (en != null && en.isNotEmpty) return en;
    return _data['confidence_note'] as String?;
  }

  // ── Back navigation ────────────────────────────────────────────────────────
  //
  // The three ways a user lands on this screen produce three different stack
  // shapes, and the AppBar arrow, the Android system back button, and Reading
  // History → back all have to do the right thing on each of them:
  //
  //   1. From scan flow — palm_scan_screen pushReplacement's this route, so the
  //      camera page is no longer on the stack. `pop()` from here would return
  //      to the shell's Home tab in the best case, but on release APKs
  //      `context.pop()` can silently no-op if go_router's imperative stack has
  //      been left in a shell-branch state. `context.go` is stack-clearing and
  //      deterministic, so scan-flow back always routes explicitly to Home.
  //
  //   2. From Reading History — pushed with `{'analysis_id': ...}` and no scan
  //      data. Popping is the correct behaviour (returns to the history list),
  //      with a Home fallback if the stack has somehow been cleared.
  //
  //   3. From a nested Palm Line screen (palm_line_screen.dart:355 pushes
  //      /palm-analysis) — treated like scan flow: go straight to Home rather
  //      than leaving a stale analysis in the stack.
  //
  // Both the AppBar leading button AND the PopScope Android-back handler route
  // through this single method so behaviour cannot drift.
  void _handleBack() {
    final cameFromHistory =
        widget.analysisData == null && widget.analysisId != null;

    if (cameFromHistory && context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.homeScreen);
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider so the widget rebuilds when language changes.
    context.watch<LocaleProvider>();

    if (_isLoadingFromDb) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: AppTheme.backgroundDark,
          appBar: AppBar(
            backgroundColor: AppTheme.surfaceDark,
            foregroundColor: AppTheme.textPrimary,
            title: Text(
              _isHindi ? 'हस्तरेखा विश्लेषण' : 'Palm Analysis',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: _handleBack,
            ),
          ),
          body: const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
      );
    }

    final overallScore = (_data['overall_score'] as num?)?.toInt() ?? 78;
    final summary = _getSummary();
    final confidenceScore =
        (_data['confidence_score'] as num?)?.toDouble() ?? 75.0;
    final confidenceNote = _getConfidenceNote();
    final keyTraits = _getKeyTraits();
    final dailyInsight = _getDailyInsight();
    final isPremium = _data['is_premium'] as bool? ?? false;

    return PopScope(
      // Intercept the Android system back button so it routes through the same
      // deterministic handler as the AppBar arrow. Without this, the OS-level
      // back gesture calls Navigator.maybePop directly and hits the same broken
      // shell-branch stack that made "Rocket's" earlier fix ineffective in the
      // release APK.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: _buildScaffold(
        overallScore: overallScore,
        summary: summary,
        confidenceScore: confidenceScore,
        confidenceNote: confidenceNote,
        keyTraits: keyTraits,
        dailyInsight: dailyInsight,
        isPremium: isPremium,
      ),
    );
  }

  Widget _buildScaffold({
    required int overallScore,
    required String summary,
    required double confidenceScore,
    required String? confidenceNote,
    required List<String> keyTraits,
    required String dailyInsight,
    required bool isPremium,
  }) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        foregroundColor: AppTheme.textPrimary,
        title: Text(
          _isHindi ? 'हस्तरेखा विश्लेषण' : 'Palm Analysis',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _handleBack,
        ),
        actions: [
          if (_hasRealData)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isPremium
                      ? AppTheme.primary.withAlpha(30)
                      : Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPremium
                        ? AppTheme.primary.withAlpha(80)
                        : Colors.white.withAlpha(30),
                  ),
                ),
                child: Text(
                  isPremium
                      ? (_isHindi ? 'प्रीमियम' : 'Premium')
                      : (_isHindi ? 'मुफ़्त' : 'Free'),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPremium ? AppTheme.primary : Colors.white54,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Confidence note (if image quality was borderline)
            if (confidenceNote != null && confidenceNote.isNotEmpty)
              _ConfidenceNoteCard(note: confidenceNote),

            // Overview card
            _OverviewCard(
              score: overallScore,
              summary: summary,
              confidenceScore: confidenceScore,
              keyTraits: keyTraits,
              isHindi: _isHindi,
              isRealData: _hasRealData,
            ),
            const SizedBox(height: 16),

            // Daily insight (if available)
            if (dailyInsight.isNotEmpty)
              _DailyInsightCard(insight: dailyInsight, isHindi: _isHindi),

            const SizedBox(height: 20),

            // Palm Lines section
            _SectionHeader(
              title: _isHindi ? 'हस्तरेखाएं' : 'Palm Lines',
              icon: Icons.back_hand_outlined,
            ),
            const SizedBox(height: 12),
            _LineCard(
              emoji: '❤️',
              title: _isHindi ? 'हृदय रेखा' : 'Heart Line',
              subtitle: _isHindi
                  ? 'भावनात्मक स्वास्थ्य और प्रेम'
                  : 'Emotional health & love',
              score: _getScore('love_relationships', fallback: 78),
              isLocked: _isLocked('love_relationships'),
              content: _getCategoryContent('love_relationships'),
              onTap: () =>
                  context.push('${AppRoutes.heartLine}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _LineCard(
              emoji: '🧠',
              title: _isHindi ? 'मस्तिष्क रेखा' : 'Head Line',
              subtitle: _isHindi
                  ? 'बुद्धि और मानसिक शक्ति'
                  : 'Intelligence & mental strength',
              score: _getScore('personality', fallback: 85),
              isLocked: _isLocked('personality'),
              content: _getCategoryContent('personality'),
              onTap: () =>
                  context.push('${AppRoutes.headLine}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _LineCard(
              emoji: '✋',
              title: _isHindi ? 'जीवन रेखा' : 'Life Line',
              subtitle: _isHindi
                  ? 'जीवन शक्ति और स्वास्थ्य'
                  : 'Vitality & health',
              score: _getScore('life_path', fallback: 72),
              isLocked: _isLocked('life_path'),
              content: _getCategoryContent('life_path'),
              onTap: () =>
                  context.push('${AppRoutes.lifeLine}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _PremiumLineCard(
              emoji: '🌟',
              title: _isHindi ? 'भाग्य रेखा' : 'Fate Line',
              subtitle: _isHindi ? 'करियर और भाग्य' : 'Career & destiny',
              isLocked: _isLocked('career'),
              content: _getCategoryContent('career'),
              onTap: () =>
                  context.push('${AppRoutes.fateLine}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _PremiumLineCard(
              emoji: '☀️',
              title: _isHindi ? 'सूर्य रेखा' : 'Sun / Success Line',
              subtitle: _isHindi ? 'सफलता और प्रसिद्धि' : 'Success & fame',
              isLocked: _isFeatureLocked(PremiumFeatures.sunLine),
              content: '',
              onTap: () => context.push('${AppRoutes.sunLine}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _PremiumLineCard(
              emoji: '💬',
              title: _isHindi ? 'बुध रेखा' : 'Mercury Line',
              subtitle: _isHindi
                  ? 'संचार और व्यापार'
                  : 'Communication & business',
              isLocked: _isFeatureLocked(PremiumFeatures.mercuryLine),
              content: '',
              onTap: () =>
                  context.push('${AppRoutes.mercuryLine}?locale=$_locale'),
            ),
            const SizedBox(height: 20),

            // Special indicators
            _SectionHeader(
              title: _isHindi ? 'विशेष संकेत' : 'Special Indicators',
              icon: Icons.auto_awesome_outlined,
            ),
            const SizedBox(height: 12),
            _PremiumLineCard(
              emoji: '💍',
              title: _isHindi ? 'विवाह संकेत' : 'Marriage Indicators',
              subtitle: _isHindi ? 'प्रेम और विवाह' : 'Love & marriage',
              isLocked: _isFeatureLocked(PremiumFeatures.marriageIndicators),
              content: '',
              onTap: () => context.push(
                '${AppRoutes.marriageIndicators}?locale=$_locale',
              ),
            ),
            const SizedBox(height: 8),
            _PremiumLineCard(
              emoji: '🏔️',
              title: _isHindi ? 'पर्वत विश्लेषण' : 'Mount Analysis',
              subtitle: _isHindi ? 'ग्रहों का प्रभाव' : 'Planetary influences',
              isLocked: _isFeatureLocked(PremiumFeatures.mountAnalysis),
              content: '',
              onTap: () =>
                  context.push('${AppRoutes.mountAnalysis}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _PremiumLineCard(
              emoji: '✨',
              title: _isHindi ? 'हस्त चिह्न' : 'Palm Marks & Signs',
              subtitle: _isHindi ? 'विशेष चिह्न' : 'Special marks',
              isLocked: _isFeatureLocked(PremiumFeatures.palmMarks),
              content: '',
              onTap: () =>
                  context.push('${AppRoutes.palmMarks}?locale=$_locale'),
            ),
            const SizedBox(height: 20),

            // Life insights
            _SectionHeader(
              title: _isHindi ? 'जीवन अंतर्दृष्टि' : 'Life Insights',
              icon: Icons.psychology_outlined,
            ),
            const SizedBox(height: 12),
            _InsightCard(
              emoji: '🧠',
              title: _isHindi ? 'व्यक्तित्व' : 'Personality',
              content: _getCategoryContent('personality'),
              isLocked: _isLocked('personality'), // free by policy
              onTap: () =>
                  context.push('${AppRoutes.personality}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _InsightCard(
              emoji: '❤️',
              title: _isHindi ? 'प्रेम और रिश्ते' : 'Love & Relationships',
              content: _getCategoryContent('love_relationships'),
              isLocked: _isLocked('love_relationships'), // free by policy
              onTap: () => context.push(
                '${AppRoutes.loveRelationships}?locale=$_locale',
              ),
            ),
            const SizedBox(height: 8),
            _InsightCard(
              emoji: '💰',
              title: _isHindi ? 'धन और वित्त' : 'Wealth & Finances',
              content: _getCategoryContent('wealth'),
              isLocked: _isLocked('wealth'),
              onTap: () =>
                  context.push('${AppRoutes.wealthFinances}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _InsightCard(
              emoji: '💼',
              title: _isHindi ? 'करियर और व्यापार' : 'Career & Business',
              content: _getCategoryContent('career'),
              isLocked: _isLocked('career'),
              onTap: () =>
                  context.push('${AppRoutes.careerBusiness}?locale=$_locale'),
            ),
            const SizedBox(height: 8),
            _InsightCard(
              emoji: '🔮',
              title: _isHindi ? 'भविष्य की प्रवृत्तियां' : 'Future Tendencies',
              content: _getCategoryContent('future_tendencies'),
              isLocked: _isLocked('future_tendencies'),
              onTap: () =>
                  context.push('${AppRoutes.futureTendencies}?locale=$_locale'),
            ),
            const SizedBox(height: 24),

            // View Palm Profile
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    context.push('${AppRoutes.palmProfile}?locale=$_locale'),
                icon: const Icon(Icons.back_hand_rounded, size: 18),
                label: Text(
                  _isHindi ? 'हस्त प्रोफ़ाइल देखें' : 'View Palm Profile',
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

            // Scan again button
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.palmScanScreen),
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: Text(
                  _isHindi ? 'नई हथेली स्कैन करें' : 'Scan New Palm',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withAlpha(80)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Confidence Note Card ──────────────────────────────────────────────────────

class _ConfidenceNoteCard extends StatelessWidget {
  final String note;
  const _ConfidenceNoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.amber.shade200,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Daily Insight Card ────────────────────────────────────────────────────────

class _DailyInsightCard extends StatelessWidget {
  final String insight;
  final bool isHindi;
  const _DailyInsightCard({required this.insight, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2A0A), Color(0xFF0A1A05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌟', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                isHindi ? 'आज की अंतर्दृष्टि' : "Today's Insight",
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.green.shade300,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white70,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview Card ─────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final int score;
  final String summary;
  final double confidenceScore;
  final List<String> keyTraits;
  final bool isHindi;
  final bool isRealData;

  const _OverviewCard({
    required this.score,
    required this.summary,
    required this.confidenceScore,
    required this.keyTraits,
    required this.isHindi,
    required this.isRealData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withAlpha(30),
                  border: Border.all(color: AppTheme.primary.withAlpha(80)),
                ),
                child: Center(
                  child: Text(
                    '$score',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHindi ? 'समग्र स्कोर' : 'Overall Score',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                    Text(
                      isHindi ? 'हस्तरेखा विश्लेषण' : 'Palm Analysis',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (isRealData)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isHindi ? 'AI विश्लेषण' : 'AI Analyzed',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summary,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white70,
              height: 1.6,
            ),
          ),
          if (keyTraits.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: keyTraits
                  .take(4)
                  .map(
                    (trait) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(40),
                        ),
                      ),
                      child: Text(
                        trait,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isHindi
                  ? '⚠️ हस्तरेखा पारंपरिक व्याख्या है, वैज्ञानिक तथ्य नहीं'
                  : '⚠️ Palmistry is interpretive, not scientific fact',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: Colors.white38,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ── Line Card ─────────────────────────────────────────────────────────────────

class _LineCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final int score;
  final bool isLocked;
  final String content;
  final VoidCallback onTap;

  const _LineCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.isLocked,
    required this.content,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1208),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A2A18)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  if (content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        content,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white38,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  '$score',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white24,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Premium Line Card ─────────────────────────────────────────────────────────

class _PremiumLineCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool isLocked;
  final String content;
  final VoidCallback onTap;

  const _PremiumLineCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isLocked,
    required this.content,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1208),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withAlpha(30)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  if (content.isNotEmpty && !isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        content,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white38,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (isLocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      color: AppTheme.primary,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Premium',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white24,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Insight Card ──────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String content;
  final bool isLocked;
  final VoidCallback onTap;

  const _InsightCard({
    required this.emoji,
    required this.title,
    required this.content,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1208),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A2A18)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (content.isNotEmpty && !isLocked)
                    Text(
                      content,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: Colors.white38,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isLocked)
              const Icon(Icons.lock_rounded, color: AppTheme.primary, size: 16)
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white24,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
