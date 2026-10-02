// HastVeda Analytics Service
// Centralized analytics abstraction — wired to Mixpanel for product analytics.
// IMPORTANT: Mixpanel is used ONLY for product analytics and event tracking.
//            It is NOT used for push notification delivery.
//
// Architecture:
//   HastVeda App → AnalyticsService.track() → Mixpanel (analytics only)
//   HastVeda App → FCMService → Firebase Cloud Messaging (push notifications only)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';

// ── Platform label ────────────────────────────────────────────────────────────
// defaultTargetPlatform reports the *host* OS on web (e.g. "macOS"), so web hits
// would otherwise be indistinguishable from native ones. kIsWeb must win.
String get currentPlatform => kIsWeb ? 'web' : defaultTargetPlatform.name;

// ── Event name constants ──────────────────────────────────────────────────────
class HastVedaEvents {
  // Onboarding
  static const String onboardingStarted = 'onboarding_started';
  static const String onboardingCompleted = 'onboarding_completed';
  static const String onboardingSkipped = 'onboarding_skipped';

  // Authentication
  static const String signInStarted = 'sign_in_started';
  static const String signInSuccess = 'sign_in_success';
  static const String signInFailed = 'sign_in_failed';
  static const String signUpStarted = 'sign_up_started';
  static const String signUpSuccess = 'sign_up_success';
  static const String guestModeStarted = 'guest_mode_started';
  static const String logout = 'logout';

  // Palm Scanning
  static const String palmScanStarted = 'palm_scan_started';
  static const String cameraPermissionGranted = 'camera_permission_granted';
  static const String cameraPermissionDenied = 'camera_permission_denied';
  static const String palmCaptureStarted = 'palm_capture_started';
  static const String palmCaptureCompleted = 'palm_capture_completed';
  static const String palmScanFailed = 'palm_scan_failed';
  static const String palmAnalysisStarted = 'palm_analysis_started';
  static const String palmAnalysisCompleted = 'palm_analysis_completed';
  static const String palmAnalysisFailed = 'palm_analysis_failed';

  // Readings
  static const String readingCreated = 'reading_created';
  static const String readingViewed = 'reading_viewed';
  static const String readingHistoryViewed = 'reading_history_viewed';
  static const String readingReopened = 'reading_reopened';

  // Predictions
  static const String dailyPredictionViewed = 'daily_prediction_viewed';
  static const String weeklyPredictionViewed = 'weekly_prediction_viewed';
  static const String monthlyPredictionViewed = 'monthly_prediction_viewed';
  static const String yearlyPredictionViewed = 'yearly_prediction_viewed';

  // Premium
  static const String premiumScreenViewed = 'premium_screen_viewed';
  static const String premiumFeatureLocked = 'premium_feature_locked';
  static const String premiumCtaClicked = 'premium_cta_clicked';
  static const String purchaseStarted = 'purchase_started';
  static const String purchaseCompleted = 'purchase_completed';
  static const String purchaseFailed = 'purchase_failed';
  static const String subscriptionCancelled = 'subscription_cancelled';

  // Couple Reading
  static const String coupleReadingStarted = 'couple_reading_started';
  static const String coupleReadingCompleted = 'couple_reading_completed';
  static const String coupleReadingResultViewed =
      'couple_reading_result_viewed';

  // Reports
  static const String detailedReportStarted = 'detailed_report_started';
  static const String detailedReportCompleted = 'detailed_report_completed';
  static const String detailedReportViewed = 'detailed_report_viewed';
  static const String reportHistoryViewed = 'report_history_viewed';
  static const String reportReopened = 'report_reopened';
  static const String pdfExportStarted = 'pdf_export_started';
  static const String pdfExportCompleted = 'pdf_export_completed';
  static const String pdfExportFailed = 'pdf_export_failed';

  // Settings
  static const String languageChanged = 'language_changed';
  static const String themeChanged = 'theme_changed';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String notificationsDisabled = 'notifications_disabled';

  // App lifecycle
  static const String appOpened = 'app_opened';
  static const String appBackgrounded = 'app_backgrounded';
  static const String networkOffline = 'network_offline';
  static const String networkRestored = 'network_restored';
}

