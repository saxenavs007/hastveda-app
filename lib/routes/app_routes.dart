import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presentation/home_screen/home_screen.dart';
import '../presentation/palm_scan_screen/palm_scan_screen.dart';
import '../presentation/predictions_screen/predictions_screen.dart';
import '../presentation/premium_paywall_screen/premium_paywall_screen.dart';
import '../presentation/couple_reading_screen/couple_reading_screen.dart';
import '../presentation/couple_reading_screen/couple_reading_result_screen.dart';
import '../presentation/couple_reading_screen/couple_reading_history_screen.dart';
import '../presentation/detailed_report_screen/detailed_report_screen.dart';
import '../presentation/report_history_screen/report_history_screen.dart';
import '../presentation/splash_screen/splash_screen.dart';
import '../presentation/onboarding_screen/onboarding_screen.dart';
import '../presentation/login_screen/login_screen.dart';
import '../presentation/profile_screen/profile_screen.dart';
import '../presentation/settings_screen/settings_screen.dart';
import '../presentation/notifications_screen/notifications_screen.dart';
import '../presentation/palm_analysis_screen/palm_analysis_screen.dart';
// palm_line_screen.dart now defines only PalmLineScreen — every category screen
// lives in premium_content_screens.dart, so no `hide` clause is needed and there
// is exactly one implementation (and one gate) per route.
import '../presentation/palm_line_screen/palm_line_screen.dart';
import '../presentation/static_screens/static_screens.dart';
import '../presentation/reading_history_screen/reading_history_screen.dart';
import '../widgets/app_scaffold.dart';
import '../presentation/couple_reading_screen/couple_tab_screen.dart';
import '../presentation/reading_comparison_screen/reading_comparison_screen.dart';
import '../presentation/premium_screens/premium_content_screens.dart';
import '../presentation/admin_screen/admin_discount_dashboard.dart';
import '../presentation/admin_screen/admin_reviews_dashboard.dart';
import '../presentation/ask_hastveda_screen/ask_hastveda_screen.dart';
import '../presentation/remedies_screen/remedies_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String homeScreen = '/home-screen';
  static const String palmScanScreen = '/palm-scan-screen';
  static const String predictionsScreen = '/predictions-screen';
  static const String premiumPaywall = '/premium-paywall';
  static const String coupleReading = '/couple-reading';
  static const String coupleReadingResult = '/couple-reading-result';
  static const String coupleReadingHistory = '/couple-reading-history';
  static const String detailedReport = '/detailed-report';
  static const String reportHistory = '/report-history';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String notifications = '/notifications';
  static const String palmAnalysis = '/palm-analysis';
  static const String palmProfile = '/palm-profile';
  static const String lifeLine = '/life-line';
  static const String heartLine = '/heart-line';
  static const String headLine = '/head-line';
  static const String fateLine = '/fate-line';
  static const String sunLine = '/sun-line';
  static const String mercuryLine = '/mercury-line';
  static const String marriageIndicators = '/marriage-indicators';
  static const String mountAnalysis = '/mount-analysis';
  static const String palmMarks = '/palm-marks';
  static const String personality = '/personality';
  static const String loveRelationships = '/love-relationships';
  static const String wealthFinances = '/wealth-finances';
  static const String careerBusiness = '/career-business';
  static const String futureTendencies = '/future-tendencies';
  static const String readingHistory = '/reading-history';
  static const String detailedReading = '/detailed-reading';
  static const String languageSelection = '/language-selection';
  static const String helpAbout = '/help-about';
  static const String privacyPolicy = '/privacy-policy';
  static const String termsConditions = '/terms-conditions';
  static const String aiDisclaimer = '/ai-disclaimer';
  static const String readingComparison = '/reading-comparison';
  static const String readingSelection = '/reading-selection';
  static const String adminDiscountDashboard = '/admin-discount-dashboard';
  static const String adminReviewsDashboard = '/admin-reviews-dashboard';
  static const String askHastveda = '/ask-hastveda';
  static const String remedies = '/remedies';
}

CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      );
    },
  );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}

CustomTransitionPage<void> _bottomSheetPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      );
    },
  );
}

