import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


// HastVeda FCM Service
// Firebase Cloud Messaging (FCM) push notification infrastructure for Android.
//
// Architecture:
//   HastVeda Android App
//   → FCM device token (captured here)
//   → Supabase (users.fcm_token — persisted here)
//   → Firebase Cloud Messaging (server-side, via Edge Function — NOT implemented here)
//   → Android device
//
// IMPORTANT:
//   - Mixpanel is NOT used for push notification delivery.
//   - This service is SEPARATE from AnalyticsService.
//   - Notification SENDING is DISABLED until Firebase configuration is provided.
//   - This service only handles: token capture, token persistence, deep-link routing.
//
// Firebase configuration required before enabling:
//   1. google-services.json placed in android/app/
//   2. firebase_messaging Flutter package added
//   3. FCM Server Key configured in Supabase Edge Function
//
// Until Firebase is configured, this service operates in STUB mode:
//   - Token capture returns null
//   - Permission requests are simulated
//   - No actual FCM calls are made

// ── FCM Deep-link destinations ────────────────────────────────────────────────
class FCMDeepLinks {
  static const String dailyPrediction = '/predictions-screen?tab=daily';
  static const String weeklyPrediction = '/predictions-screen?tab=weekly';
  static const String reportReady = '/report-history';
  static const String coupleReadingReady = '/couple-reading-result';
  static const String premium = '/premium-paywall';
  static const String home = '/home-screen';
  static const String notifications = '/notifications';
}

// ── Notification categories ───────────────────────────────────────────────────
enum NotificationCategory {
  dailyPrediction,
  readingReady,
  reportReady,
  premiumUpdates,
  importantAccount,
}

// ── FCM Service ───────────────────────────────────────────────────────────────
class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  static const String _prefFcmToken = 'hastveda_fcm_token';
  static const String _prefPermissionRequested =
      'hastveda_fcm_permission_requested';
  static const String _prefPermissionGranted =
      'hastveda_fcm_permission_granted';

  // ── Firebase configuration status ─────────────────────────────────────────
  // Set to true ONLY after google-services.json is placed and firebase_messaging is added.
  // Currently DISABLED — awaiting Firebase project configuration.
  static const bool _firebaseConfigured = false;

  String? _currentToken;
  bool _initialized = false;

  // ── Initialize FCM ─────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!_firebaseConfigured) {
      debugPrint('[FCM] Firebase not yet configured — running in stub mode.');
      debugPrint(
        '[FCM] To enable: add google-services.json to android/app/ and add firebase_messaging package.',
      );
      return;
    }

    // When Firebase is configured, initialize here:
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    // await _setupForegroundHandler();
    // await _requestPermission();
    // await _captureToken();
  }

  // ── Request notification permission ───────────────────────────────────────
  /// Returns true if permission was granted (or already granted).
  /// Shows a contextual explanation before requesting.
  Future<bool> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();

    if (!_firebaseConfigured) {
      debugPrint('[FCM] Permission request skipped — Firebase not configured.');
      // Store that we've "requested" so the prompt doesn't show repeatedly
      await prefs.setBool(_prefPermissionRequested, true);
      return false;
    }

    // When Firebase is configured:
    // final settings = await FirebaseMessaging.instance.requestPermission(
    //   alert: true, badge: true, sound: true,
    // );
    // final granted = settings.authorizationStatus == AuthorizationStatus.authorized;
    // await prefs.setBool(_prefPermissionGranted, granted);
    // await prefs.setBool(_prefPermissionRequested, true);
    // return granted;

    return false;
  }

  // ── Check if permission has been requested ─────────────────────────────────
  Future<bool> hasRequestedPermission() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPermissionRequested) ?? false;
  }

  // ── Check if permission is granted ────────────────────────────────────────
  Future<bool> isPermissionGranted() async {
    if (!_firebaseConfigured) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPermissionGranted) ?? false;
  }

  // ── Capture FCM token ──────────────────────────────────────────────────────
  Future<String?> captureToken() async {
    if (!_firebaseConfigured) {
      debugPrint('[FCM] Token capture skipped — Firebase not configured.');
      return null;
    }

    try {
      // When Firebase is configured:
      // final token = await FirebaseMessaging.instance.getToken();
      // if (token != null) {
      //   _currentToken = token;
      //   await _persistToken(token);
      // }
      // return token;
      return null;
    } catch (e) {
      debugPrint('[FCM] Token capture error: $e');
      return null;
    }
  }

  // ── Persist FCM token to Supabase ──────────────────────────────────────────
  /// Stores the FCM token in public.users.fcm_token.
  /// Uses upsert to avoid duplicates.
  Future<void> persistToken(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Check if token already matches — avoid unnecessary writes
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString(_prefFcmToken);
      if (cachedToken == token) return;

      await Supabase.instance.client.from('users').upsert({
        'id': userId,
        'fcm_token': token,
        'platform': 'android',
        'last_active_at': DateTime.now().toIso8601String(),
      });

      await prefs.setString(_prefFcmToken, token);
      _currentToken = token;
      debugPrint('[FCM] Token persisted to Supabase.');
    } catch (e) {
      debugPrint('[FCM] Token persistence error: $e');
    }
  }

  // ── Clear FCM token on logout ──────────────────────────────────────────────
  Future<void> clearToken() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from('users')
            .update({'fcm_token': null})
            .eq('id', userId);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefFcmToken);
      _currentToken = null;
    } catch (e) {
      debugPrint('[FCM] Token clear error: $e');
    }
  }

  // ── Handle incoming notification (foreground) ──────────────────────────────
  /// When Firebase is configured, this will handle foreground messages.
  /// Currently a stub.
  void handleForegroundMessage(Map<String, dynamic> message) {
    if (!_firebaseConfigured) return;
    debugPrint('[FCM] Foreground message: $message');
    // When Firebase is configured:
    // final notification = message['notification'];
    // Show local notification using flutter_local_notifications
  }

  // ── Handle notification tap / deep-link ───────────────────────────────────
  /// Returns the route to navigate to based on notification data.
  /// Called when user taps a notification.
  String? resolveDeepLink(Map<String, dynamic>? data) {
    if (data == null) return null;
    final type = data['type'] as String?;
    final id = data['id'] as String?;

    switch (type) {
      case 'daily_prediction':
        return FCMDeepLinks.dailyPrediction;
      case 'weekly_prediction':
        return FCMDeepLinks.weeklyPrediction;
      case 'report_ready':
        return id != null
            ? '${FCMDeepLinks.reportReady}?id=$id'
            : FCMDeepLinks.reportReady;
      case 'couple_reading_ready':
        return FCMDeepLinks.coupleReadingReady;
      case 'premium':
        return FCMDeepLinks.premium;
      case 'account':
        return FCMDeepLinks.notifications;
      default:
        return FCMDeepLinks.home;
    }
  }

  String? get currentToken => _currentToken;
  bool get isFirebaseConfigured => _firebaseConfigured;
}