// ── Analytics Service ─────────────────────────────────────────────────────────
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  // Mixpanel REST API endpoint (ingestion)
  static const String _mixpanelIngestionUrl = 'https://api.mixpanel.com/track';
  static const String _mixpanelEngageUrl = 'https://api.mixpanel.com/engage';

  // Mixpanel project token — loaded from env
  static const String _projectToken = String.fromEnvironment(
    'MIXPANEL_TOKEN',
    defaultValue: '',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
    ),
  );

  String? _distinctId;
  String? _userTier;
  String? _language;

  // ── Identify user ───────────────────────────────────────────────────────────
  Future<void> identify({
    required String userId,
    String? tier,
    String? language,
  }) async {
    _distinctId = userId;
    _userTier = tier;
    _language = language;

    if (_projectToken.isEmpty) {
      debugPrint(
        '[Analytics] Mixpanel token not configured — skipping identify',
      );
      return;
    }

    try {
      // $set operation — update user profile in Mixpanel
      final payload = [
        {
          '\$token': _projectToken,
          '\$distinct_id': userId,
          '\$set': {
            'user_tier': tier ?? 'free',
            'language': language ?? 'en',
            'platform': currentPlatform,
            'app_name': 'HastVeda',
          },
        },
      ];
      await _dio.post(
        _mixpanelEngageUrl,
        data:
            'data=${Uri.encodeComponent(base64Encode(utf8.encode(jsonEncode(payload))))}',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
    } catch (e) {
      debugPrint('[Analytics] identify error: $e');
    }
  }

  // ── Reset (on logout) ───────────────────────────────────────────────────────
  void reset() {
    _distinctId = null;
    _userTier = null;
    _language = null;
  }

  // ── Core track method ───────────────────────────────────────────────────────
  /// Track a product event with optional privacy-safe parameters.
  /// Never pass: email, password, phone, palm images, PII, or report content.
  Future<void> track(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    // Always log in debug mode for testing
    debugPrint('[Analytics] track: $eventName ${properties ?? {}}');

    // Persist to Supabase analytics_events table (always, regardless of Mixpanel config)
    _persistToSupabase(eventName, properties);

    if (_projectToken.isEmpty) {
      debugPrint(
        '[Analytics] Mixpanel token not configured — event logged locally only',
      );
      return;
    }

    try {
      final props = <String, dynamic>{
        'token': _projectToken,
        'distinct_id': _distinctId ?? 'anonymous',
        'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'platform': currentPlatform,
        'app_name': 'HastVeda',
        if (_userTier != null) 'user_tier': _userTier,
        if (_language != null) 'language': _language,
        ...?properties,
      };

      final event = [
        {'event': eventName, 'properties': props},
      ];

      await _dio.post(
        _mixpanelIngestionUrl,
        data:
            'data=${Uri.encodeComponent(base64Encode(utf8.encode(jsonEncode(event))))}',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
    } catch (e) {
      debugPrint('[Analytics] track error for $eventName: $e');
      // Silent fail — analytics must never crash the app
    }
  }

  // ── Persist to Supabase analytics_events ────────────────────────────────────
  Future<void> _persistToSupabase(
    String eventName,
    Map<String, dynamic>? properties,
  ) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      await Supabase.instance.client.from('analytics_events').insert({
        'user_id': userId,
        'event_name': eventName,
        'event_category': _categoryFor(eventName),
        'properties': properties ?? {},
        'platform': currentPlatform,
        'app_version': '1.0.0',
      });
    } catch (_) {
      // Silent fail — do not disrupt the app
    }
  }

  String _categoryFor(String eventName) {
    if (eventName.startsWith('onboarding')) return 'onboarding';
    if (eventName.startsWith('sign_') ||
        eventName == 'logout' ||
        eventName == 'guest_mode_started') {
      return 'auth';
    }
    if (eventName.startsWith('palm_') || eventName.startsWith('camera_')) {
      return 'palm_scan';
    }
    if (eventName.startsWith('reading')) return 'reading';
    if (eventName.contains('prediction')) return 'prediction';
    if (eventName.startsWith('premium_') ||
        eventName.startsWith('purchase_') ||
        eventName == 'subscription_cancelled') {
      return 'premium';
    }
    if (eventName.startsWith('couple_')) return 'couple_reading';
    if (eventName.startsWith('detailed_report') ||
        eventName.startsWith('report_') ||
        eventName.startsWith('pdf_')) {
      return 'report';
    }
    if (eventName == 'language_changed' ||
        eventName == 'theme_changed' ||
        eventName.startsWith('notifications_')) {
      return 'settings';
    }
    return 'app';
  }

  // ── Convenience helpers ──────────────────────────────────────────────────────
  void trackWithLanguage(
    String event,
    String languageCode, [
    Map<String, dynamic>? extra,
  ]) {
    track(event, properties: {'language': languageCode, ...?extra});
  }

  void trackWithTier(String event, String tier, [Map<String, dynamic>? extra]) {
    track(event, properties: {'user_tier': tier, ...?extra});
  }
}

// ── Global singleton accessor ─────────────────────────────────────────────────
final analytics = AnalyticsService.instance;
