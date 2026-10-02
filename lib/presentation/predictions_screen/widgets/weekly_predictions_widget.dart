import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/personalized_predictions_service.dart';
import '../../../theme/app_theme.dart';
import './prediction_card_widget.dart';

class WeeklyPredictionsWidget extends StatefulWidget {
  final String language;

  const WeeklyPredictionsWidget({super.key, required this.language});

  @override
  State<WeeklyPredictionsWidget> createState() =>
      _WeeklyPredictionsWidgetState();
}

class _WeeklyPredictionsWidgetState extends State<WeeklyPredictionsWidget> {
  PalmPredictionsData? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await PersonalizedPredictionsService.instance.getPredictions();
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    final predictions = _data?.weekly ?? [];
    final isPersonalized =
        _data?.isPersonalized == true && predictions.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeekHeader(isPersonalized),
          const SizedBox(height: 16),
          if (!isPersonalized)
            _buildNoPalmDataBanner()
          else ...[
            _buildConfidenceChart(context, predictions),
            const SizedBox(height: 16),
            ...predictions.map(
              (p) => PredictionCardWidget(
                entry: PredictionEntry(
                  textEn: [p.content, p.category],
                  textHi: [p.contentHi, p.categoryHi],
                  iconName: p.iconName,
                  accentColor: AppTheme.gold,
                  confidence: p.confidence,
                  isMajorEvent: p.isMajorEvent,
                ),
                language: widget.language,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekHeader(bool isPersonalized) {
    final now = DateTime.now();
    final weekEnd = now.add(const Duration(days: 6));
    final months = [
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
    final monthsHi = [
      'जन',
      'फर',
      'मार',
      'अप्र',
      'मई',
      'जून',
      'जुल',
      'अग',
      'सित',
      'अक्ट',
      'नव',
      'दिस',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.goldMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_view_week, color: AppTheme.gold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.language == 'EN'
                  ? '${months[now.month - 1]} ${now.day} – ${months[weekEnd.month - 1]} ${weekEnd.day}'
                  : '${now.day} ${monthsHi[now.month - 1]} – ${weekEnd.day} ${monthsHi[weekEnd.month - 1]}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.gold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isPersonalized)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.gold.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.language == 'EN' ? 'Personalized' : 'व्यक्तिगत',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: AppTheme.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfidenceChart(
    BuildContext context,
    List<PersonalizedPrediction> predictions,
  ) {
    final days = widget.language == 'EN'
        ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : ['सो', 'मं', 'बु', 'गु', 'शु', 'श', 'र'];

    // Build energy curve from prediction confidences
    final baseScore = predictions.isNotEmpty
        ? predictions.map((p) => p.confidence).reduce((a, b) => a + b) /
              predictions.length
        : 70.0;

    final spots = List.generate(7, (i) {
      final variation = [0.0, 4.0, 8.0, 5.0, -3.0, 10.0, 7.0][i];
      return FlSpot(i.toDouble(), (baseScore + variation).clamp(50.0, 100.0));
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.language == 'EN'
                ? 'Weekly Energy Forecast'
                : 'साप्ताहिक ऊर्जा पूर्वानुमान',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1410),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: const Color(0xFFEDE5DF),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= days.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          days[idx],
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF8A7A6A),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    color: AppTheme.gold,
                    barWidth: 2.5,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 3,
                            color: AppTheme.gold,
                            strokeWidth: 2,
                            strokeColor: AppTheme.backgroundDark,
                          ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.gold.withAlpha(51),
                          AppTheme.gold.withAlpha(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
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

  Widget _buildNoPalmDataBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.goldMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold.withAlpha(60)),
      ),
      child: Column(
        children: [
          const Icon(Icons.back_hand_outlined, color: AppTheme.gold, size: 32),
          const SizedBox(height: 12),
          Text(
            widget.language == 'EN'
                ? 'Scan Your Palm for Personalized Weekly Predictions'
                : 'व्यक्तिगत साप्ताहिक भविष्यवाणियों के लिए अपनी हथेली स्कैन करें',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.gold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.language == 'EN'
                ? 'Complete a palm scan to unlock personalized weekly predictions based on your actual palm analysis.'
                : 'व्यक्तिगत साप्ताहिक भविष्यवाणियाँ अनलॉक करने के लिए हथेली स्कैन पूरा करें।',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
