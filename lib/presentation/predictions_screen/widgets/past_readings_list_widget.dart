import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/custom_icon_widget.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../../widgets/empty_state_widget.dart';

class _PastReading {
  final String date;
  final String dateHi;
  final String topPrediction;
  final String topPredictionHi;
  final int confidence;
  final String imageUrl;
  final String semanticLabel;
  final List<String> linesAnalyzed;

  const _PastReading({
    required this.date,
    required this.dateHi,
    required this.topPrediction,
    required this.topPredictionHi,
    required this.confidence,
    required this.imageUrl,
    required this.semanticLabel,
    required this.linesAnalyzed,
  });
}

class PastReadingsListWidget extends StatefulWidget {
  final String language;

  const PastReadingsListWidget({super.key, required this.language});

  @override
  State<PastReadingsListWidget> createState() => _PastReadingsListWidgetState();
}

class _PastReadingsListWidgetState extends State<PastReadingsListWidget> {
  // TODO: Replace with [Riverpod/Bloc] for production
  int? _expandedIndex;

  static const List<_PastReading> _pastReadings = [
    _PastReading(
      date: 'Today, Aug 9, 2026 — 9:32 AM',
      dateHi: 'आज, 9 अगस्त 2026 — 9:32 AM',
      topPrediction:
          'Career opportunity arrives before midday. Strong financial momentum.',
      topPredictionHi: 'दोपहर से पहले करियर अवसर आएगा। मजबूत वित्तीय गति।',
      confidence: 87,
      imageUrl:
          'https://images.pexels.com/photos/3259629/pexels-photo-3259629.jpeg?w=120',
      semanticLabel:
          'Close-up of an open palm showing hand lines under warm light',
      linesAnalyzed: ['Heart', 'Head', 'Life', 'Fate'],
    ),
    _PastReading(
      date: 'Aug 8, 2026 — 8:15 PM',
      dateHi: '8 अगस्त 2026 — 8:15 PM',
      topPrediction:
          'Emotional clarity and a new meaningful connection this week.',
      topPredictionHi:
          'इस सप्ताह भावनात्मक स्पष्टता और एक नया अर्थपूर्ण संबंध।',
      confidence: 82,
      imageUrl:
          'https://images.pixabay.com/photo/2018/01/15/07/51/woman-3083383_1280.jpg',
      semanticLabel:
          'Palm of a hand with visible life and heart lines in natural daylight',
      linesAnalyzed: ['Heart', 'Head', 'Life'],
    ),
    _PastReading(
      date: 'Aug 7, 2026 — 10:00 AM',
      dateHi: '7 अगस्त 2026 — 10:00 AM',
      topPrediction: 'Financial upturn indicated by strong head line depth.',
      topPredictionHi: 'मजबूत मस्तिष्क रेखा की गहराई से वित्तीय उछाल का संकेत।',
      confidence: 79,
      imageUrl:
          'https://images.pexels.com/photos/3958379/pexels-photo-3958379.jpeg?w=120',
      semanticLabel: 'Right hand palm facing up showing deep palm lines',
      linesAnalyzed: ['Head', 'Fate'],
    ),
    _PastReading(
      date: 'Aug 5, 2026 — 7:45 PM',
      dateHi: '5 अगस्त 2026 — 7:45 PM',
      topPrediction:
          'Creative breakthrough imminent. Head line shows exceptional clarity.',
      topPredictionHi:
          'रचनात्मक सफलता आसन्न है। मस्तिष्क रेखा असाधारण स्पष्टता दर्शाती है।',
      confidence: 91,
      imageUrl:
          'https://cdn.pixabay.com/photo/2016/11/29/09/16/hand-1868562_1280.jpg',
      semanticLabel:
          'Detailed palm of a hand with prominent head and life lines',
      linesAnalyzed: ['Heart', 'Head', 'Life', 'Fate'],
    ),
    _PastReading(
      date: 'Aug 3, 2026 — 11:20 AM',
      dateHi: '3 अगस्त 2026 — 11:20 AM',
      topPrediction:
          'Relationship transformation approaching. Heart line shows fork.',
      topPredictionHi:
          'रिश्ते में बदलाव आ रहा है। हृदय रेखा में विभाजन दिखता है।',
      confidence: 76,
      imageUrl:
          'https://images.pexels.com/photos/6787202/pexels-photo-6787202.jpeg?w=120',
      semanticLabel:
          'Open palm with intricate line patterns photographed from above',
      linesAnalyzed: ['Heart', 'Life'],
    ),
    _PastReading(
      date: 'Jul 30, 2026 — 9:05 AM',
      dateHi: '30 जुलाई 2026 — 9:05 AM',
      topPrediction:
          'Spiritual awakening cycle begins. Fate line shows deep upward curve.',
      topPredictionHi:
          'आध्यात्मिक जागृति चक्र शुरू होता है। भाग्य रेखा में गहरा ऊर्ध्वगामी वक्र।',
      confidence: 84,
      imageUrl:
          'https://cdn.pixabay.com/photo/2017/09/08/18/20/hands-2729034_1280.jpg',
      semanticLabel: 'Both palms held together showing symmetrical hand lines',
      linesAnalyzed: ['Fate', 'Life'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_pastReadings.isEmpty) {
      return EmptyStateWidget(
        iconName: 'history',
        title: 'No Past Readings',
        subtitle:
            'Your scan history will appear here after your first palm reading.',
        ctaLabel: 'Scan Now',
        onCta: () {},
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _pastReadings.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildPastHeader();
        }
        final reading = _pastReadings[index - 1];
        final isExpanded = _expandedIndex == index - 1;
        return _PastReadingCard(
          reading: reading,
          language: widget.language,
          isExpanded: isExpanded,
          isFirst: index - 1 == 0,
          onTap: () {
            setState(() {
              _expandedIndex = isExpanded ? null : index - 1;
            });
          },
        );
      },
    );
  }

  Widget _buildPastHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const CustomIconWidget(
            iconName: 'history',
            color: AppTheme.gold,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            widget.language == 'EN'
                ? '${_pastReadings.length} Past Readings'
                : '${_pastReadings.length} पिछले पठन',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastReadingCard extends StatelessWidget {
  final _PastReading reading;
  final String language;
  final bool isExpanded;
  final bool isFirst;
  final VoidCallback onTap;

  const _PastReadingCard({
    required this.reading,
    required this.language,
    required this.isExpanded,
    required this.isFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isHindi = language == 'HI';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: isFirst
              ? Border.all(color: AppTheme.gold.withAlpha(102))
              : Border.all(color: AppTheme.outlineDark),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomImageWidget(
                      imageUrl: reading.imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      semanticLabel: reading.semanticLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                isHindi ? reading.dateHi : reading.date,
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(26),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${reading.confidence}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isHindi
                              ? reading.topPredictionHi
                              : reading.topPrediction,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children: reading.linesAnalyzed.map((line) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.goldMuted,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                line,
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.gold,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const CustomIconWidget(
                      iconName: 'keyboard_arrow_down',
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              // Expanded detail
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: isExpanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.goldMuted,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isHindi
                                    ? 'पूर्ण भविष्यवाणी:'
                                    : 'Full Prediction:',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isHindi
                                    ? reading.topPredictionHi
                                    : reading.topPrediction,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const CustomIconWidget(
                                    iconName: 'share_outlined',
                                    color: AppTheme.gold,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isHindi ? 'साझा करें' : 'Share Reading',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.gold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
