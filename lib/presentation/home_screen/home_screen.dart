import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../services/app_strings.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../widgets/hastveda_error_widget.dart';
import '../../widgets/luxury_surface.dart';
import '../../widgets/premium_status_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _recentReadings = [];
  bool _isLoading = true;
  String? _loadError;
  bool? _isPremium;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Payment success notifies this without remounting the home route.
    if (context.watch<EntitlementNotifier>().isPremium && _isPremium != true) {
      _isPremium = true;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      await _readHome().timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Home load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _readHome() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Force-refresh entitlements on every home screen load so Premium
    // state is always current (handles post-payment, post-login cases).
    final isPremium = await EntitlementService.instance.isPremiumUser(
      forceRefresh: true,
    );

    final profile = await SupabaseService.instance.client
        .from('user_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    final readings = await SupabaseService.instance.client
        .from('reading_history')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(3);

    if (!mounted) return;
    final livePremium = context.read<EntitlementNotifier>().isPremium;
    setState(() {
      _isPremium = isPremium || livePremium;
      _userProfile = profile;
      _recentReadings = List<Map<String, dynamic>>.from(readings);
      _isLoading = false;
    });
  }

  String _greeting(AppStrings s) {
    final hour = DateTime.now().hour;
    if (hour < 12) return s.goodMorning;
    if (hour < 17) return s.goodAfternoon;
    return s.goodEvening;
  }

  String _getUserName() {
    final name = _userProfile?['full_name'] as String?;
    if (name != null && name.isNotEmpty) {
      return name.split(' ').first;
    }
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) return email.split('@').first;
    } catch (e) {
      debugPrint('Home name fallback: $e');
    }
    return 'Guest';
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = themeProvider.isDark;
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final hasReadings = _recentReadings.isNotEmpty;

    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final outline = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final primaryColor = AppTheme.gold;

    return Scaffold(
      backgroundColor: bg,
      body: LuxuryBackdrop(
        child: Column(
        children: [
          AppBarWidget(
            title: 'HastVeda',
            actions: [
              GestureDetector(
                onTap: () => context.push(AppRoutes.premiumPaywall),
                child: const PremiumStatusWidget(compact: true),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.go(AppRoutes.notifications),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: surfaceEl,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: outline),
                  ),
                  child: CustomIconWidget(
                    iconName: 'notifications_outlined',
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondaryLight,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.push(AppRoutes.profile),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _getUserName().isNotEmpty
                          ? _getUserName()[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          Expanded(
            child: _loadError != null
                ? HastVedaInlineError(
                    title: s.somethingWentWrong,
                    message: s.troubleConnecting,
                    onRetry: _loadData,
                  )
                : RefreshIndicator(
                    color: primaryColor,
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isTablet ? 600 : double.infinity,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 20),
                                Text(
                                  _greeting(s),
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 2.4,
                                    color: AppTheme.gold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getUserName(),
                                  style: AppTheme.display(
                                    34,
                                    color: textPri,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formattedDate(),
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: textSec,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const PremiumStatusWidget(),
                                const SizedBox(height: 20),
                                _ScanCtaCard(
                                  onScan: () =>
                                      context.push(AppRoutes.palmScanScreen),
                                  s: s,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 20),
                                _TodaysHighlightSection(
                                  hasReadings: hasReadings,
                                  onScan: () =>
                                      context.push(AppRoutes.palmScanScreen),
                                  onViewPredictions: () =>
                                      context.push(AppRoutes.predictionsScreen),
                                  s: s,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 20),
                                _RecentReadingsSection(
                                  readings: _recentReadings,
                                  isLoading: _isLoading,
                                  onViewAll: () =>
                                      context.push(AppRoutes.readingHistory),
                                  onScan: () =>
                                      context.push(AppRoutes.palmScanScreen),
                                  s: s,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 20),
                                _PremiumFeaturesRow(s: s, isDark: isDark),
                                const SizedBox(height: 20),
                                // Show Ask HastVeda card for Premium users,
                                // or the upgrade banner for free users.
                                if (_isPremium == true)
                                  _AskHastVedaCard(isDark: isDark)
                                else ...[
                                  _AskHastVedaCard(
                                    isDark: isDark,
                                    payPerQuestion: true,
                                  ),
                                  const SizedBox(height: 12),
                                  _PremiumBanner(
                                    onTap: () =>
                                        context.push(AppRoutes.premiumPaywall),
                                    s: s,
                                    isDark: isDark,
                                  ),
                                ],
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
        ),
      ),
    );
  }

  String _formattedDate() {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class _ScanCtaCard extends StatelessWidget {
  final VoidCallback onScan;
  final AppStrings s;
  final bool isDark;
  const _ScanCtaCard({
    required this.onScan,
    required this.s,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onScan,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.goldGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppTheme.gold.withAlpha(70),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.back_hand_rounded, color: Color(0xFF14110A), size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.scanYourPalm,
                    style: AppTheme.display(
                      26,
                      color: const Color(0xFF14110A),
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI palm intelligence, in your hands',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: const Color(0xFF14110A).withAlpha(190),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF14110A).withAlpha(28),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFF14110A),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ask HastVeda Card — shown to Premium users instead of the upgrade banner
// ─────────────────────────────────────────────────────────────────────────────

class _AskHastVedaCard extends StatelessWidget {
  final bool isDark;
  final bool payPerQuestion;
  const _AskHastVedaCard({
    required this.isDark,
    this.payPerQuestion = false,
  });

  @override
  Widget build(BuildContext context) {
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final primaryColor = AppTheme.gold;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.askHastveda),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0A2E), Color(0xFF2A1200)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.purpleMutedLight, AppTheme.goldMutedLight],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withAlpha(80)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withAlpha(30),
              ),
              child: Icon(
                Icons.psychology_rounded,
                color: primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask HastVeda',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    payPerQuestion
                        ? 'One question · ₹59 (₹50 + GST)'
                        : '2 free questions each month · ₹59 after that',
                    style: GoogleFonts.outfit(fontSize: 12, color: textSec),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Ask Now',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaysHighlightSection extends StatelessWidget {
  final bool hasReadings;
  final VoidCallback onScan;
  final VoidCallback onViewPredictions;
  final AppStrings s;
  final bool isDark;

  const _TodaysHighlightSection({
    required this.hasReadings,
    required this.onScan,
    required this.onViewPredictions,
    required this.s,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final outline = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final textMut = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;
    final primaryColor = AppTheme.gold;
    final goldMutedColor = isDark
        ? AppTheme.goldMuted
        : AppTheme.goldMutedLight;

    if (!hasReadings) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceEl,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: outline),
        ),
        child: Column(
          children: [
            Icon(Icons.back_hand_outlined, size: 48, color: textMut),
            const SizedBox(height: 12),
            Text(
              s.yourPalmJourney,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.startFirstScan,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: textSec,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton.icon(
                onPressed: onScan,
                icon: const Icon(
                  Icons.back_hand_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  s.scanYourPalm,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
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
            ),
          ],
        ),
      );
    }

    return _PersonalizedHighlightLoader(
      onViewPredictions: onViewPredictions,
      isDark: isDark,
      surfaceEl: surfaceEl,
      outline: outline,
      textPri: textPri,
      textSec: textSec,
      textMut: textMut,
      primaryColor: primaryColor,
      goldMutedColor: goldMutedColor,
      s: s,
    );
  }
}

/// Loads the latest daily insight from the DB and renders it with full depth.
class _PersonalizedHighlightLoader extends StatefulWidget {
  final VoidCallback onViewPredictions;
  final bool isDark;
  final Color surfaceEl;
  final Color outline;
  final Color textPri;
  final Color textSec;
  final Color textMut;
  final Color primaryColor;
  final Color goldMutedColor;
  final AppStrings s;

  const _PersonalizedHighlightLoader({
    required this.onViewPredictions,
    required this.isDark,
    required this.surfaceEl,
    required this.outline,
    required this.textPri,
    required this.textSec,
    required this.textMut,
    required this.primaryColor,
    required this.goldMutedColor,
    required this.s,
  });

  @override
  State<_PersonalizedHighlightLoader> createState() =>
      _PersonalizedHighlightLoaderState();
}

class _PersonalizedHighlightLoaderState
    extends State<_PersonalizedHighlightLoader> {
  String? _insightText;
  String? _guidanceText;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInsight();
  }

  Future<void> _loadInsight() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final localeProvider = context.read<LocaleProvider>();
      final lang = localeProvider.languageCode;
      final isHindi = lang == 'hi' || lang == 'hi-Latn';

      // Load the latest completed palm analysis for daily insight
      final analysis = await SupabaseService.instance.client
          .from('palm_analysis')
          .select('summary, summary_hi, personality_analysis, life_analysis')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Also try the predictions table for a stored daily insight
      final prediction = await SupabaseService.instance.client
          .from('predictions')
          .select('content, short_summary, metadata')
          .eq('user_id', userId)
          .eq('time_period', 'daily')
          .eq('is_featured', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      String? insight;
      String? guidance;

      if (prediction != null) {
        final meta = prediction['metadata'] as Map<String, dynamic>?;
        if (isHindi && meta != null) {
          final hiContent = meta['content_hi'] as String?;
          if (hiContent != null && hiContent.isNotEmpty) {
            insight = hiContent;
          }
        }
        insight ??=
            prediction['content'] as String? ??
            prediction['short_summary'] as String?;
      }

      // If no prediction, build from analysis summary
      if ((insight == null || insight.isEmpty) && analysis != null) {
        if (isHindi) {
          insight =
              analysis['summary_hi'] as String? ??
              analysis['summary'] as String?;
        } else {
          insight = analysis['summary'] as String?;
        }

        // Extract a guidance point from personality_analysis
        final pa = analysis['personality_analysis'] as Map<String, dynamic>?;
        if (pa != null) {
          final traits = isHindi
              ? (pa['key_traits_hi'] as List?)?.cast<String>()
              : (pa['key_traits_en'] as List?)?.cast<String>();
          if (traits != null && traits.isNotEmpty) {
            guidance = isHindi
                ? 'आज का मार्गदर्शन: अपनी ${traits.first} की शक्ति का उपयोग करें।'
                : 'Today\'s guidance: Lean into your ${traits.first.toLowerCase()} today.';
          }
        }
      }

      setState(() {
        _insightText = insight;
        _guidanceText = guidance;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Highlight load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: widget.surfaceEl,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.outline),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: widget.primaryColor,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final hasContent = _insightText != null && _insightText!.isNotEmpty;

    return GestureDetector(
      onTap: widget.onViewPredictions,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: widget.surfaceEl,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.primaryColor.withAlpha(60)),
          boxShadow: [
            BoxShadow(
              color: widget.primaryColor.withAlpha(20),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny, color: widget.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  widget.s.todaysHighlight,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: widget.textPri,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: widget.primaryColor,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.goldMutedColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                hasContent
                    ? _insightText!
                    : 'Your palm patterns suggest a day of focused energy and meaningful connections. Scan your palm to get your personalized daily insight.',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: widget.textPri,
                  height: 1.6,
                ),
              ),
            ),
            if (_guidanceText != null && _guidanceText!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.primaryColor.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: widget.primaryColor,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _guidanceText!,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: widget.textSec,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '⚠️ Interpretive only — not a guaranteed prediction',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: widget.textMut,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentReadingsSection extends StatelessWidget {
  final List<Map<String, dynamic>> readings;
  final bool isLoading;
  final VoidCallback onViewAll;
  final VoidCallback onScan;
  final AppStrings s;
  final bool isDark;

  const _RecentReadingsSection({
    required this.readings,
    required this.isLoading,
    required this.onViewAll,
    required this.onScan,
    required this.s,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final outline = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final textMut = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;
    final primaryColor = AppTheme.gold;
    final goldMutedColor = isDark
        ? AppTheme.goldMuted
        : AppTheme.goldMutedLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              s.recentReadings,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
            ),
            if (readings.isNotEmpty)
              GestureDetector(
                onTap: onViewAll,
                child: Row(
                  children: [
                    Text(
                      s.viewAll,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, color: primaryColor, size: 16),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: CircularProgressIndicator(
                color: primaryColor,
                strokeWidth: 2,
              ),
            ),
          )
        else if (readings.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceEl,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: outline),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: textMut, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.noReadingsYet,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPri,
                        ),
                      ),
                      Text(
                        'Your palm readings will appear here',
                        style: GoogleFonts.outfit(fontSize: 12, color: textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: surfaceEl,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: outline),
            ),
            child: Column(
              children: List.generate(readings.length, (index) {
                final reading = readings[index];
                final createdAt = reading['created_at'] != null
                    ? DateTime.tryParse(reading['created_at'] as String)
                    : null;
                final isFirst = index == 0;
                final isLast = index == readings.length - 1;
                return Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: isFirst ? goldMutedColor : surfaceEl,
                        borderRadius: BorderRadius.only(
                          topLeft: isFirst
                              ? const Radius.circular(16)
                              : Radius.zero,
                          topRight: isFirst
                              ? const Radius.circular(16)
                              : Radius.zero,
                          bottomLeft: isLast
                              ? const Radius.circular(16)
                              : Radius.zero,
                          bottomRight: isLast
                              ? const Radius.circular(16)
                              : Radius.zero,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor.withAlpha(20),
                              ),
                              child: Icon(
                                Icons.back_hand_rounded,
                                color: primaryColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    createdAt != null
                                        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                                        : 'Palm Reading',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: textSec,
                                    ),
                                  ),
                                  Text(
                                    'Palm reading completed',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      color: textPri,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast) Divider(height: 1, color: outline, indent: 72),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _PremiumFeaturesRow extends StatelessWidget {
  final AppStrings s;
  final bool isDark;
  const _PremiumFeaturesRow({required this.s, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.premiumFeatures,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FeatureCard(
                emoji: '❤️',
                title: s.coupleReading,
                subtitle: 'Check compatibility',
                onTap: () => context.push(AppRoutes.coupleReading),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FeatureCard(
                emoji: '📊',
                title: s.detailedReport,
                subtitle: '19 sections',
                onTap: () => context.push(AppRoutes.detailedReport),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FeatureCard(
                emoji: '🌿',
                title: 'Remedies',
                subtitle: 'Vedic guidance',
                onTap: () => context.push(AppRoutes.remedies),
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;

  const _FeatureCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final outline = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surfaceEl,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.outfit(fontSize: 11, color: textSec),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  final VoidCallback onTap;
  final AppStrings s;
  final bool isDark;
  const _PremiumBanner({
    required this.onTap,
    required this.s,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final primaryColor = AppTheme.gold;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.purpleMuted, AppTheme.goldMuted],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.purpleMutedLight, AppTheme.goldMutedLight],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withAlpha(60)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withAlpha(30),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.unlockCompleteStory,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Detailed lines, predictions & more',
                    style: GoogleFonts.outfit(fontSize: 12, color: textSec),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Explore',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