/// True when a Supabase session exists on this device.
///
/// Wrapped in a try/catch because `Supabase.instance` throws if initialization
/// failed (missing credentials). A backend we cannot reach is treated as
/// signed-out, which routes the user to Login rather than into a scan that
/// would fail at the first database write.
bool _hasActiveSession() {
  try {
    return Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

/// Palm scanning writes biometric data to user-scoped tables and consumes the
/// account's monthly free-scan quota, so it cannot run without a signed-in
/// user. Guest scanning was removed for this reason; this guard also catches
/// the case where a session expired while the app was open. The originating
/// location is carried through so Login can return the user here afterwards.
String? _requireAccountForScan(BuildContext context, GoRouterState state) {
  if (_hasActiveSession()) return null;
  return Uri(
    path: AppRoutes.login,
    queryParameters: {'redirect': state.matchedLocation},
  ).toString();
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.initial,
  routes: [
    // Splash
    GoRoute(
      path: AppRoutes.splash,
      pageBuilder: (context, state) => _fadePage(state, const SplashScreen()),
    ),
    // Onboarding
    GoRoute(
      path: AppRoutes.onboarding,
      pageBuilder: (context, state) =>
          _fadePage(state, const OnboardingScreen()),
    ),
    // Login
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (context, state) => _fadePage(
        state,
        LoginScreen(redirectTo: state.uri.queryParameters['redirect']),
      ),
    ),
    // Premium Paywall
    GoRoute(
      path: AppRoutes.premiumPaywall,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        final returnRoute = state.uri.queryParameters['return'];
        return _bottomSheetPage(
          state,
          PremiumPaywallScreen(locale: locale, returnRoute: returnRoute),
        );
      },
    ),
    // Couple Reading
    GoRoute(
      path: AppRoutes.coupleReading,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, CoupleReadingScreen(locale: locale));
      },
    ),
    // Couple Reading Result
    GoRoute(
      path: AppRoutes.coupleReadingResult,
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final locale = extra['locale'] as String? ?? 'en';
        final compatibility =
            extra['compatibility'] as Map<String, dynamic>? ?? {};
        return _fadePage(
          state,
          CoupleReadingResultScreen(
            compatibility: {
              ...compatibility,
              'person1_name': extra['person1Name'] as String? ?? 'Person 1',
              'person2_name': extra['person2Name'] as String? ?? 'Person 2',
            },
            locale: locale,
          ),
        );
      },
    ),
    // Couple Reading History
    GoRoute(
      path: AppRoutes.coupleReadingHistory,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, CoupleReadingHistoryScreen(locale: locale));
      },
    ),
    // Detailed Report
    GoRoute(
      path: AppRoutes.detailedReport,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final analysisId = extra['analysis_id'] as String?;
        final readingId = extra['reading_id'] as String?;
        return _slidePage(
          state,
          DetailedReportScreen(
            locale: locale,
            analysisId: analysisId,
            readingId: readingId,
          ),
        );
      },
    ),
    // Report History
    GoRoute(
      path: AppRoutes.reportHistory,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, ReportHistoryScreen(locale: locale));
      },
    ),
    // Profile
    GoRoute(
      path: AppRoutes.profile,
      pageBuilder: (context, state) => _slidePage(state, const ProfileScreen()),
    ),
    // Settings
    GoRoute(
      path: AppRoutes.settings,
      pageBuilder: (context, state) =>
          _slidePage(state, const SettingsScreen()),
    ),
    // Notifications
    GoRoute(
      path: AppRoutes.notifications,
      pageBuilder: (context, state) =>
          _slidePage(state, const NotificationsScreen()),
    ),
    // Palm Analysis
    GoRoute(
      path: AppRoutes.palmAnalysis,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        final extra = state.extra as Map<String, dynamic>?;
        // If extra contains only 'analysis_id', load from DB (history navigation)
        final analysisId = extra?['analysis_id'] as String?;
        final hasFullData = extra != null && extra.containsKey('overall_score');
        return _slidePage(
          state,
          PalmAnalysisScreen(
            locale: locale,
            analysisData: hasFullData ? extra : null,
            analysisId: analysisId,
          ),
        );
      },
    ),
    // Palm Profile
    GoRoute(
      path: AppRoutes.palmProfile,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, PalmProfileScreen(locale: locale));
      },
    ),
    // Life Line
    GoRoute(
      path: AppRoutes.lifeLine,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          PalmLineScreen(lineKey: 'life', locale: locale),
        );
      },
    ),
    // Heart Line
    GoRoute(
      path: AppRoutes.heartLine,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          PalmLineScreen(lineKey: 'heart', locale: locale),
        );
      },
    ),
    // Head Line
    GoRoute(
      path: AppRoutes.headLine,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          PalmLineScreen(lineKey: 'head', locale: locale),
        );
      },
    ),
    // Fate Line
    GoRoute(
      path: AppRoutes.fateLine,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          PalmLineScreen(lineKey: 'fate', locale: locale),
        );
      },
    ),
    // Sun Line
    GoRoute(
      path: AppRoutes.sunLine,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          PalmLineScreen(lineKey: 'sun', locale: locale),
        );
      },
    ),
    // Mercury Line
    GoRoute(
      path: AppRoutes.mercuryLine,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          PalmLineScreen(lineKey: 'mercury', locale: locale),
        );
      },
    ),
    // Marriage Indicators
    GoRoute(
      path: AppRoutes.marriageIndicators,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, MarriageIndicatorsScreen(locale: locale));
      },
    ),
    // Mount Analysis
    GoRoute(
      path: AppRoutes.mountAnalysis,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, MountAnalysisScreen(locale: locale));
      },
    ),
    // Palm Marks
    GoRoute(
      path: AppRoutes.palmMarks,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, PalmMarksScreen(locale: locale));
      },
    ),
    // Personality
    GoRoute(
      path: AppRoutes.personality,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, PersonalityScreen(locale: locale));
      },
    ),
    // Love & Relationships
    GoRoute(
      path: AppRoutes.loveRelationships,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, LoveRelationshipsScreen(locale: locale));
      },
    ),
    // Wealth & Finances
    GoRoute(
      path: AppRoutes.wealthFinances,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, WealthFinancesScreen(locale: locale));
      },
    ),
    // Career & Business
    GoRoute(
      path: AppRoutes.careerBusiness,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, CareerBusinessScreen(locale: locale));
      },
    ),
    // Future Tendencies
    GoRoute(
      path: AppRoutes.futureTendencies,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, FutureTendenciesScreen(locale: locale));
      },
    ),
    // Reading Comparison (direct with IDs)
    GoRoute(
      path: AppRoutes.readingComparison,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final readingIdA = extra['reading_id_a'] as String? ?? '';
        final readingIdB = extra['reading_id_b'] as String? ?? '';
        return _slidePage(
          state,
          ReadingComparisonScreen(
            readingIdA: readingIdA,
            readingIdB: readingIdB,
            locale: locale,
          ),
        );
      },
    ),
    // Reading Selection (entry point from history)
    GoRoute(
      path: AppRoutes.readingSelection,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, ReadingSelectionScreen(locale: locale));
      },
    ),
    // Reading History
    GoRoute(
      path: AppRoutes.readingHistory,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, ReadingHistoryScreen(locale: locale));
      },
    ),
    // Detailed Reading
    GoRoute(
      path: AppRoutes.detailedReading,
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(
          state,
          DetailedReadingScreen(
            readingId: extra?['readingId'] as String?,
            locale: locale,
          ),
        );
      },
    ),
    // Language Selection
    GoRoute(
      path: AppRoutes.languageSelection,
      pageBuilder: (context, state) =>
          _slidePage(state, const LanguageSelectionScreen()),
    ),
    // Help & About
    GoRoute(
      path: AppRoutes.helpAbout,
      pageBuilder: (context, state) =>
          _slidePage(state, const HelpAboutScreen()),
    ),
    // Privacy Policy
    GoRoute(
      path: AppRoutes.privacyPolicy,
      pageBuilder: (context, state) =>
          _slidePage(state, const PrivacyPolicyScreen()),
    ),
    // Terms & Conditions
    GoRoute(
      path: AppRoutes.termsConditions,
      pageBuilder: (context, state) =>
          _slidePage(state, const TermsConditionsScreen()),
    ),
    // AI Disclaimer
    GoRoute(
      path: AppRoutes.aiDisclaimer,
      pageBuilder: (context, state) =>
          _slidePage(state, const AiDisclaimerScreen()),
    ),
    // Admin Discount Dashboard
    GoRoute(
      path: AppRoutes.adminDiscountDashboard,
      pageBuilder: (context, state) =>
          _slidePage(state, const AdminDiscountDashboard()),
    ),
    // Admin Reviews Dashboard
    GoRoute(
      path: AppRoutes.adminReviewsDashboard,
      pageBuilder: (context, state) =>
          _slidePage(state, const AdminReviewsDashboard()),
    ),
    // Ask HastVeda
    GoRoute(
      path: AppRoutes.askHastveda,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, AskHastVedaScreen(locale: locale));
      },
    ),
    // Remedies
    GoRoute(
      path: AppRoutes.remedies,
      pageBuilder: (context, state) {
        final locale = state.uri.queryParameters['locale'] ?? 'en';
        return _slidePage(state, RemediesScreen(locale: locale));
      },
    ),
    // Main shell with bottom nav (5 branches)
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.homeScreen,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        // Branch 1: Scan
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.palmScanScreen,
              redirect: _requireAccountForScan,
              builder: (context, state) => const PalmScanScreen(),
            ),
          ],
        ),
        // Branch 2: Readings / Predictions
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.predictionsScreen,
              builder: (context, state) => const PredictionsScreen(),
            ),
          ],
        ),
        // Branch 3: Couple
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/couple-tab',
              builder: (context, state) => const CoupleTabScreen(),
            ),
          ],
        ),
        // Branch 4: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile-tab',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
