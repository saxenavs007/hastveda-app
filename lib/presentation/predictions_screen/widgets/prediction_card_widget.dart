import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/custom_icon_widget.dart';

class PredictionEntry {
  final List<String> textEn;
  final List<String> textHi;
  final String iconName;
  final Color accentColor;
  final int confidence;
  final bool isMajorEvent;

  const PredictionEntry({
    required this.textEn,
    required this.textHi,
    required this.iconName,
    required this.accentColor,
    required this.confidence,
    this.isMajorEvent = false,
  });
}

class PredictionCardWidget extends StatelessWidget {
  final PredictionEntry entry;
  final String language;

  const PredictionCardWidget({
    super.key,
    required this.entry,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final texts = language == 'EN' ? entry.textEn : entry.textHi;
    final mainText = texts.isNotEmpty ? texts[0] : '';
    final boldPhrases = texts.length > 1 ? texts.sublist(1) : <String>[];

    TextSpan buildRichText(String text, List<String> bolds) {
      if (bolds.isEmpty) return TextSpan(text: text);
      final spans = <TextSpan>[];
      String remaining = text;
      for (final phrase in bolds) {
        final idx = remaining.indexOf(phrase);
        if (idx == -1) continue;
        if (idx > 0) {
          spans.add(TextSpan(text: remaining.substring(0, idx)));
        }
        spans.add(
          TextSpan(
            text: phrase,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.gold,
            ),
          ),
        );
        remaining = remaining.substring(idx + phrase.length);
      }
      if (remaining.isNotEmpty) spans.add(TextSpan(text: remaining));
      return TextSpan(children: spans);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: entry.isMajorEvent ? AppTheme.gold : entry.accentColor,
            width: entry.isMajorEvent ? 4 : 3,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: entry.isMajorEvent
                ? AppTheme.gold.withAlpha(26)
                : Colors.black.withAlpha(13),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: entry.iconName,
                color: entry.isMajorEvent ? AppTheme.gold : entry.accentColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                      height: 1.5,
                    ),
                    children: [buildRichText(mainText, boldPhrases)],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.cyanMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CustomIconWidget(
                      iconName: 'bolt',
                      color: AppTheme.cyan,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${entry.confidence}%',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.cyan,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.isMajorEvent) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.goldMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    language == 'EN' ? 'KEY EVENT' : 'मुख्य घटना',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
