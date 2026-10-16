import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _morningChannelId = 'hastveda_daily_horoscope';

/// Handles an FCM message while the app is backgrounded or killed.
/// Must stay a top-level function so the background isolate can call it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  final notification = message.notification;
  final title = (notification?.title ?? message.data['title'] ?? '').toString().trim();
  final body = (notification?.body ?? message.data['body'] ?? '').toString().trim();
  if (notification != null || (title.isEmpty && body.isEmpty)) return;

  final plugin = FlutterLocalNotificationsPlugin();
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await plugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
  final route = (message.data['route'] ?? FCMDeepLinks.notifications).toString();
  await plugin.show(
    811,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _morningChannelId,
        'Daily horoscope',
        channelDescription: 'Morning palm horoscope from your saved scan',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
      ),
    ),
    payload: route,
  );
}

void registerFcmBackgroundHandler() {
  if (kIsWeb) return;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}

class FCMDeepLinks {
  static const String dailyPrediction = '/predictions-screen?tab=daily';
  static const String weeklyPrediction = '/predictions-screen?tab=weekly';
  static const String reportReady = '/report-history';
  static const String coupleReadingReady = '/couple-reading-result';
  static const String premium = '/premium-paywall';
  static const String home = '/home-screen';
  static const String notifications = '/notifications';
}

enum NotificationCategory {
  dailyPrediction,
  readingReady,
  reportReady,
  premiumUpdates,
  importantAccount,
}

