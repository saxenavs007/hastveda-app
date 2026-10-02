import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/personalized_predictions_service.dart';
import '../../../theme/app_theme.dart';
import './prediction_card_widget.dart';
import './life_lines_breakdown_widget.dart';

class TodayPredictionsWidget extends StatefulWidget {
  final String language;

  const TodayPredictionsWidget({super.key, required this.language});

  @override
  State<TodayPredictionsWidget> createState() => _TodayPredictionsWidgetState();
}

class _TodayPredictionsWidgetState extends State<TodayPredictionsWidget> {
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

    final predictions = _data?.today ?? [];
    final isPersonalized =
        _data?.isPersonalized == true && predictions.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateHeader(isPersonalized),
          const SizedBox(height: 16),
          if (!isPersonalized)
            _buildNoPalmDataBanner()
          else
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
          const SizedBox(height: 8),
          LifeLinesBreakdownWidget(language: widget.language),
        ],
      ),
    );
  }

  Widget _buildDateHeader(bool isPersonalized) {
    final now = DateTime.now();
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
    final days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
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
    final daysHi = [
      'रविवार',
      'सोमवार',
      'मंगलवार',
      'बुधवार',
      'गुरुवार',
      'शुक्रवार',
      'शनिवार',
    ];

    final dateEn =
        '${days[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
    final dateHi =
        '${daysHi[now.weekday % 7]}, ${now.day} ${monthsHi[now.month - 1]} ${now.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.goldMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny, color: AppTheme.gold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.language == 'EN' ? dateEn : dateHi,
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
                ? 'Scan Your Palm for Personalized Predictions'
                : 'व्यक्तिगत भविष्यवाणियों के लिए अपनी हथेली स्कैन करें',
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
                ? 'Your predictions will be generated from your actual palm analysis once you complete a palm scan.'
                : 'एक बार हथेली स्कैन पूरा करने के बाद आपकी भविष्यवाणियाँ आपके वास्तविक हस्तरेखा विश्लेषण से उत्पन्न होंगी।',
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
