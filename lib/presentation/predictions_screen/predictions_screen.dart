import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/premium_strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../widgets/premium_lock_widget.dart';
import './widgets/monthly_predictions_widget.dart';
import './widgets/past_readings_list_widget.dart';
import './widgets/prediction_tab_bar_widget.dart';
import './widgets/today_predictions_widget.dart';
import './widgets/weekly_predictions_widget.dart';
import './widgets/yearly_predictions_widget.dart';

class PredictionsScreen extends StatefulWidget {
  const PredictionsScreen({super.key});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Replace with [Riverpod/Bloc] for production
  late TabController _tabController;
  String _selectedLanguage = 'EN';
  int _currentTab = 0;
  bool? _isPremium;

  static const List<String> _tabLabels = [
    'Today',
    'Weekly',
    'Monthly',
    'Yearly',
    'Past',
  ];

  static const List<String> _tabLabelsHi = [
    'आज',
    'साप्ताहिक',
    'मासिक',
    'वार्षिक',
    'पिछला',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
        // Track prediction tab views
        final events = [
          HastVedaEvents.dailyPredictionViewed,
          HastVedaEvents.weeklyPredictionViewed,
          HastVedaEvents.monthlyPredictionViewed,
          HastVedaEvents.yearlyPredictionViewed,
        ];
        if (_tabController.index < events.length) {
          final periods = ['daily', 'weekly', 'monthly', 'yearly'];
          analytics.track(
            events[_tabController.index],
            properties: {'prediction_period': periods[_tabController.index]},
          );
        }
      }
    });
    _checkPremium();
    // Track initial daily prediction view
    analytics.track(
      HastVedaEvents.dailyPredictionViewed,
      properties: {'prediction_period': 'daily'},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.watch<EntitlementNotifier>().isPremium && _isPremium != true) {
      _isPremium = true;
    }
  }

  Future<void> _checkPremium() async {
    final premium = await EntitlementService.instance.isPremiumUser(
      forceRefresh: true,
    );
    if (!mounted) return;
    final livePremium = context.read<EntitlementNotifier>().isPremium;
    setState(() => _isPremium = premium || livePremium);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Weekly / Monthly / Yearly are "Deep Future & Predictions" — Premium.
  /// Today's Insight stays free and is never wrapped.
  Widget _deepPredictions(Widget child) => EntitlementGate(
    feature: PremiumFeatures.deepPredictions,
    locale: _selectedLanguage.toLowerCase(),
    fullPage: true,
    child: child,
  );

  void _toggleLanguage() {
    setState(() {
      _selectedLanguage = _selectedLanguage == 'EN' ? 'HI' : 'EN';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    if (isTablet) {
      return _buildTabletLayout();
    }
    return _buildPhoneLayout();
  }

  Widget _buildPhoneLayout() {
    final labels = _selectedLanguage == 'EN' ? _tabLabels : _tabLabelsHi;
    final strings = PremiumStrings(locale: _selectedLanguage.toLowerCase());

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Column(
        children: [
          _buildHeader(),
          // Premium upgrade CTA for free users
          if (_isPremium == false)
            _PredictionUpgradeBanner(
              strings: strings,
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.premiumPaywall),
            ),
          PredictionTabBarWidget(
            tabController: _tabController,
            labels: labels,
            currentTab: _currentTab,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Today's Insight is FREE.
                TodayPredictionsWidget(language: _selectedLanguage),
                // Deep Future & Predictions is PREMIUM.
                _deepPredictions(
                  WeeklyPredictionsWidget(language: _selectedLanguage),
                ),
                _deepPredictions(
                  MonthlyPredictionsWidget(language: _selectedLanguage),
                ),
                _deepPredictions(
                  YearlyPredictionsWidget(language: _selectedLanguage),
                ),
                PastReadingsListWidget(language: _selectedLanguage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    final labels = _selectedLanguage == 'EN' ? _tabLabels : _tabLabelsHi;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Row(
        children: [
          // Left rail tabs
          Container(
            width: 160,
            color: AppTheme.surfaceDark,
            child: Column(
              children: [
                _buildHeader(compact: true),
                const SizedBox(height: 8),
                ...List.generate(5, (i) {
                  final isActive = _currentTab == i;
                  return GestureDetector(
                    onTap: () {
                      _tabController.animateTo(i);
                      setState(() => _currentTab = i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: isActive ? AppTheme.goldGradient : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        labels[i],
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? const Color(0xFF0A0A0F)
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Right content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Today's Insight is FREE.
                TodayPredictionsWidget(language: _selectedLanguage),
                // Deep Future & Predictions is PREMIUM.
                _deepPredictions(
                  WeeklyPredictionsWidget(language: _selectedLanguage),
                ),
                _deepPredictions(
                  MonthlyPredictionsWidget(language: _selectedLanguage),
                ),
                _deepPredictions(
                  YearlyPredictionsWidget(language: _selectedLanguage),
                ),
                PastReadingsListWidget(language: _selectedLanguage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({bool compact = false}) {
    return Container(
      color: AppTheme.surfaceDark,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const CustomIconWidget(
                iconName: 'back_hand',
                color: AppTheme.gold,
                size: 22,
              ),
              const SizedBox(width: 8),
              if (!compact)
                Text(
                  'Palm Predictions',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              const Spacer(),
              // Language toggle
              GestureDetector(
                onTap: _toggleLanguage,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark.withAlpha(51),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'EN',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _selectedLanguage == 'EN'
                              ? AppTheme.textSecondary
                              : AppTheme.surfaceDark.withAlpha(128),
                        ),
                      ),
                      Text(
                        ' | ',
                        style: TextStyle(
                          color: AppTheme.surfaceDark.withAlpha(102),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'हि',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _selectedLanguage == 'HI'
                              ? AppTheme.textSecondary
                              : AppTheme.surfaceDark.withAlpha(128),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark.withAlpha(51),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const CustomIconWidget(
                  iconName: 'share_outlined',
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact premium upgrade banner for predictions screen
class _PredictionUpgradeBanner extends StatelessWidget {
  final PremiumStrings strings;
  final VoidCallback onTap;

  const _PredictionUpgradeBanner({required this.strings, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8650A).withAlpha(60)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFE8650A),
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.benefitPredictions,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE8650A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                strings.unlockPremiumCta,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
