import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

import '../routes/app_routes.dart';
import '../theme/app_theme.dart';
import '../widgets/connectivity_banner.dart';
import './config/supabase_config.dart';
import './services/analytics_service.dart';
import './services/connectivity_service.dart';
import './services/entitlement_notifier.dart';
import './services/error_logger.dart';
import './services/fcm_service.dart';
import './services/locale_provider.dart';
import './services/notification_preferences_service.dart';
import './services/supabase_service.dart';
import './services/theme_provider.dart';
import './theme/app_theme.dart';
import './widgets/app_error_boundary.dart';
import './widgets/connectivity_banner.dart';
import './widgets/hastveda_error_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global Flutter error handler ─────────────────────────────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    errorLogger.logFlutterError(details);
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  // ── Global Dart/async error handler ──────────────────────────────────────
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    errorLogger.log(
      category: ErrorCategory.appCrash,
      operation: 'unhandled_async_error',
      userMessage: 'An unexpected error occurred.',
      error: error,
      stackTrace: stack,
      severity: ErrorSeverity.critical,
    );
    if (kDebugMode) {
      debugPrint('[PlatformDispatcher] Unhandled error: $error');
    }
    return true;
  };

  // ── Supabase initialization with clear diagnostics ───────────────────────
  bool supabaseReady = false;
  String? supabaseError;

  if (!SupabaseConfig.isConfigured) {
    supabaseError =
        'Supabase credentials are missing (SUPABASE_URL / SUPABASE_ANON_KEY). '
        'Please rebuild the APK via Launch → APK so the build pipeline '
        'injects the required environment variables.';
    debugPrint('[HastVeda] ❌ $supabaseError');
  } else {
    try {
      await SupabaseService.initialize();
      supabaseReady = true;
      debugPrint('[HastVeda] ✅ Supabase initialized successfully.');
    } catch (e) {
      supabaseError = e.toString();
      errorLogger.log(
        category: ErrorCategory.supabase,
        operation: 'supabase_initialize',
        userMessage: 'Failed to connect to backend.',
        error: e,
        severity: ErrorSeverity.critical,
      );
      debugPrint('[HastVeda] ❌ Supabase init failed: $e');
    }
  }

  // Initialize FCM (stub mode until Firebase is configured)
  try {
    await FCMService.instance.initialize();
  } catch (e) {
    debugPrint('FCM init error: $e');
  }

  // Track app_opened event
  analytics.track(HastVedaEvents.appOpened);

  bool hasShownError = false;

  ErrorWidget.builder = (FlutterErrorDetails details) {
    errorLogger.logFlutterError(details);
    if (!hasShownError) {
      hasShownError = true;
      Future.delayed(const Duration(seconds: 5), () {
        hasShownError = false;
      });
      return HastVedaErrorWidget(errorDetails: details);
    }
    return const SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  ]).then((value) {
    GoRouter.optionURLReflectsImperativeAPIs = true;
    runApp(
      ProviderScope(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider(create: (_) => ConnectivityService.instance),
            ChangeNotifierProvider(
              create: (_) => NotificationPreferencesService.instance,
            ),
            ChangeNotifierProvider(create: (_) => EntitlementNotifier()),
          ],
          child: supabaseReady
              ? const MyApp()
              : _SupabaseErrorApp(message: supabaseError ?? 'Unknown error'),
        ),
      ),
    );
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Sizer(
      builder: (context, orientation, screenType) {
        return MaterialApp.router(
          title: 'HastVeda',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
          builder: (context, child) {
            // Sync system brightness to ThemeProvider for ThemeMode.system support
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final brightness = MediaQuery.of(context).platformBrightness;
              themeProvider.updateSystemBrightness(brightness);
            });
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0)),
              child: ConnectivityBanner(child: AppErrorBoundary(child: child!)),
            );
          },
          // 🚨 END CRITICAL SECTION
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
        );
      },
    );
  }
}

/// Shown when Supabase credentials are missing at startup.
/// Replaces the generic "Something went wrong" crash with a clear,
/// actionable message so the user (and developer) knows exactly what failed.
class _SupabaseErrorApp extends StatelessWidget {
  final String message;
  const _SupabaseErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/ChatGPT_Image_Aug_10__2026__12_57_14_AM-1786333327390.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'HastVeda',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: AppTheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We\'re having trouble connecting.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The app could not reach the HastVeda backend. '
                    'Please close the app and reopen it. '
                    'If the problem persists, reinstall from the latest APK.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
