import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Recent Readings widget — accepts real data from parent
class RecentReadingsWidget extends StatelessWidget {
  final VoidCallback onViewAll;
  final List<Map<String, dynamic>> readings;

  const RecentReadingsWidget({
    super.key,
    required this.onViewAll,
    this.readings = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Readings',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1410),
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Row(
                children: [
                  Text(
                    'View All',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFE8650A),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const CustomIconWidget(
                    iconName: 'chevron_right',
                    color: Color(0xFFE8650A),
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
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
            children: List.generate(readings.length, (index) {
              final reading = readings[index];
              final createdAt = reading['created_at'] != null
                  ? DateTime.tryParse(reading['created_at'] as String)
                  : null;
              final isFirst = index == 0;
              final isLast = index == readings.length - 1;
              return Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: isFirst ? const Color(0xFFFFF3EA) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: isFirst
                            ? const Radius.circular(16)
                            : Radius.zero,
                        topRight: isFirst
                            ? const Radius.circular(16)
                            : Radius.zero,
                        bottomLeft: isLast
                            ? const Radius.circular(16)
                            : Radius.zero,
                        bottomRight: isLast
                            ? const Radius.circular(16)
                            : Radius.zero,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFE8650A).withAlpha(20),
                            ),
                            child: const Icon(
                              Icons.back_hand_rounded,
                              color: Color(0xFFE8650A),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  createdAt != null
                                      ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                                      : 'Palm Reading',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: const Color(0xFF5C4A3A),
                                  ),
                                ),
                                Text(
                                  'Palm reading completed',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: const Color(0xFF3A2A1A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                      height: 1,
                      color: Color(0xFFEDE5DF),
                      indent: 72,
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}
