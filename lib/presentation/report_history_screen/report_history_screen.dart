import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/locale_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hastveda_error_widget.dart';

class ReportHistoryScreen extends StatefulWidget {
  final String locale;

  const ReportHistoryScreen({super.key, this.locale = 'en'});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _coupleReadings = [];

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
    analytics.track(HastVedaEvents.reportHistoryViewed);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Load reports from Supabase (user's own reports only via RLS)
      final reportsData = await SupabaseService.instance.client
          .from('reports')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      // Load couple readings (user's own only via RLS)
      final coupleData = await SupabaseService.instance.client
          .from('couple_readings')
          .select()
          .or('person1_user_id.eq.$userId,person2_user_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(reportsData);
          _coupleReadings = List<Map<String, dynamic>>.from(coupleData);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Report history load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _reports = [];
          _coupleReadings = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        foregroundColor: AppTheme.textPrimary,
        title: Text(
          s.reportHistory,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: popOrHome,
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(text: _isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Reports'),
            Tab(text: _isHindi ? 'युगल पठन' : 'Couple Readings'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _hasError
          ? HastVedaInlineError(
              title: s.somethingWentWrong,
              message: s.unableToLoadHistory,
              onRetry: _loadHistory,
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _ReportsList(
                  reports: _reports,
                  isHindi: _isHindi,
                  onRefresh: _loadHistory,
                ),
                _CoupleReadingsList(
                  readings: _coupleReadings,
                  isHindi: _isHindi,
                  onRefresh: _loadHistory,
                ),
              ],
            ),
    );
  }
}

// ============================================================
// REPORTS LIST
// ============================================================

class _ReportsList extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final bool isHindi;
  final Future<void> Function() onRefresh;

  const _ReportsList({
    required this.reports,
    required this.isHindi,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return _EmptyState(
        icon: Icons.description_outlined,
        title: isHindi ? 'कोई रिपोर्ट नहीं' : 'No Reports Yet',
        subtitle: isHindi
            ? 'आपकी विस्तृत हस्तरेखा रिपोर्ट यहां दिखेंगी'
            : 'Your detailed palm reading reports will appear here',
        ctaLabel: isHindi ? 'रिपोर्ट तैयार करें' : 'Generate Report',
        onCta: () => context.push(AppRoutes.detailedReport),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final report = reports[index];
          return _ReportHistoryCard(report: report, isHindi: isHindi);
        },
      ),
    );
  }
}

class _ReportHistoryCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool isHindi;

  const _ReportHistoryCard({required this.report, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    final createdAt = report['created_at'] != null
        ? DateTime.tryParse(report['created_at'] as String)
        : null;
    final status = report['status'] as String? ?? 'completed';
    final language = report['language'] as String? ?? 'en';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE5DF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withAlpha(15),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHindi
                          ? 'विस्तृत हस्तरेखा रिपोर्ट'
                          : 'Detailed Palm Report',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1410),
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF8B7355),
                        ),
                      ),
                  ],
                ),
              ),
              _StatusBadge(status: status, isHindi: isHindi),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFEDE5DF), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetaChip(
                icon: Icons.translate_rounded,
                label: language == 'hi'
                    ? (isHindi ? 'हिंदी' : 'Hindi')
                    : (isHindi ? 'अंग्रेजी' : 'English'),
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.category_rounded,
                label: isHindi ? 'विस्तृत' : 'Detailed',
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final reportId = report['id'] as String?;
                  if (reportId != null) {
                    context.push(
                      AppRoutes.detailedReport,
                      extra: {'reportId': reportId, 'reportData': report},
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  isHindi ? 'देखें' : 'View',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COUPLE READINGS LIST
// ============================================================

class _CoupleReadingsList extends StatelessWidget {
  final List<Map<String, dynamic>> readings;
  final bool isHindi;
  final Future<void> Function() onRefresh;

  const _CoupleReadingsList({
    required this.readings,
    required this.isHindi,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return _EmptyState(
        icon: Icons.favorite_outline_rounded,
        title: isHindi ? 'कोई युगल पठन नहीं' : 'No Couple Readings Yet',
        subtitle: isHindi
            ? 'आपके युगल पठन यहां दिखेंगे'
            : 'Your couple readings will appear here',
        ctaLabel: isHindi ? 'युगल पठन शुरू करें' : 'Start Couple Reading',
        onCta: () => context.push(AppRoutes.coupleReading),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: readings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final reading = readings[index];
          return _CoupleReadingCard(reading: reading, isHindi: isHindi);
        },
      ),
    );
  }
}

class _CoupleReadingCard extends StatelessWidget {
  final Map<String, dynamic> reading;
  final bool isHindi;

  const _CoupleReadingCard({required this.reading, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    final createdAt = reading['created_at'] != null
        ? DateTime.tryParse(reading['created_at'] as String)
        : null;
    final status = reading['status'] as String? ?? 'completed';
    final overallScore = reading['overall_compatibility_score'] as int?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE5DF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withAlpha(15),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHindi
                          ? 'युगल अनुकूलता पठन'
                          : 'Couple Compatibility Reading',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1410),
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF8B7355),
                        ),
                      ),
                  ],
                ),
              ),
              if (overallScore != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$overallScore%',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFEDE5DF), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetaChip(
                icon: Icons.people_rounded,
                label: isHindi ? 'युगल' : 'Couple',
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: status, isHindi: isHindi),
              const Spacer(),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  isHindi ? 'देखें' : 'View',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HELPER WIDGETS
// ============================================================

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isHindi;

  const _StatusBadge({required this.status, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == 'completed';
    final color = isCompleted ? AppTheme.success : AppTheme.warning;
    final label = isCompleted
        ? (isHindi ? 'पूर्ण' : 'Completed')
        : (isHindi ? 'प्रक्रिया में' : 'Processing');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDE5DF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF8B7355)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: const Color(0xFF8B7355),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onCta;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withAlpha(15),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1410),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF8B7355),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onCta,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 0,
              ),
              child: Text(
                ctaLabel,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
