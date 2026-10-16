import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'package:url_strategy/url_strategy.dart';

import './config/supabase_config.dart';
import './startup.dart';
import './services/analytics_service.dart';
import './services/connectivity_service.dart';
import './services/entitlement_notifier.dart';
import './services/error_logger.dart';
import './services/fcm_service.dart';
import './services/local_notification_service.dart';
import './services/locale_provider.dart';
import './services/notification_preferences_service.dart';
import './services/supabase_service.dart';
import './services/theme_provider.dart';
import './theme/app_theme.dart';
import './routes/app_routes.dart';
import './widgets/app_error_boundary.dart';
import './widgets/connectivity_banner.dart';
import './widgets/hastveda_error_widget.dart';

Future<void> main() async {
  // Path URLs must be chosen before the binding reads the browser location.
  // A bad <base href> used to throw here and leave the HTML error screen up.
  try {
    setPathUrlStrategy();
  } catch (e) {
    debugPrint('[HastVeda] Path URL strategy skipped: $e');
  }
  WidgetsFlutterBinding.ensureInitialized();
  // FCM requires Firebase to be initialized before FirebaseMessaging.instance
  // is accessed. Web needs explicit options; native platforms use their
  // platform configuration (for example Android google-services.json).
  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        const appEnvironment = String.fromEnvironment('APP_ENV', defaultValue: 'production');
        if (appEnvironment == 'test') {
          const apiKey = String.fromEnvironment('TEST_FIREBASE_API_KEY');
          const appId = String.fromEnvironment('TEST_FIREBASE_APP_ID');
          const senderId = String.fromEnvironment('TEST_FIREBASE_MESSAGING_SENDER_ID');
          const projectId = String.fromEnvironment('TEST_FIREBASE_PROJECT_ID');
          const authDomain = String.fromEnvironment('TEST_FIREBASE_AUTH_DOMAIN');
          const storageBucket = String.fromEnvironment('TEST_FIREBASE_STORAGE_BUCKET');
          if ([apiKey, appId, senderId, projectId, authDomain, storageBucket].any((v) => v.isEmpty)) {
            throw StateError('Test build requires a complete test Firebase configuration; production Firebase is intentionally disabled.');
          }
          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: senderId,
              projectId: projectId,
              authDomain: authDomain,
              storageBucket: storageBucket,
            ),
          );
        } else {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: 'AIzaSyBHbakAGVgamWXBBL_mFHCicOEhl61Z8FI',
              appId: '1:412267977624:web:c85847f932d18ec69869ed',
              messagingSenderId: '412267977624',
              projectId: 'hastveda-notifications',
              authDomain: 'hastveda-notifications.firebaseapp.com',
              storageBucket: 'hastveda-notifications.appfirebasestorage.app',
            ),
          );
        }
      } else {
        await Firebase.initializeApp();
      }
    }
  } catch (e) {
    debugPrint('[HastVeda] Firebase initialization failed: $e');
  }
  registerFcmBackgroundHandler();

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

  bool hasShownError = false;

  ErrorWidget.builder = (FlutterErrorDetails details) {
    errorLogger.logFlutterError(details);
    // The first frames are the splash. A late Supabase client or asset
    // miss must not paint the "Something went wrong" screen over it.
    if (!_startupSettled) {
      return const _StartupLoadingFrame();
    }
    if (!hasShownError) {
      hasShownError = true;
      Future.delayed(const Duration(seconds: 5), () {
        hasShownError = false;
      });
      return HastVedaErrorWidget(errorDetails: details);
    }
    return const SizedBox.shrink();
  };

  if (!debugForceStartupFailure) {
    try {
      await SupabaseService.ensureReady();
    } catch (e, stack) {
      debugPrint('[HastVeda] Supabase was not ready before runApp: $e');
      debugPrint('$stack');
    }
  }

  GoRouter.optionURLReflectsImperativeAPIs = true;
  runApp(
    ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider.value(value: ConnectivityService.instance),
          ChangeNotifierProvider.value(
            value: NotificationPreferencesService.instance,
          ),
          ChangeNotifierProvider(create: (_) => EntitlementNotifier()),
        ],
        child: const MyApp(),
      ),
    ),
  );
  unawaited(_boot());
}

/// Widget tests set this so startup returns without touching the network.
@visibleForTesting
bool debugForceStartupFailure = false;

const Duration _configTimeout = Duration(seconds: 5);
const Duration _backendTimeout = Duration(seconds: 8);
const Duration _serviceTimeout = Duration(seconds: 5);

/// Each startup future is capped. A timeout or throw is logged and ignored
/// so the splash can still open the dashboard.
Future<bool> _step(String label, Future<void> action, Duration limit) async {
  try {
    await action.timeout(limit);
    return true;
  } on TimeoutException {
    debugPrint('[HastVeda] $label timed out after ${limit.inSeconds}s');
    unawaited(_logStartupFailure(label, 'timed out after ${limit.inSeconds}s'));
    return false;
  } catch (e) {
    debugPrint('[HastVeda] $label failed: $e');
    unawaited(_logStartupFailure(label, e));
    return false;
  }
}

Future<void> _logStartupFailure(String label, Object error) async {
  try {
    await errorLogger
        .log(
          category: ErrorCategory.supabase,
          operation: 'startup_$label',
          userMessage: 'HastVeda could not finish starting.',
          error: error,
          severity: ErrorSeverity.high,
        )
        .timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('[HastVeda] startup log skipped: $e');
  }
}

Future<void> _boot() async {
  try {
    // These must not sit on the path to the first screen.
    unawaited(
      _step(
        'orientation',
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
        _serviceTimeout,
      ),
    );
    unawaited(_step('fcm', FCMService.instance.initialize(), _serviceTimeout));
    unawaited(
      _step(
        'notifications',
        LocalNotificationService.instance.initialize(),
        _serviceTimeout,
      ),
    );
    unawaited(
      _step(
        'analytics',
        analytics.track(HastVedaEvents.appOpened),
        _serviceTimeout,
      ),
    );
    await _prepareStartup().timeout(_backendTimeout);
  } catch (e) {
    debugPrint('[HastVeda] startup gave up: $e');
  } finally {
    _startupSettled = true;
    markStartupFinished();
  }
}

/// True after the splash has been given a ready client, or startup gave up.
bool _startupSettled = false;

/// Shown in place of the error screen while the first frame is still booting.
class _StartupLoadingFrame extends StatelessWidget {
  const _StartupLoadingFrame();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF070708),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
          ),
        ),
      ),
    );
  }
}

Future<void> _prepareStartup() async {
  if (debugForceStartupFailure) return;
  final configured = await _step(
    'config',
    SupabaseConfig.loadFromEnvFile(),
    _configTimeout,
  );
  if (!configured || !SupabaseConfig.isConfigured) {
    debugPrint('[HastVeda] continuing without server configuration');
    return;
  }
  final ready = await _step(
    'supabase',
    SupabaseService.initialize(),
    _backendTimeout,
  );
  if (!ready) {
    debugPrint('[HastVeda] continuing without a server connection');
    return;
  }
  debugPrint('[HastVeda] Supabase initialized successfully.');
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