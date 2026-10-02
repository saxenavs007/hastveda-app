// HastVeda Detailed Report Screen
// Generates and displays a comprehensive 19-section palm reading report
// from REAL saved Gemini palm analysis stored in Supabase.
// No mock data — all content is AI-generated from actual palm observations.
//
// Features:
// - 19-section comprehensive premium report
// - Download PDF
// - Share PDF (Android share sheet)
// - Email Report (via Resend/Supabase)
// - Premium access gating

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/connectivity_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/locale_provider.dart';
import '../../services/pdf_export_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_lock_widget.dart';
import '../../presentation/review_screen/review_screen.dart';

class DetailedReportScreen extends StatefulWidget {
  final String locale;
  final String? analysisId;
  final String? readingId;

  const DetailedReportScreen({
    super.key,
    this.locale = 'en',
    this.analysisId,
    this.readingId,
  });

  @override
  State<DetailedReportScreen> createState() => _DetailedReportScreenState();
}

class _DetailedReportScreenState extends State<DetailedReportScreen> {
  bool _isCheckingEntitlement = true;
  bool _hasAccess = false;
  bool _isGenerating = false;
  bool _reportGenerated = false;
  bool _hasPalmAnalysis = false;
  Map<String, dynamic>? _reportData;
  String? _reportId;
  String? _errorMessage;
  String? _resolvedAnalysisId;
  String? _resolvedReadingId;
  DateTime? _generatedAt;
  String? _userName;
  bool _appliedLivePremium = false;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _resolvedAnalysisId = widget.analysisId;
    _resolvedReadingId = widget.readingId;
    _initialize();
    analytics.track(
      HastVedaEvents.detailedReportStarted,
      properties: {'language': widget.locale},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.watch<EntitlementNotifier>().isPremium;
    if (!premium || _hasAccess) return;
    _hasAccess = true;
    _isCheckingEntitlement = false;
    if (_appliedLivePremium) return;
    _appliedLivePremium = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _resolvedAnalysisId == null || _reportGenerated) return;
      await _checkForExistingReport();
      if (mounted) setState(() {});
    });
  }

  Future<void> _initialize() async {
    setState(() => _isCheckingEntitlement = true);

    final hasAccess = await EntitlementService.instance
        .canAccessDetailedReport(forceRefresh: true);

    if (_resolvedAnalysisId == null && _resolvedReadingId != null) {
      await _resolveAnalysisFromReading();
    }

    if (_resolvedAnalysisId == null) {
      await _findLatestAnalysis();
    }

    if (_resolvedAnalysisId != null && hasAccess) {
      await _checkForExistingReport();
    }

    // Fetch user name for personalization
    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId != null) {
        final data = await Supabase.instance.client
            .from('user_profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
        _userName = data?['full_name'] as String?;
      }
    } catch (_) {}

    if (mounted) {
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _hasAccess = hasAccess || premium;
        _hasPalmAnalysis = _resolvedAnalysisId != null;
        _isCheckingEntitlement = false;
      });
    }
  }

  Future<void> _resolveAnalysisFromReading() async {
    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('reading_history')
          .select('analysis_id, metadata')
          .eq('id', _resolvedReadingId!)
          .eq('user_id', userId)
          .maybeSingle();
      if (data != null) {
        _resolvedAnalysisId = data['analysis_id'] as String?;
      }
    } catch (e) {
      debugPrint('Resolve analysis error: $e');
    }
  }

  Future<void> _findLatestAnalysis() async {
    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('palm_analysis')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data != null) {
        _resolvedAnalysisId = data['id'] as String?;
      }
    } catch (e) {
      debugPrint('Find latest analysis error: $e');
    }
  }

  Future<void> _checkForExistingReport() async {
    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('reports')
          .select('id, content, generated_at, created_at')
          .eq('analysis_id', _resolvedAnalysisId!)
          .eq('user_id', userId)
          .eq('report_type', 'detailed_analysis')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data != null &&
          data['content'] != null &&
          (data['content'] as Map).isNotEmpty) {
        final content = data['content'] as Map<String, dynamic>;
        final contentLang =
            (content['metadata'] as Map<String, dynamic>?)?['language'] ?? 'en';
        // Accept both old and new format reports
        if (contentLang == widget.locale) {
          _reportData = content;
          _reportId = data['id'] as String?;
          _generatedAt = data['generated_at'] != null
              ? DateTime.tryParse(data['generated_at'] as String)
              : data['created_at'] != null
              ? DateTime.tryParse(data['created_at'] as String)
              : null;
          _reportGenerated = true;
        }
      }
    } catch (e) {
      debugPrint('Check existing report error: $e');
    }
  }

  Future<void> _generateReport() async {
    if (ConnectivityService.instance.isOffline) {
      final lp = context.read<LocaleProvider>();
      final s = AppStrings.of(lp.languageCode);
      setState(() => _errorMessage = s.internetRequired);
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      if (_resolvedAnalysisId == null) {
        throw Exception(
          _isHindi
              ? 'कोई हस्तरेखा विश्लेषण नहीं मिला। पहले हस्तरेखा स्कैन करें।'
              : 'No palm analysis found. Please scan your palm first.',
        );
      }

      final response = await Supabase.instance.client.functions.invoke(
        'detailed-report',
        body: {
          'analysis_id': _resolvedAnalysisId,
          'reading_id': _resolvedReadingId,
          'language': widget.locale,
          'force_regenerate': false,
        },
      );

      if (response.status != 200) {
        final errorData = response.data as Map<String, dynamic>? ?? {};
        final code = errorData['code'] as String? ?? '';
        if (code == 'ENTITLEMENT_REQUIRED') {
          throw Exception(
            _isHindi
                ? 'विस्तृत रिपोर्ट के लिए प्रीमियम सदस्यता आवश्यक है।'
                : 'Detailed Report requires Premium subscription.',
          );
        }
        throw Exception(
          errorData['error'] as String? ??
              (_isHindi
                  ? 'रिपोर्ट उत्पन्न नहीं हो सकी।'
                  : 'Could not generate report.'),
        );
      }

      final result = response.data as Map<String, dynamic>;
      final report = result['report'] as Map<String, dynamic>?;

      if (report == null || report.isEmpty) {
        throw Exception(
          _isHindi
              ? 'रिपोर्ट डेटा प्राप्त नहीं हुआ।'
              : 'Report data not received.',
        );
      }

      if (mounted) {
        setState(() {
          _reportData = report;
          _reportId = result['report_id'] as String?;
          _generatedAt = result['generated_at'] != null
              ? DateTime.tryParse(result['generated_at'] as String)
              : DateTime.now();
          _reportGenerated = true;
          _isGenerating = false;
        });

        // Trigger review prompt after successful report generation
        if (mounted) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              showReviewDialogIfAppropriate(
                context: context,
                featureContext: ReviewFeatureContext.detailedReport,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isCheckingEntitlement) {
      return Scaffold(
        backgroundColor: isDark
            ? AppTheme.backgroundDark
            : AppTheme.backgroundLight,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (!_hasAccess) {
      return _EntitlementGateScreen(
        isHindi: _isHindi,
        isDark: isDark,
        locale: widget.locale,
      );
    }

    if (_reportGenerated && _reportData != null) {
      return _ReportViewerScreen(
        reportData: _reportData!,
        locale: widget.locale,
        reportId: _reportId,
        generatedAt: _generatedAt,
        isDark: isDark,
        userName: _userName,
      );
    }

    return _ReportGeneratorScreen(
      isHindi: _isHindi,
      isDark: isDark,
      hasPalmAnalysis: _hasPalmAnalysis,
      isGenerating: _isGenerating,
      errorMessage: _errorMessage,
      onGenerate: _generateReport,
      locale: widget.locale,
    );
  }
}

// ============================================================
// ENTITLEMENT GATE SCREEN
// ============================================================

class _EntitlementGateScreen extends StatelessWidget {
  final bool isHindi;
  final bool isDark;
  final String locale;

  const _EntitlementGateScreen({
    required this.isHindi,
    required this.isDark,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1410),
        title: Text(
          isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Report',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1410),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 40),
            PremiumLockWidget(
              feature: PremiumFeatures.detailedReport,
              locale: locale,
              showInline: false,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// REPORT GENERATOR SCREEN (pre-generation state)
// ============================================================

class _ReportGeneratorScreen extends StatelessWidget {
  final bool isHindi;
  final bool isDark;
  final bool hasPalmAnalysis;
  final bool isGenerating;
  final String? errorMessage;
  final VoidCallback onGenerate;
  final String locale;

  const _ReportGeneratorScreen({
    required this.isHindi,
    required this.isDark,
    required this.hasPalmAnalysis,
    required this.isGenerating,
    required this.errorMessage,
    required this.onGenerate,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1410);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF8B7355);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        foregroundColor: textPrimary,
        title: Text(
          isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Report',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF2A1200), const Color(0xFF1A0A00)]
                      : [const Color(0xFFFFF8F0), const Color(0xFFFFF0E0)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primary.withAlpha(isDark ? 60 : 40),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primary.withAlpha(20),
                      border: Border.all(
                        color: AppTheme.primary.withAlpha(60),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isHindi
                        ? 'आपकी व्यक्तिगत हस्तरेखा रिपोर्ट'
                        : 'Your Personalized Palm Reading Report',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isHindi
                        ? 'आपके वास्तविक हस्तरेखा विश्लेषण से 19 व्यापक खंडों वाली एक प्रीमियम रिपोर्ट तैयार की जाएगी।'
                        : 'A comprehensive 19-section premium report will be generated from your real palm analysis.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (!hasPalmAnalysis) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.warning.withAlpha(20)
                      : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warning.withAlpha(80)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isHindi
                                ? 'हस्तरेखा विश्लेषण आवश्यक है'
                                : 'Palm Analysis Required',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1410),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isHindi
                                ? 'विस्तृत रिपोर्ट के लिए पहले हस्तरेखा स्कैन करें।'
                                : 'Please scan your palm first to generate a detailed report.',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () => context.push('/palm-scan-screen'),
                            icon: const Icon(Icons.back_hand_rounded, size: 16),
                            label: Text(
                              isHindi
                                  ? 'हस्तरेखा स्कैन करें'
                                  : 'Scan Your Palm',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            Text(
              isHindi
                  ? 'रिपोर्ट में शामिल होगा (19 खंड):'
                  : 'Report includes (19 sections):',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ..._reportSections(isHindi).map(
              (section) => _SectionPreviewTile(
                number: section['number'] as int,
                title: section['title'] as String,
                icon: section['icon'] as String,
                isDark: isDark,
              ),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.withAlpha(20)
                    : const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.blue.withAlpha(50)
                      : const Color(0xFFBAE6FD),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.recycling_rounded,
                    size: 18,
                    color: Color(0xFF0284C7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isHindi
                          ? 'यह रिपोर्ट आपके मौजूदा हस्तरेखा विश्लेषण का उपयोग करती है। कोई नया स्कैन आवश्यक नहीं है।'
                          : 'This report uses your existing palm analysis. No new scan required.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF0369A1),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.error.withAlpha(isDark ? 30 : 15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.error.withAlpha(80)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: AppTheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppTheme.error,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (isGenerating || !hasPalmAnalysis)
                    ? null
                    : onGenerate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primary.withAlpha(80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: isGenerating
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isHindi
                                ? 'रिपोर्ट तैयार हो रही है...'
                                : 'Generating report...',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            isHindi
                                ? 'विस्तृत रिपोर्ट तैयार करें'
                                : 'Generate Detailed Report',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _reportSections(bool isHindi) => [
    {
      'number': 1,
      'icon': '📋',
      'title': isHindi ? 'कार्यकारी सारांश' : 'Executive Summary',
    },
    {
      'number': 2,
      'icon': '🌿',
      'title': isHindi ? 'समग्र हस्तरेखा अवलोकन' : 'Overall Palm Overview',
    },
    {
      'number': 3,
      'icon': '🧠',
      'title': isHindi ? 'व्यक्तित्व और चरित्र' : 'Personality & Character',
    },
    {
      'number': 4,
      'icon': '💡',
      'title': isHindi ? 'मस्तिष्क रेखा विश्लेषण' : 'Head Line Analysis',
    },
    {
      'number': 5,
      'icon': '❤️',
      'title': isHindi ? 'हृदय रेखा विश्लेषण' : 'Heart Line Analysis',
    },
    {
      'number': 6,
      'icon': '✋',
      'title': isHindi ? 'जीवन रेखा विश्लेषण' : 'Life Line Analysis',
    },
    {
      'number': 7,
      'icon': '⭐',
      'title': isHindi ? 'भाग्य/करियर रेखा' : 'Fate / Career Line',
    },
    {
      'number': 8,
      'icon': '🔍',
      'title': isHindi ? 'प्रमुख हस्तरेखा विशेषताएं' : 'Major Palm Features',
    },
    {
      'number': 9,
      'icon': '💼',
      'title': isHindi ? 'करियर और पेशेवर जीवन' : 'Career & Professional Life',
    },
    {
      'number': 10,
      'icon': '💰',
      'title': isHindi
          ? 'वित्त और धन प्रवृत्तियां'
          : 'Financial & Wealth Tendencies',
    },
    {
      'number': 11,
      'icon': '💕',
      'title': isHindi ? 'प्रेम और रिश्ते' : 'Love & Relationships',
    },
    {
      'number': 12,
      'icon': '💍',
      'title': isHindi
          ? 'विवाह/साझेदारी अंतर्दृष्टि'
          : 'Marriage / Partnership Insights',
    },
    {
      'number': 13,
      'icon': '🌱',
      'title': isHindi
          ? 'स्वास्थ्य और जीवन शक्ति'
          : 'Health & Vitality Tendencies',
    },
    {
      'number': 14,
      'icon': '👨‍👩‍👧',
      'title': isHindi ? 'परिवार और सामाजिक जीवन' : 'Family & Social Life',
    },
    {
      'number': 15,
      'icon': '💪',
      'title': isHindi ? 'प्रमुख शक्तियां' : 'Strengths',
    },
    {
      'number': 16,
      'icon': '🎯',
      'title': isHindi
          ? 'चुनौतियां / विकास के क्षेत्र'
          : 'Challenges / Areas for Growth',
    },
    {
      'number': 17,
      'icon': '🔮',
      'title': isHindi ? 'भविष्य की प्रवृत्तियां' : 'Future Tendencies',
    },
    {
      'number': 18,
      'icon': '🧭',
      'title': isHindi
          ? 'व्यावहारिक मार्गदर्शन'
          : 'Practical Guidance & Remedies',
    },
    {
      'number': 19,
      'icon': '🌟',
      'title': isHindi ? 'अंतिम समग्र मार्गदर्शन' : 'Final Overall Guidance',
    },
  ];
}

// ============================================================
// SECTION PREVIEW TILE
// ============================================================

class _SectionPreviewTile extends StatelessWidget {
  final int number;
  final String title;
  final String icon;
  final bool isDark;

  const _SectionPreviewTile({
    required this.number,
    required this.title,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFEDE5DF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withAlpha(15),
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF1A1410),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REPORT VIEWER SCREEN
// ============================================================

class _ReportViewerScreen extends StatefulWidget {
  final Map<String, dynamic> reportData;
  final String locale;
  final String? reportId;
  final DateTime? generatedAt;
  final bool isDark;
  final String? userName;

  const _ReportViewerScreen({
    required this.reportData,
    required this.locale,
    required this.isDark,
    this.reportId,
    this.generatedAt,
    this.userName,
  });

  @override
  State<_ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<_ReportViewerScreen> {
  bool _isExportingPdf = false;
  bool _isSharingPdf = false;
  bool _isEmailingReport = false;
  String? _actionError;
  String? _actionSuccess;

  bool get _isHindi => widget.locale == 'hi';

  Color get _bgColor =>
      widget.isDark ? const Color(0xFF0F0A06) : const Color(0xFFFAF7F4);
  Color get _appBarColor =>
      widget.isDark ? const Color(0xFF1A0E06) : Colors.white;
  Color get _textPrimary =>
      widget.isDark ? Colors.white : const Color(0xFF1A1410);
  Color get _textSecondary =>
      widget.isDark ? Colors.white60 : const Color(0xFF8B7355);
  Color get _cardBg => widget.isDark ? Colors.white.withAlpha(8) : Colors.white;
  Color get _cardBorder =>
      widget.isDark ? Colors.white.withAlpha(15) : const Color(0xFFEDE5DF);

  void _clearActionStatus() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _actionError = null;
          _actionSuccess = null;
        });
      }
    });
  }

  Future<void> _downloadPdf() async {
    if (widget.reportId == null) {
      setState(
        () => _actionError = _isHindi
            ? 'रिपोर्ट ID उपलब्ध नहीं है।'
            : 'Report ID not available.',
      );
      return;
    }
    setState(() {
      _isExportingPdf = true;
      _actionError = null;
      _actionSuccess = null;
    });
    try {
      final result = await PdfExportService.instance.exportDetailedReport(
        reportId: widget.reportId!,
        locale: widget.locale,
      );
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _isExportingPdf = false;
          _actionSuccess = _isHindi
              ? '✅ PDF सफलतापूर्वक डाउनलोड हो गई!'
              : '✅ PDF downloaded successfully!';
        });
        _clearActionStatus();
      } else {
        setState(() {
          _isExportingPdf = false;
          _actionError = result.errorMessage;
        });
        _clearActionStatus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExportingPdf = false;
          _actionError = _isHindi
              ? 'PDF उत्पन्न नहीं हो सका।'
              : 'Could not generate PDF.';
        });
      }
      _clearActionStatus();
    }
  }

  Future<void> _sharePdf() async {
    if (widget.reportId == null) {
      setState(
        () => _actionError = _isHindi
            ? 'रिपोर्ट ID उपलब्ध नहीं है।'
            : 'Report ID not available.',
      );
      return;
    }
    setState(() {
      _isSharingPdf = true;
      _actionError = null;
      _actionSuccess = null;
    });
    try {
      final result = await PdfExportService.instance.shareDetailedReport(
        reportId: widget.reportId!,
        locale: widget.locale,
      );
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _isSharingPdf = false;
        });
      } else {
        setState(() {
          _isSharingPdf = false;
          _actionError = result.errorMessage;
        });
        _clearActionStatus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSharingPdf = false;
          _actionError = _isHindi
              ? 'PDF शेयर नहीं हो सकी।'
              : 'Could not share PDF.';
        });
      }
      _clearActionStatus();
    }
  }

  Future<void> _emailReport() async {
    if (widget.reportId == null) {
      setState(
        () => _actionError = _isHindi
            ? 'रिपोर्ट ID उपलब्ध नहीं है।'
            : 'Report ID not available.',
      );
      return;
    }
    setState(() {
      _isEmailingReport = true;
      _actionError = null;
      _actionSuccess = null;
    });
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not authenticated');

      final response = await Supabase.instance.client.functions.invoke(
        'email-report',
        body: {'report_id': widget.reportId, 'locale': widget.locale},
      );

      if (!mounted) return;
      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>?;
        final email = data?['email'] as String? ?? '';
        setState(() {
          _isEmailingReport = false;
          _actionSuccess = _isHindi
              ? '✅ रिपोर्ट आपके ईमेल पर भेज दी गई है।'
              : '✅ Your detailed report has been sent to your email${email.isNotEmpty ? ' ($email)' : ''}.';
        });
        _clearActionStatus();
      } else {
        final errorData = response.data as Map<String, dynamic>? ?? {};
        final code = errorData['code'] as String? ?? '';
        String errMsg;
        if (code == 'EMAIL_NOT_CONFIGURED') {
          errMsg = _isHindi
              ? 'ईमेल सेवा अभी उपलब्ध नहीं है। कृपया बाद में पुनः प्रयास करें।'
              : 'Email service is not yet configured. Please try again later.';
        } else {
          errMsg =
              errorData['error'] as String? ??
              (_isHindi ? 'ईमेल भेजने में विफल।' : 'Failed to send email.');
        }
        setState(() {
          _isEmailingReport = false;
          _actionError = errMsg;
        });
        _clearActionStatus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmailingReport = false;
          _actionError = _isHindi
              ? 'ईमेल भेजने में विफल। पुनः प्रयास करें।'
              : 'Failed to send email. Please try again.';
        });
        _clearActionStatus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _appBarColor,
        foregroundColor: _textPrimary,
        title: Text(
          _isHindi ? 'हस्तरेखा रिपोर्ट' : 'Palm Reading Report',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action status banners
            if (_actionSuccess != null)
              _ActionBanner(
                isSuccess: true,
                message: _actionSuccess!,
                isDark: widget.isDark,
              ),
            if (_actionError != null)
              _ActionBanner(
                isSuccess: false,
                message: _actionError!,
                isDark: widget.isDark,
              ),
            if (_actionSuccess != null || _actionError != null)
              const SizedBox(height: 12),

            // Report header with branding
            _buildReportHeader(context),
            const SizedBox(height: 20),

            // Action buttons row
            _buildActionButtons(context),
            const SizedBox(height: 24),

            // ── 19 SECTIONS ──────────────────────────────────────────────────

            // Section 1: Executive Summary
            _buildSection(
              context,
              number: 1,
              icon: '📋',
              sectionKey: 'executive_summary',
              defaultTitle: _isHindi ? 'कार्यकारी सारांश' : 'Executive Summary',
              highlightsKey: 'key_highlights',
              isHighlight: true,
            ),

            // Section 2: Overall Palm Overview
            _buildSection(
              context,
              number: 2,
              icon: '🌿',
              sectionKey: 'overall_palm_overview',
              defaultTitle: _isHindi
                  ? 'समग्र हस्तरेखा अवलोकन'
                  : 'Overall Palm Overview',
              highlightsKey: 'key_observations',
            ),

            // Section 3: Personality & Character
            _buildSection(
              context,
              number: 3,
              icon: '🧠',
              sectionKey: 'personality_character',
              defaultTitle: _isHindi
                  ? 'व्यक्तित्व और चरित्र'
                  : 'Personality & Character',
              highlightsKey: 'traits',
            ),

            // Section 4: Head Line Analysis
            _buildSection(
              context,
              number: 4,
              icon: '💡',
              sectionKey: 'head_line_analysis',
              defaultTitle: _isHindi
                  ? 'मस्तिष्क रेखा विश्लेषण'
                  : 'Head Line Analysis',
              highlightsKey: 'observations',
            ),

            // Section 5: Heart Line Analysis
            _buildSection(
              context,
              number: 5,
              icon: '❤️',
              sectionKey: 'heart_line_analysis',
              defaultTitle: _isHindi
                  ? 'हृदय रेखा विश्लेषण'
                  : 'Heart Line Analysis',
              highlightsKey: 'observations',
            ),

            // Section 6: Life Line Analysis
            _buildSection(
              context,
              number: 6,
              icon: '✋',
              sectionKey: 'life_line_analysis',
              defaultTitle: _isHindi
                  ? 'जीवन रेखा विश्लेषण'
                  : 'Life Line Analysis',
              highlightsKey: 'observations',
            ),

            // Section 7: Fate/Career Line
            _buildSection(
              context,
              number: 7,
              icon: '⭐',
              sectionKey: 'fate_career_line',
              defaultTitle: _isHindi
                  ? 'भाग्य/करियर रेखा'
                  : 'Fate / Career Line',
              highlightsKey: 'observations',
            ),

            // Section 8: Major Palm Features
            _buildMajorFeaturesSection(context),

            // Section 9: Career & Professional
            _buildSection(
              context,
              number: 9,
              icon: '💼',
              sectionKey: 'career_professional',
              defaultTitle: _isHindi
                  ? 'करियर और पेशेवर जीवन'
                  : 'Career & Professional Life',
              highlightsKey: 'observations',
            ),

            // Section 10: Financial & Wealth
            _buildSection(
              context,
              number: 10,
              icon: '💰',
              sectionKey: 'financial_wealth',
              defaultTitle: _isHindi
                  ? 'वित्त और धन प्रवृत्तियां'
                  : 'Financial & Wealth Tendencies',
              highlightsKey: 'observations',
            ),

            // Section 11: Love & Relationships
            _buildSection(
              context,
              number: 11,
              icon: '💕',
              sectionKey: 'love_relationships',
              defaultTitle: _isHindi
                  ? 'प्रेम और रिश्ते'
                  : 'Love & Relationships',
              highlightsKey: 'observations',
            ),

            // Section 12: Marriage / Partnership
            _buildSection(
              context,
              number: 12,
              icon: '💍',
              sectionKey: 'marriage_partnership',
              defaultTitle: _isHindi
                  ? 'विवाह/साझेदारी अंतर्दृष्टि'
                  : 'Marriage / Partnership Insights',
              highlightsKey: 'observations',
            ),

            // Section 13: Health & Vitality
            _buildSection(
              context,
              number: 13,
              icon: '🌱',
              sectionKey: 'health_vitality',
              defaultTitle: _isHindi
                  ? 'स्वास्थ्य और जीवन शक्ति'
                  : 'Health & Vitality Tendencies',
              highlightsKey: 'observations',
            ),

            // Section 14: Family & Social Life
            _buildSection(
              context,
              number: 14,
              icon: '👨‍👩‍👧',
              sectionKey: 'family_social',
              defaultTitle: _isHindi
                  ? 'परिवार और सामाजिक जीवन'
                  : 'Family & Social Life',
              highlightsKey: 'observations',
            ),

            // Section 15: Key Strengths
            _buildSection(
              context,
              number: 15,
              icon: '💪',
              sectionKey: 'key_strengths',
              defaultTitle: _isHindi ? 'प्रमुख शक्तियां' : 'Key Strengths',
              highlightsKey: 'strengths',
            ),

            // Section 16: Challenges / Growth
            _buildSection(
              context,
              number: 16,
              icon: '🎯',
              sectionKey: 'challenges_growth',
              defaultTitle: _isHindi
                  ? 'चुनौतियां / विकास के क्षेत्र'
                  : 'Challenges / Areas for Growth',
              highlightsKey: 'areas',
            ),

            // Section 17: Future Tendencies
            _buildSection(
              context,
              number: 17,
              icon: '🔮',
              sectionKey: 'future_tendencies',
              defaultTitle: _isHindi
                  ? 'भविष्य की प्रवृत्तियां'
                  : 'Future Tendencies',
              highlightsKey: 'observations',
            ),

            // Section 18: Practical Guidance
            _buildSection(
              context,
              number: 18,
              icon: '🧭',
              sectionKey: 'practical_guidance',
              defaultTitle: _isHindi
                  ? 'व्यावहारिक मार्गदर्शन'
                  : 'Practical Guidance & Remedies',
              highlightsKey: 'guidance_points',
            ),

            // Section 19: Final Guidance
            _buildFinalGuidanceSection(context),

            const SizedBox(height: 24),

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withAlpha(8)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Text(
                _isHindi
                    ? '⚠️ यह रिपोर्ट AI-जनित हस्तरेखा शास्त्र की पारंपरिक व्याख्या पर आधारित है। यह वैज्ञानिक रूप से सिद्ध नहीं है। यह चिकित्सीय, कानूनी या वित्तीय सलाह नहीं है। इसे आत्म-चिंतन और मनोरंजन के लिए उपयोग करें।'
                    : '⚠️ This report is AI-generated based on traditional palmistry interpretation. It is not scientifically proven. This is not medical, legal, or financial advice. Use it for self-reflection and entertainment.',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildReportHeader(BuildContext context) {
    final dateStr = widget.generatedAt != null
        ? '${widget.generatedAt!.day}/${widget.generatedAt!.month}/${widget.generatedAt!.year}'
        : '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

    final metadata = widget.reportData['metadata'] as Map<String, dynamic>?;
    final handType =
        (widget.reportData['overall_palm_overview']
                as Map<String, dynamic>?)?['hand_type']
            as String?;
    final userName = widget.userName ?? (metadata?['user_name'] as String?);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDark
              ? [const Color(0xFF2A1200), const Color(0xFF1A0A00)]
              : [const Color(0xFFFFF8F0), const Color(0xFFFFF0E0)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HastVeda branding row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0F05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'HastVeda',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary.withAlpha(50)),
                ),
                child: Text(
                  _isHindi ? 'प्रीमियम रिपोर्ट' : 'PREMIUM REPORT',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isHindi
                ? 'विस्तृत हस्तरेखा पठन रिपोर्ट'
                : 'Detailed Palm Reading Report',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isHindi
                ? '"प्राचीन ज्ञान। बुद्धिमान अंतर्दृष्टि।"'
                : '"Ancient Wisdom. Intelligent Insights."',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          if (userName != null && userName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    userName,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 12,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '${_isHindi ? "उत्पन्न:" : "Generated:"} $dateStr',
                style: GoogleFonts.outfit(fontSize: 12, color: _textSecondary),
              ),
            ],
          ),
          if (handType != null && handType.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.back_hand_rounded,
                  size: 12,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    handType,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _HeaderBadge(
                label: _isHindi ? '19 खंड' : '19 Sections',
                icon: Icons.list_alt_rounded,
                isDark: widget.isDark,
              ),
              const SizedBox(width: 8),
              _HeaderBadge(
                label: _isHindi ? 'AI-संचालित' : 'AI-Powered',
                icon: Icons.auto_awesome_rounded,
                isDark: widget.isDark,
              ),
              const SizedBox(width: 8),
              _HeaderBadge(
                label: _isHindi ? 'व्यक्तिगत' : 'Personalized',
                icon: Icons.verified_rounded,
                isDark: widget.isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final anyBusy = _isExportingPdf || _isSharingPdf || _isEmailingReport;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.download_rounded,
                label: _isHindi ? 'PDF डाउनलोड' : 'Download PDF',
                isLoading: _isExportingPdf,
                disabled: anyBusy,
                onTap: _downloadPdf,
                isDark: widget.isDark,
                isPrimary: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.share_rounded,
                label: _isHindi ? 'PDF शेयर' : 'Share PDF',
                isLoading: _isSharingPdf,
                disabled: anyBusy,
                onTap: _sharePdf,
                isDark: widget.isDark,
                isPrimary: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _ActionButton(
            icon: Icons.email_rounded,
            label: _isHindi ? 'ईमेल रिपोर्ट' : 'Email Report',
            isLoading: _isEmailingReport,
            disabled: anyBusy,
            onTap: _emailReport,
            isDark: widget.isDark,
            isPrimary: false,
            fullWidth: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required int number,
    required String icon,
    required String sectionKey,
    required String defaultTitle,
    required String highlightsKey,
    bool isHighlight = false,
  }) {
    final section = widget.reportData[sectionKey] as Map<String, dynamic>?;
    if (section == null) return const SizedBox.shrink();

    final title = section['title'] as String? ?? defaultTitle;
    final content = section['content'] as String? ?? '';
    final highlights = (section[highlightsKey] as List?)?.cast<String>() ?? [];
    final score = (section['score'] as num?)?.toInt();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _ReportSectionCard(
        number: number,
        icon: icon,
        title: title,
        content: content,
        highlights: highlights,
        score: score,
        isDark: widget.isDark,
        cardBg: isHighlight
            ? (widget.isDark
                  ? const Color(0xFF1A0E06)
                  : const Color(0xFFFFF8F0))
            : _cardBg,
        cardBorder: isHighlight ? AppTheme.primary.withAlpha(60) : _cardBorder,
        textPrimary: _textPrimary,
        textSecondary: _textSecondary,
        isHighlight: isHighlight,
      ),
    );
  }

  Widget _buildMajorFeaturesSection(BuildContext context) {
    final section =
        widget.reportData['major_palm_features'] as Map<String, dynamic>?;
    if (section == null) return const SizedBox.shrink();

    final title =
        section['title'] as String? ??
        (_isHindi
            ? 'प्रमुख हस्तरेखा विशेषताएं'
            : 'Major Palm Features / Mounts');
    final content = section['content'] as String? ?? '';
    final lines =
        (section['lines'] as List?)
            ?.map((l) => l as Map<String, dynamic>)
            .toList() ??
        [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              number: 8,
              icon: '🔍',
              title: title,
              isDark: widget.isDark,
              textPrimary: _textPrimary,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isNotEmpty) ...[
                    _RichText(
                      text: content,
                      isDark: widget.isDark,
                      textSecondary: _textSecondary,
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...lines.map(
                    (line) => _PalmLineRow(
                      line: line,
                      isDark: widget.isDark,
                      textPrimary: _textPrimary,
                      textSecondary: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalGuidanceSection(BuildContext context) {
    final section =
        widget.reportData['final_guidance'] as Map<String, dynamic>?;
    if (section == null) return const SizedBox.shrink();

    final title =
        section['title'] as String? ??
        (_isHindi ? 'अंतिम समग्र मार्गदर्शन' : 'Final Overall Guidance');
    final content = section['content'] as String? ?? '';
    final closingNote = section['closing_note'] as String? ?? '';
    final disclaimer = section['disclaimer'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDark
                ? [
                    AppTheme.primary.withAlpha(20),
                    AppTheme.primary.withAlpha(8),
                  ]
                : [
                    AppTheme.primary.withAlpha(10),
                    AppTheme.primary.withAlpha(4),
                  ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withAlpha(50)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              number: 19,
              icon: '🌟',
              title: title,
              isDark: widget.isDark,
              textPrimary: _textPrimary,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isNotEmpty)
                    _RichText(
                      text: content,
                      isDark: widget.isDark,
                      textSecondary: _textSecondary,
                    ),
                  if (closingNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(
                          widget.isDark ? 20 : 10,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(40),
                        ),
                      ),
                      child: Text(
                        closingNote,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: widget.isDark
                              ? AppTheme.primary.withAlpha(220)
                              : AppTheme.primary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  if (disclaimer.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      disclaimer,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: _textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ACTION BUTTON
// ============================================================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onTap;
  final bool isDark;
  final bool isPrimary;
  final bool fullWidth;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isLoading,
    required this.disabled,
    required this.onTap,
    required this.isDark,
    required this.isPrimary,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton.icon(
        onPressed: (disabled || isLoading) ? null : onTap,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon, size: 16),
        label: Text(
          label,
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? AppTheme.primary
              : (isDark ? Colors.white.withAlpha(20) : const Color(0xFFF5EFE8)),
          foregroundColor: isPrimary
              ? Colors.white
              : (isDark ? Colors.white : const Color(0xFF8C4F10)),
          disabledBackgroundColor: isDark
              ? Colors.white.withAlpha(10)
              : const Color(0xFFEDE5DF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          elevation: 0,
        ),
      ),
    );
  }
}

// ============================================================
// ACTION BANNER
// ============================================================

class _ActionBanner extends StatelessWidget {
  final bool isSuccess;
  final String message;
  final bool isDark;

  const _ActionBanner({
    required this.isSuccess,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSuccess ? AppTheme.success : AppTheme.error;
    final bgColor = isSuccess
        ? (isDark ? AppTheme.success.withAlpha(30) : const Color(0xFFF0FFF8))
        : (isDark ? AppTheme.error.withAlpha(30) : const Color(0xFFFFF0F0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
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

// ============================================================
// REPORT SECTION CARD
// ============================================================

class _ReportSectionCard extends StatelessWidget {
  final int number;
  final String icon;
  final String title;
  final String content;
  final List<String> highlights;
  final int? score;
  final bool isDark;
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final bool isHighlight;

  const _ReportSectionCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.content,
    required this.highlights,
    required this.isDark,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    this.score,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            number: number,
            icon: icon,
            title: title,
            score: score,
            isDark: isDark,
            textPrimary: textPrimary,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (content.isNotEmpty)
                  _RichText(
                    text: content,
                    isDark: isDark,
                    textSecondary: textSecondary,
                  ),
                if (highlights.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...highlights.map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 7),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              h,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isHighlight
                                    ? AppTheme.primary
                                    : AppTheme.primary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADER
// ============================================================

class _SectionHeader extends StatelessWidget {
  final int number;
  final String icon;
  final String title;
  final int? score;
  final bool isDark;
  final Color textPrimary;

  const _SectionHeader({
    required this.number,
    required this.icon,
    required this.title,
    required this.isDark,
    required this.textPrimary,
    this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(5)
            : AppTheme.primary.withAlpha(5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withAlpha(20),
              border: Border.all(color: AppTheme.primary.withAlpha(50)),
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          if (score != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _scoreColor(score!).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$score%',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _scoreColor(score!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppTheme.success;
    if (score >= 65) return AppTheme.primary;
    return AppTheme.warning;
  }
}

// ============================================================
// PALM LINE ROW
// ============================================================

class _PalmLineRow extends StatelessWidget {
  final Map<String, dynamic> line;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _PalmLineRow({
    required this.line,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final name = line['name'] as String? ?? '';
    final visible = line['visible'] as bool? ?? false;
    final description = line['description'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(5)
            : AppTheme.primary.withAlpha(5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(10)
              : AppTheme.primary.withAlpha(20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: visible ? AppTheme.success : AppTheme.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HEADER BADGE
// ============================================================

class _HeaderBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;

  const _HeaderBadge({
    required this.label,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(10)
            : AppTheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(20)
              : AppTheme.primary.withAlpha(30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: isDark ? Colors.white60 : AppTheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: isDark ? Colors.white60 : AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RICH TEXT RENDERER
// ============================================================

class _RichText extends StatelessWidget {
  final String text;
  final bool isDark;
  final Color textSecondary;

  const _RichText({
    required this.text,
    required this.isDark,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        spans.add(
          TextSpan(
            text: parts[i],
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1410),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: parts[i],
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: textSecondary,
              height: 1.6,
            ),
          ),
        );
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
