import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';

class PredictionTabBarWidget extends StatelessWidget {
  final TabController tabController;
  final List<String> labels;
  final int currentTab;

  const PredictionTabBarWidget({
    super.key,
    required this.tabController,
    required this.labels,
    required this.currentTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceDark,
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppTheme.gold,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        labelColor: AppTheme.gold,
        unselectedLabelColor: AppTheme.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tabs: labels.map((label) => Tab(text: label)).toList(),
      ),
    );
  }
}
