import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum BadgeType { success, warning, error, info, neutral, primary }

class StatusBadgeWidget extends StatelessWidget {
  final String label;
  final BadgeType type;

  const StatusBadgeWidget({
    super.key,
    required this.label,
    this.type = BadgeType.primary,
  });

  Color _bg() {
    switch (type) {
      case BadgeType.success:
        return const Color(0xFFDCFCE7);
      case BadgeType.warning:
        return const Color(0xFFFEF3C7);
      case BadgeType.error:
        return const Color(0xFFFEE2E2);
      case BadgeType.info:
        return const Color(0xFFEDE9FE);
      case BadgeType.neutral:
        return const Color(0xFFF3F4F6);
      case BadgeType.primary:
        return const Color(0xFFFFE8D6);
    }
  }

  Color _fg() {
    switch (type) {
      case BadgeType.success:
        return const Color(0xFF2D7A4F);
      case BadgeType.warning:
        return const Color(0xFFB45309);
      case BadgeType.error:
        return const Color(0xFFB91C1C);
      case BadgeType.info:
        return const Color(0xFF5B21B6);
      case BadgeType.neutral:
        return const Color(0xFF6B7280);
      case BadgeType.primary:
        return const Color(0xFFE8650A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _fg(),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
