import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/personalized_predictions_service.dart';
import '../../../theme/app_theme.dart';
import './prediction_card_widget.dart';

class YearlyPredictionsWidget extends StatefulWidget {
  final String language;

  const YearlyPredictionsWidget({super.key, required this.language});

  @override
  State<YearlyPredictionsWidget> createState() =>
      _YearlyPredictionsWidgetState();
}

class _YearlyPredictionsWidgetState extends State<YearlyPredictionsWidget> {
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

    final predictions = _data?.yearly ?? [];
    final isPersonalized =
        _data?.isPersonalized == true && predictions.isNotEmpty;
    final now = DateTime.now();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildYearHeader(now.year, isPersonalized),
          const SizedBox(height: 16),
          if (!isPersonalized)
            _buildNoPalmDataBanner()
          else ...[
            _buildQuarterTimeline(predictions),
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

  Widget _buildYearHeader(int year, bool isPersonalized) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.goldMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppTheme.gold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.language == 'EN'
                  ? '$year Annual Reading'
                  : '$year वार्षिक पठन',
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

  Widget _buildQuarterTimeline(List<PersonalizedPrediction> predictions) {
    final avgScore = predictions.isNotEmpty
        ? predictions.map((p) => p.confidence).reduce((a, b) => a + b) /
              predictions.length
        : 75.0;

    final quarters = widget.language == 'EN'
        ? [
            _QuarterData(
              'Q1',
              'Jan–Mar',
              (avgScore - 5).clamp(50, 100).toInt(),
              'Foundation',
            ),
            _QuarterData(
              'Q2',
              'Apr–Jun',
              (avgScore + 3).clamp(50, 100).toInt(),
              'Growth',
            ),
            _QuarterData(
              'Q3',
              'Jul–Sep',
              (avgScore + 8).clamp(50, 100).toInt(),
              'Peak',
            ),
            _QuarterData(
              'Q4',
              'Oct–Dec',
              (avgScore + 5).clamp(50, 100).toInt(),
              'Harvest',
            ),
          ]
        : [
            _QuarterData(
              'Q1',
              'जन–मार',
              (avgScore - 5).clamp(50, 100).toInt(),
              'नींव',
            ),
            _QuarterData(
              'Q2',
              'अप्र–जून',
              (avgScore + 3).clamp(50, 100).toInt(),
              'विकास',
            ),
            _QuarterData(
              'Q3',
              'जुल–सित',
              (avgScore + 8).clamp(50, 100).toInt(),
              'शिखर',
            ),
            _QuarterData(
              'Q4',
              'अक्ट–दिस',
              (avgScore + 5).clamp(50, 100).toInt(),
              'कटाई',
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.language == 'EN'
                ? 'Quarterly Energy Flow'
                : 'त्रैमासिक ऊर्जा प्रवाह',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: quarters.map((q) {
              final isPeak = q.score >= 90;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 4 + (q.score / 100 * 60),
                        decoration: BoxDecoration(
                          color: isPeak
                              ? AppTheme.gold
                              : AppTheme.gold.withOpacity(0.3 + q.score / 200),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        q.label,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isPeak
                              ? AppTheme.gold
                              : AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        q.range,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        q.theme,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isPeak ? AppTheme.gold : AppTheme.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '${q.score}%',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1410),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
                ? 'Scan Your Palm for Personalized Yearly Predictions'
                : 'व्यक्तिगत वार्षिक भविष्यवाणियों के लिए अपनी हथेली स्कैन करें',
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
                ? 'Complete a palm scan to unlock personalized yearly predictions based on your actual palm analysis.'
                : 'व्यक्तिगत वार्षिक भविष्यवाणियाँ अनलॉक करने के लिए हथेली स्कैन पूरा करें।',
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

class _QuarterData {
  final String label;
  final String range;
  final int score;
  final String theme;

  const _QuarterData(this.label, this.range, this.score, this.theme);
}
