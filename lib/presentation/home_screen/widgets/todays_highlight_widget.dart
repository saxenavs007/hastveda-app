import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Today's Highlight widget — shows only when real prediction data exists
class TodaysHighlightWidget extends StatelessWidget {
  final String? predictionText;
  final int? confidence;

  const TodaysHighlightWidget({
    super.key,
    this.predictionText,
    this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    // Only render if there's real prediction data
    if (predictionText == null || predictionText!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8650A).withAlpha(51)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8650A).withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const CustomIconWidget(
                    iconName: 'wb_sunny',
                    color: Color(0xFFE8650A),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Highlight",
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1410),
                    ),
                  ),
                ],
              ),
              if (confidence != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8650A).withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$confidence% Confidence',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFE8650A),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              predictionText!,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF3A2A1A),
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '⚠️ Palmistry interpretation — not a guaranteed prediction',
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: const Color(0xFFBDAA9A),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
