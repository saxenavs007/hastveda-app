import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';

class _LifeLine {
  final String nameEn;
  final String nameHi;
  final String iconName;
  final int score;
  final String descEn;
  final String descHi;
  final Color color;

  const _LifeLine({
    required this.nameEn,
    required this.nameHi,
    required this.iconName,
    required this.score,
    required this.descEn,
    required this.descHi,
    required this.color,
  });
}

class LifeLinesBreakdownWidget extends StatelessWidget {
  final String language;

  const LifeLinesBreakdownWidget({super.key, required this.language});

  static const List<_LifeLine> _lines = [
    _LifeLine(
      nameEn: 'Heart Line',
      nameHi: 'हृदय रेखा',
      iconName: 'favorite',
      score: 82,
      descEn: 'Deep emotional bonds forming',
      descHi: 'गहरे भावनात्मक संबंध बन रहे हैं',
      color: AppTheme.gold,
    ),
    _LifeLine(
      nameEn: 'Head Line',
      nameHi: 'मस्तिष्क रेखा',
      iconName: 'psychology',
      score: 91,
      descEn: 'Exceptional clarity and focus',
      descHi: 'असाधारण स्पष्टता और एकाग्रता',
      color: AppTheme.cyan,
    ),
    _LifeLine(
      nameEn: 'Life Line',
      nameHi: 'जीवन रेखा',
      iconName: 'favorite_border',
      score: 75,
      descEn: 'Strong vitality, minor stress ahead',
      descHi: 'मजबूत जीवनशक्ति, आगे थोड़ा तनाव',
      color: AppTheme.success,
    ),
    _LifeLine(
      nameEn: 'Fate Line',
      nameHi: 'भाग्य रेखा',
      iconName: 'star',
      score: 88,
      descEn: 'Career trajectory rising sharply',
      descHi: 'करियर का मार्ग तेजी से ऊपर जा रहा है',
      color: AppTheme.confetti,
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
            language == 'EN' ? 'Life Lines Analysis' : 'जीवन रेखा विश्लेषण',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1410),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            language == 'EN'
                ? 'Based on your last palm scan'
                : 'आपके अंतिम हथेली स्कैन के आधार पर',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: const Color(0xFF8A7A6A),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(_lines.length, (i) {
            final line = _lines[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: line.color.withAlpha(31),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.star, color: line.color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  language == 'EN' ? line.nameEn : line.nameHi,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A1410),
                                  ),
                                ),
                                Text(
                                  '${line.score}/100',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: line.color,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: line.score / 100,
                                backgroundColor: line.color.withAlpha(31),
                                valueColor: AlwaysStoppedAnimation(line.color),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              language == 'EN' ? line.descEn : line.descHi,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF8A7A6A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
