import 'package:web/web.dart';

/// Removes the browser copies of the Supabase auth session.
/// The key shape is `sb-<project-ref>-auth-token`.
void clearPersistedAuthSession() {
  _strip(window.localStorage);
  _strip(window.sessionStorage);
}

void _strip(Storage storage) {
  final keys = <String>[];
  for (var i = 0; i < storage.length; i++) {
    final key = storage.key(i);
    if (key != null && key.startsWith('sb-') && key.contains('auth')) {
      keys.add(key);
    }
  }
  for (final key in keys) {
    storage.removeItem(key);
  }
}
