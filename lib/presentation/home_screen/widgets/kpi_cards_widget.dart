import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../widgets/custom_icon_widget.dart';

/// KPI cards widget — shows empty/placeholder state for new users
/// Real data is loaded by HomeScreen and passed in
class KpiCardsWidget extends StatelessWidget {
  final int? totalScans;
  final double? avgConfidence;

  const KpiCardsWidget({super.key, this.totalScans, this.avgConfidence});

  @override
  Widget build(BuildContext context) {
    final hasData = totalScans != null && totalScans! > 0;

    if (!hasData) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'Total Scans',
            value: '$totalScans',
            iconName: 'back_hand',
            accentColor: const Color(0xFFE8650A),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            label: 'Avg Confidence',
            value: '${avgConfidence?.toStringAsFixed(0) ?? 0}%',
            iconName: 'auto_awesome',
            accentColor: const Color(0xFF8B5CF6),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String iconName;
  final Color accentColor;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.iconName,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 12,
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
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: const Color(0xFF5C4A3A),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(31),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CustomIconWidget(
                  iconName: iconName,
                  color: accentColor,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A1410),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
