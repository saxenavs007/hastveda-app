// HastVeda Notification Preferences Service
// Manages user notification preferences in Supabase notification_preferences table.
// Separate from FCMService (delivery) and AnalyticsService (tracking).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Notification Preferences Model ───────────────────────────────────────────
class NotificationPreferences {
  final bool pushEnabled;
  final bool dailyPrediction;
  final bool readingReady;
  final bool reportReady;
  final bool premiumUpdates;
  final bool importantAccount;

  const NotificationPreferences({
    this.pushEnabled = true,
    this.dailyPrediction = true,
    this.readingReady = true,
    this.reportReady = true,
    this.premiumUpdates = false,
    this.importantAccount = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      pushEnabled: json['push_enabled'] as bool? ?? true,
      dailyPrediction: json['new_predictions'] as bool? ?? true,
      readingReady: json['reading_ready'] as bool? ?? true,
      reportReady: json['reading_ready'] as bool? ?? true,
      premiumUpdates: json['subscription_alerts'] as bool? ?? false,
      importantAccount: json['push_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'push_enabled': pushEnabled,
    'new_predictions': dailyPrediction,
    'reading_ready': readingReady,
    'subscription_alerts': premiumUpdates,
  };

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? dailyPrediction,
    bool? readingReady,
    bool? reportReady,
    bool? premiumUpdates,
    bool? importantAccount,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      dailyPrediction: dailyPrediction ?? this.dailyPrediction,
      readingReady: readingReady ?? this.readingReady,
      reportReady: reportReady ?? this.reportReady,
      premiumUpdates: premiumUpdates ?? this.premiumUpdates,
      importantAccount: importantAccount ?? this.importantAccount,
    );
  }
}

// ── Notification Preferences Service ─────────────────────────────────────────
class NotificationPreferencesService extends ChangeNotifier {
  NotificationPreferencesService._();
  static final NotificationPreferencesService instance =
      NotificationPreferencesService._();

  static const String _prefKey = 'hastveda_notif_prefs';

  NotificationPreferences _prefs = const NotificationPreferences();
  bool _isLoading = false;

  NotificationPreferences get preferences => _prefs;
  bool get isLoading => _isLoading;

  // ── Load preferences ───────────────────────────────────────────────────────
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final data = await Supabase.instance.client
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null) {
        _prefs = NotificationPreferences.fromJson(data);
      } else {
        // Create default preferences for new user
        await _createDefaults(userId);
      }
    } catch (e) {
      debugPrint('[NotifPrefs] Load error: $e');
      // Fall back to local cache
      await _loadFromCache();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _createDefaults(String userId) async {
    try {
      await Supabase.instance.client.from('notification_preferences').insert({
        'user_id': userId,
        ..._prefs.toJson(),
      });
    } catch (_) {}
  }

  Future<void> _loadFromCache() async {
    // Use defaults if cache unavailable
  }

  // ── Update a single preference ─────────────────────────────────────────────
  Future<void> update(NotificationPreferences updated) async {
    _prefs = updated;
    notifyListeners();

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('notification_preferences').upsert({
        'user_id': userId,
        ...updated.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[NotifPrefs] Update error: $e');
    }
  }

  // ── Toggle push enabled ────────────────────────────────────────────────────
  Future<void> togglePush(bool enabled) async {
    await update(_prefs.copyWith(pushEnabled: enabled));
  }

  // ── Toggle daily prediction ────────────────────────────────────────────────
  Future<void> toggleDailyPrediction(bool enabled) async {
    await update(_prefs.copyWith(dailyPrediction: enabled));
  }

  // ── Toggle reading ready ───────────────────────────────────────────────────
  Future<void> toggleReadingReady(bool enabled) async {
    await update(_prefs.copyWith(readingReady: enabled));
  }

  // ── Toggle report ready ────────────────────────────────────────────────────
  Future<void> toggleReportReady(bool enabled) async {
    await update(_prefs.copyWith(reportReady: enabled));
  }

  // ── Toggle premium updates ─────────────────────────────────────────────────
  Future<void> togglePremiumUpdates(bool enabled) async {
    await update(_prefs.copyWith(premiumUpdates: enabled));
  }

  // ── Toggle important account ───────────────────────────────────────────────
  Future<void> toggleImportantAccount(bool enabled) async {
    await update(_prefs.copyWith(importantAccount: enabled));
  }

  // ── Reset on logout ────────────────────────────────────────────────────────
  void reset() {
    _prefs = const NotificationPreferences();
    notifyListeners();
  }
}
