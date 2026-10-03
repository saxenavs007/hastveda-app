import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../routes/app_routes.dart';
import 'notification_preferences_service.dart';

/// Pops a morning horoscope alert on the phone lock screen and notification shade.
/// Tapping it opens the daily horoscope. Web and desktop skip scheduling.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  static const int _dailyId = 810;
  static const String _channelId = 'hastveda_daily_horoscope';
  static const String _payload = '/insight-preview';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (kIsWeb || _ready) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _open(payload);
      }
    }

    _ready = true;
    await _scheduleMorningAlert();
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) _open(payload);
  }

  void _open(String payload) {
    final target = payload.startsWith('/') ? payload : _payload;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      appRouter.go(target);
    });
  }

  Future<void> _scheduleMorningAlert() async {
    try {
      await NotificationPreferencesService.instance.load();
    } catch (_) {}
    final prefs = NotificationPreferencesService.instance.preferences;
    if (!prefs.pushEnabled || !prefs.dailyPrediction) {
      await _plugin.cancel(_dailyId);
      return;
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Daily horoscope',
        channelDescription: 'Morning palm horoscope from your saved scan',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Your daily horoscope is ready',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
      ),
    );

    final when = _nextEightAm();
    await _plugin.zonedSchedule(
      _dailyId,
      'Your daily horoscope is ready',
      'Today’s palm reading, based on your scan, is waiting.',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: _payload,
    );
  }

  /// 08:00 IST every day. Stored as 02:30 UTC so the alarm does not
  /// depend on the device timezone database.
  tz.TZDateTime _nextEightAm() {
    final now = tz.TZDateTime.now(tz.UTC);
    var scheduled = tz.TZDateTime.utc(now.year, now.month, now.day, 2, 30);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