class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  static const String _prefFcmToken = 'hastveda_fcm_token';
  static const String _prefFcmUser = 'hastveda_fcm_token_user';
  static const String _prefPermissionRequested =
      'hastveda_fcm_permission_requested';
  static const String _prefPermissionGranted =
      'hastveda_fcm_permission_granted';

  static const String _vapidKey =
      'BG7ed0bGM5FT5pPKFUzDIO67V6ox8nHEHhSo_vvENxchfM4EyuGQLDSFf9-tgiSEeWzIJUZu0Se6FmlyXeRlp50';

  FirebaseMessaging? _messaging;

  /// Created on first use. Reading [FirebaseMessaging.instance] at startup
  /// throws when Firebase has not been configured, which painted the error
  /// screen over the splash.
  bool get _isFirebaseReady => Firebase.apps.isNotEmpty;

  FirebaseMessaging get _firebaseMessaging {
    if (!_isFirebaseReady) {
      throw StateError('[FCM] Firebase must be initialized before messaging is accessed.');
    }
    return _messaging ??= FirebaseMessaging.instance;
  }

  // ── Firebase configuration status ─────────────────────────────────────────
  // Enabled now to fetch live tokens.
  static const bool _firebaseConfigured = true;

  String? _currentToken;
  bool _refreshListenerReady = false;
  bool _authListenerReady = false;
  String? _initializedForUser;

  // ── Initialize FCM ─────────────────────────────────────────────────────────
  /// Asks the browser for notification permission and stores an FCM token.
  /// A call before sign-in does nothing, so the prompt happens after login.
  Future<void> initialize() async {
    if (!_firebaseConfigured || !_isFirebaseReady) {
      debugPrint('[FCM] Firebase is not initialized; skipping token registration for now.');
      return;
    }
    if (!_firebaseConfigured) {
      debugPrint('[FCM] Firebase not yet configured — running in stub mode.');
      return;
    }

    String? userId;
    try {
      final auth = Supabase.instance.client.auth;
      // Startup can happen before login. Listen for a later sign-in so FCM
      // registration is retried for fresh installs and newly signed-in users.
      if (!_authListenerReady) {
        _authListenerReady = true;
        auth.onAuthStateChange.listen((state) {
          if (state.event == AuthChangeEvent.signedIn &&
              state.session?.user.id != null) {
            initialize();
          } else if (state.event == AuthChangeEvent.signedOut) {
            _initializedForUser = null;
          }
        });
      }
      userId = auth.currentUser?.id;
    } catch (_) {
      return;
    }
    if (userId == null) return;
    if (_initializedForUser == userId && await isPermissionGranted()) return;

    try {
      if (!_refreshListenerReady) {
        _refreshListenerReady = true;
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          _currentToken = newToken;
          persistToken(newToken);
        });
      }
      final token = await requestPermissionAndGetToken();
      if (token != null) _initializedForUser = userId;
    } catch (e) {
      _initializedForUser = null;
      debugPrint('[FCM] Initialization error: $e');
    }
  }

  // ── Request notification permission ───────────────────────────────────────
  Future<bool> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_isFirebaseReady) {
      debugPrint('[FCM] Firebase is not initialized; cannot request permission.');
      return false;
    }

    if (!_firebaseConfigured) {
      await prefs.setBool(_prefPermissionRequested, true);
      return false;
    }

    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    await prefs.setBool(_prefPermissionGranted, granted);
    await prefs.setBool(_prefPermissionRequested, true);
    return granted;
  }

  Future<bool> hasRequestedPermission() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPermissionRequested) ?? false;
  }

  Future<bool> isPermissionGranted() async {
    if (!_firebaseConfigured) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPermissionGranted) ?? false;
  }

  /// Browser permission prompt plus an FCM token. Call this from a click.
  Future<String?> requestPermissionAndGetToken() async {
    if (!_isFirebaseReady) {
      debugPrint('[FCM] Firebase is not initialized; cannot generate token.');
      return null;
    }
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefPermissionGranted, granted);
      await prefs.setBool(_prefPermissionRequested, true);
      if (!granted) {
        debugPrint('[FCM] Notification permission was not granted.');
        return null;
      }

      final token = await _firebaseMessaging.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (token == null) {
        debugPrint('[FCM] Token is null despite authorization.');
        return null;
      }
      _currentToken = token;
      await persistToken(token);
      debugPrint('[FCM] Token generated and saved.');
      return token;
    } catch (e) {
      debugPrint('[FCM] Error during FCM initialization: $e');
      return null;
    }
  }

  // ── Capture FCM token ──────────────────────────────────────────────────────
  Future<String?> captureToken() async {
    if (!_firebaseConfigured || !_isFirebaseReady) {
      return null;
    }

    try {
      final token = await _firebaseMessaging.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (token != null) {
        _currentToken = token;
        await persistToken(token);
      }
      return token;
    } catch (e) {
      debugPrint('[FCM] Token capture error: $e');
      return null;
    }
  }

  // ── Persist FCM token to Supabase ──────────────────────────────────────────
  Future<void> persistToken(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final prefs = await SharedPreferences.getInstance();

      // Do not skip the database write just because this browser has a cached
      // token. The users.fcm_token column may have been cleared server-side,
      // or a previous upsert may have failed before local cache was updated.
      // Treat Supabase as the source of truth and update local cache only after
      // the authenticated upsert succeeds.
      await Supabase.instance.client.from('users').upsert({
        'id': userId,
        'fcm_token': token,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'last_active_at': DateTime.now().toIso8601String(),
      });

      await prefs.setString(_prefFcmToken, token);
      await prefs.setString(_prefFcmUser, userId);
      _currentToken = token;
      debugPrint('[FCM] Token persisted to Supabase.');
    } catch (e) {
      debugPrint('[FCM] Token persistence error: $e');
    }
  }

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
      await prefs.remove(_prefFcmUser);
      _currentToken = null;
      _initializedForUser = null;
    } catch (e) {
      debugPrint('[FCM] Token clear error: $e');
    }
  }

  void handleForegroundMessage(Map<String, dynamic> message) {
    if (!_firebaseConfigured) return;
    debugPrint('[FCM] Foreground message: $message');
  }

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
      case 'morning_curiosity':
        return FCMDeepLinks.notifications;
      default:
        return FCMDeepLinks.home;
    }
  }

  String? get currentToken => _currentToken;
  bool get isFirebaseConfigured => _firebaseConfigured;
}
