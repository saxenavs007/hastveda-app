import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/personalized_predictions_service.dart';
import '../../../theme/app_theme.dart';
import './prediction_card_widget.dart';

class MonthlyPredictionsWidget extends StatefulWidget {
  final String language;

  const MonthlyPredictionsWidget({super.key, required this.language});

  @override
  State<MonthlyPredictionsWidget> createState() =>
      _MonthlyPredictionsWidgetState();
}

class _MonthlyPredictionsWidgetState extends State<MonthlyPredictionsWidget> {
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

    final predictions = _data?.monthly ?? [];
    final isPersonalized =
        _data?.isPersonalized == true && predictions.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthHeader(isPersonalized),
          const SizedBox(height: 16),
          if (!isPersonalized)
            _buildNoPalmDataBanner()
          else ...[
            _buildLifeAreaBarChart(context, predictions),
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

  Widget _buildMonthHeader(bool isPersonalized) {
    final now = DateTime.now();
    final months = [
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
    final monthsHi = [
      'जनवरी',
      'फरवरी',
      'मार्च',
      'अप्रैल',
      'मई',
      'जून',
      'जुलाई',
      'अगस्त',
      'सितंबर',
      'अक्टूबर',
      'नवंबर',
      'दिसंबर',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.goldMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: AppTheme.gold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.language == 'EN'
                  ? '${months[now.month - 1]} ${now.year}'
                  : '${monthsHi[now.month - 1]} ${now.year}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.gold,
              ),
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

  Widget _buildLifeAreaBarChart(
    BuildContext context,
    List<PersonalizedPrediction> predictions,
  ) {
    final areas = widget.language == 'EN'
        ? ['Career', 'Finance', 'Love', 'Health', 'Spirit']
        : ['करियर', 'वित्त', 'प्रेम', 'स्वास्थ्य', 'आत्मा'];

    // Use actual confidence scores from predictions
    final scores = [
      predictions.isNotEmpty ? predictions[0].confidence.toDouble() : 75.0,
      predictions.length > 1 ? predictions[1].confidence.toDouble() : 70.0,
      predictions.length > 2 ? predictions[2].confidence.toDouble() : 72.0,
      predictions.length > 3 ? predictions[3].confidence.toDouble() : 68.0,
      75.0,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineDark),
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
                ? 'Monthly Life Area Scores'
                : 'मासिक जीवन क्षेत्र स्कोर',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1410),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                barTouchData: BarTouchData(enabled: false),
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
                        if (idx < 0 || idx >= areas.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            areas[idx],
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: const Color(0xFF8A7A6A),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.outlineDark,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _barGroup(0, scores[0], AppTheme.gold),
                  _barGroup(1, scores[1], AppTheme.success),
                  _barGroup(2, scores[2], AppTheme.deepPurple),
                  _barGroup(3, scores[3], AppTheme.error),
                  _barGroup(4, scores[4], AppTheme.cyan),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _barGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 28,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
          ),
        ),
      ],
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
                ? 'Scan Your Palm for Personalized Monthly Predictions'
                : 'व्यक्तिगत मासिक भविष्यवाणियों के लिए अपनी हथेली स्कैन करें',
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
                ? 'Complete a palm scan to unlock personalized monthly predictions based on your actual palm analysis.'
                : 'व्यक्तिगत मासिक भविष्यवाणियाँ अनलॉक करने के लिए हथेली स्कैन पूरा करें।',
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
