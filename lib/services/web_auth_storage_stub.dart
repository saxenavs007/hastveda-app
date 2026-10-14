import 'package:shared_preferences/shared_preferences.dart';

/// Removes the on-device Supabase session. Mobile stores it in
/// SharedPreferences under `sb-<project-ref>-auth-token`.
Future<void> clearPersistedAuthSession() async {
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
