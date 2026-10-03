// HastVeda — Couple Reading History Screen
// Loads saved couple readings from Supabase (couple_readings table).
// RLS ensures users only see their own readings.
// "View Report" opens the saved CoupleReadingResultScreen — no Gemini re-call.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/locale_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hastveda_error_widget.dart';

class CoupleReadingHistoryScreen extends StatefulWidget {
  final String locale;
  const CoupleReadingHistoryScreen({super.key, this.locale = 'en'});

  @override
  State<CoupleReadingHistoryScreen> createState() =>
      _CoupleReadingHistoryScreenState();
}

class _CoupleReadingHistoryScreenState
    extends State<CoupleReadingHistoryScreen> {
  static const int _pageSize = 20;

  bool _isLoading = true;
  bool _hasError = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final List<Map<String, dynamic>> _readings = [];
  final ScrollController _scrollController = ScrollController();

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _loadReadings();
    _scrollController.addListener(_onScroll);
    analytics.track(
      HastVedaEvents.readingHistoryViewed,
      properties: {'type': 'couple'},
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadReadings({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _readings.clear();
        _hasMore = true;
        _isLoading = true;
        _hasError = false;
      });
    } else {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await Supabase.instance.client
          .from('couple_readings')
          .select(
            'id, person1_name, person2_name, overall_compatibility_score, '
            'love_score, emotional_score, communication_score, marriage_score, '
            'language, status, created_at, compatibility_data',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (mounted) {
        setState(() {
          _readings.addAll(List<Map<String, dynamic>>.from(data));
          _hasMore = (data as List).length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('CoupleReadingHistory load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _readings.isEmpty) return;
    setState(() => _isLoadingMore = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final lastCreatedAt = _readings.last['created_at'] as String?;
      if (lastCreatedAt == null) return;

      final data = await Supabase.instance.client
          .from('couple_readings')
          .select(
            'id, person1_name, person2_name, overall_compatibility_score, '
            'love_score, emotional_score, communication_score, marriage_score, '
            'language, status, created_at, compatibility_data',
          )
          .eq('user_id', userId)
          .lt('created_at', lastCreatedAt)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (mounted) {
        setState(() {
          _readings.addAll(List<Map<String, dynamic>>.from(data));
          _hasMore = (data as List).length == _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('CoupleReadingHistory loadMore error: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openReport(Map<String, dynamic> reading) async {
    final coupleReadingId = reading['id'] as String?;
    if (coupleReadingId == null) return;

    // Show loading indicator briefly
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );

    try {
      // Load full data from Supabase — no Gemini call
      final data = await Supabase.instance.client
          .from('couple_readings')
          .select()
          .eq('id', coupleReadingId)
          .maybeSingle();

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      if (data == null) {
        _showError(
          _isHindi ? 'पठन डेटा नहीं मिला।' : 'Reading data not found.',
        );
        return;
      }

      final compatData =
          data['compatibility_data'] as Map<String, dynamic>? ?? {};
      final locale = data['language'] as String? ?? widget.locale;

      context.push(
        AppRoutes.coupleReadingResult,
        extra: {
          'person1Name':
              data['person1_name'] as String? ??
              (_isHindi ? 'व्यक्ति १' : 'Person 1'),
          'person2Name':
              data['person2_name'] as String? ??
              (_isHindi ? 'व्यक्ति २' : 'Person 2'),
          'compatibility': {
            ...compatData,
            // Top-level score columns
            'id': coupleReadingId,
            'person1_name':
                data['person1_name'] as String? ??
                (_isHindi ? 'व्यक्ति १' : 'Person 1'),
            'person2_name':
                data['person2_name'] as String? ??
                (_isHindi ? 'व्यक्ति २' : 'Person 2'),
            'overall_compatibility_score': data['overall_compatibility_score'],
            'love_score': data['love_score'],
            'emotional_score': data['emotional_score'],
            'communication_score': data['communication_score'],
            'financial_score': data['financial_score'],
            'career_score': data['career_score'],
            'personality_score': data['personality_score'],
            'attraction_score': data['attraction_score'],
            'marriage_score': data['marriage_score'],
          },
          'locale': locale,
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showError(
          _isHindi ? 'पठन लोड नहीं हो सका।' : 'Could not load reading.',
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    final months = _isHindi
        ? [
            'जन',
            'फर',
            'मार',
            'अप्र',
            'मई',
            'जून',
            'जुल',
            'अग',
            'सित',
            'अक्त',
            'नव',
            'दिस',
          ]
        : [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec',
          ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppTheme.success;
    if (score >= 65) return AppTheme.primary;
    return AppTheme.warning;
  }

  String _scoreLabel(int score) {
    if (_isHindi) {
      if (score >= 80) return 'उत्कृष्ट';
      if (score >= 65) return 'अच्छा';
      return 'सामान्य';
    }
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Good';
    return 'Fair';
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final appBarBg = isDark ? AppTheme.surfaceDark : const Color(0xFF1A0E06);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isHindi ? 'युगल पठन इतिहास' : 'Couple Reading History',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: popOrHome,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: _isHindi ? 'ताज़ा करें' : 'Refresh',
            onPressed: () => _loadReadings(refresh: true),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState(isDark)
          : _hasError
          ? HastVedaInlineError(
              title: s.somethingWentWrong,
              message: s.troubleConnecting,
              onRetry: () => _loadReadings(refresh: true),
            )
          : _readings.isEmpty
          ? _buildEmptyState(isDark)
          : RefreshIndicator(
              onRefresh: () => _loadReadings(refresh: true),
              color: AppTheme.primary,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _readings.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _readings.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }
                  return _CoupleHistoryCard(
                    reading: _readings[index],
                    isHindi: _isHindi,
                    isDark: isDark,
                    formatDate: _formatDate,
                    scoreColor: _scoreColor,
                    scoreLabel: _scoreLabel,
                    onViewReport: () => _openReport(_readings[index]),
                  );
                },
              ),
            ),
      // FAB to start a new couple reading
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('${AppRoutes.coupleReading}?locale=${widget.locale}'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.favorite_rounded, size: 20),
        label: Text(
          _isHindi ? 'नया पठन' : 'New Reading',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    final cardBg = isDark ? AppTheme.surfaceElevated : Colors.white;
    final shimmer = isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: shimmer),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: shimmer,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: 160,
                            decoration: BoxDecoration(
                              color: shimmer,
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 11,
                            width: 100,
                            decoration: BoxDecoration(
                              color: shimmer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: shimmer,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: shimmer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF8B7355);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFEC4899).withAlpha(30),
                    AppTheme.primary.withAlpha(20),
                  ],
                ),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 44,
                color: Color(0xFFEC4899),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isHindi ? 'अभी तक कोई युगल पठन नहीं' : 'No Couple Readings Yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isHindi
                  ? 'अपना पहला युगल अनुकूलता पठन बनाएं और यहाँ देखें।'
                  : 'Create your first couple compatibility reading and it will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: subColor,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => context.push(
                '${AppRoutes.coupleReading}?locale=${widget.locale}',
              ),
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: Text(
                _isHindi ? 'युगल पठन शुरू करें' : 'Start Couple Reading',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEC4899),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Couple History Card ────────────────────────────────────────────────────────

class _CoupleHistoryCard extends StatelessWidget {
  final Map<String, dynamic> reading;
  final bool isHindi;
  final bool isDark;
  final String Function(String?) formatDate;
  final Color Function(int) scoreColor;
  final String Function(int) scoreLabel;
  final VoidCallback onViewReport;

  const _CoupleHistoryCard({
    required this.reading,
    required this.isHindi,
    required this.isDark,
    required this.formatDate,
    required this.scoreColor,
    required this.scoreLabel,
    required this.onViewReport,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppTheme.surfaceElevated : Colors.white;
    final borderColor = isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF);
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF8B7355);

    final person1Name =
        reading['person1_name'] as String? ??
        (isHindi ? 'व्यक्ति १' : 'Person 1');
    final person2Name =
        reading['person2_name'] as String? ??
        (isHindi ? 'व्यक्ति २' : 'Person 2');
    final score =
        (reading['overall_compatibility_score'] as num?)?.toInt() ?? 0;
    final createdAt = reading['created_at'] as String?;
    final lang = reading['language'] as String? ?? 'en';

    final color = scoreColor(score);
    final label = scoreLabel(score);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 30 : 8),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                children: [
                  // Heart icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFEC4899).withAlpha(30),
                          const Color(0xFFEC4899).withAlpha(15),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFEC4899),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Names + date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                person1Name,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 12,
                                color: const Color(0xFFEC4899).withAlpha(180),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                person2Name,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 11,
                              color: subColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatDate(createdAt),
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Language badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.outlineDark
                                    : const Color(0xFFF0EBE5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                lang == 'hi' ? 'हिंदी' : 'EN',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: subColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Score ring
                  if (score > 0)
                    _ScoreRing(score: score, color: color, label: label),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // ── Score chips row ──────────────────────────────────────────
              if (score > 0) ...[
                _ScoreChipsRow(
                  reading: reading,
                  isHindi: isHindi,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
              ],

              // ── View Report button ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onViewReport,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(
                    isHindi ? 'रिपोर्ट देखें' : 'View Report',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEC4899),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Score Ring ────────────────────────────────────────────────────────────────

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  final String label;

  const _ScoreRing({
    required this.score,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: score / 100,
                strokeWidth: 4,
                backgroundColor: color.withAlpha(30),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Score Chips Row ───────────────────────────────────────────────────────────

class _ScoreChipsRow extends StatelessWidget {
  final Map<String, dynamic> reading;
  final bool isHindi;
  final bool isDark;

  const _ScoreChipsRow({
    required this.reading,
    required this.isHindi,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <_ChipData>[
      _ChipData(
        icon: Icons.favorite_rounded,
        label: isHindi ? 'प्रेम' : 'Love',
        score: (reading['love_score'] as num?)?.toInt() ?? 0,
        color: const Color(0xFFEC4899),
      ),
      _ChipData(
        icon: Icons.psychology_rounded,
        label: isHindi ? 'भावना' : 'Emotion',
        score: (reading['emotional_score'] as num?)?.toInt() ?? 0,
        color: const Color(0xFF8B5CF6),
      ),
      _ChipData(
        icon: Icons.chat_bubble_rounded,
        label: isHindi ? 'संचार' : 'Comm.',
        score: (reading['communication_score'] as num?)?.toInt() ?? 0,
        color: AppTheme.cyan,
      ),
      _ChipData(
        icon: Icons.diamond_rounded,
        label: isHindi ? 'विवाह' : 'Marriage',
        score: (reading['marriage_score'] as num?)?.toInt() ?? 0,
        color: AppTheme.primary,
      ),
    ];

    return Row(
      children: chips
          .where((c) => c.score > 0)
          .map(
            (c) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _ScoreChip(data: c, isDark: isDark),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ChipData {
  final IconData icon;
  final String label;
  final int score;
  final Color color;
  const _ChipData({
    required this.icon,
    required this.label,
    required this.score,
    required this.color,
  });
}

class _ScoreChip extends StatelessWidget {
  final _ChipData data;
  final bool isDark;

  const _ScoreChip({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: data.color.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: data.color.withAlpha(50)),
      ),
      child: Column(
        children: [
          Icon(data.icon, size: 14, color: data.color),
          const SizedBox(height: 2),
          Text(
            '${data.score}%',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: data.color,
            ),
          ),
          Text(
            data.label,
            style: GoogleFonts.outfit(
              fontSize: 9,
              color: data.color.withAlpha(180),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
