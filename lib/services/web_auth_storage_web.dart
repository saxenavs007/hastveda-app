import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart';

/// Removes every browser copy of the Supabase session.
///
/// GoTrue writes `sb-<project-ref>-auth-token`. Flutter web also mirrors
/// that value in localStorage as `flutter.sb-...-auth-token`.
Future<void> clearPersistedAuthSession() async {
  _strip(window.localStorage);
  _strip(window.sessionStorage);
  final prefs = await SharedPreferences.getInstance();
  final keys = prefs.getKeys().where(isSupabaseAuthStorageKey).toList();
  for (final key in keys) {
    await prefs.remove(key);
  }
}

bool isSupabaseAuthStorageKey(String key) {
  final lower = key.toLowerCase();
  return lower.contains('auth-token') ||
      lower == 'supabase.auth.token' ||
      (lower.contains('sb-') && lower.contains('auth'));
}

void _strip(Storage storage) {
  final keys = <String>[];
  for (var i = 0; i < storage.length; i++) {
    final key = storage.key(i);
    if (key != null && isSupabaseAuthStorageKey(key)) keys.add(key);
  }
  for (final key in keys) {
    storage.removeItem(key);
  }
}
