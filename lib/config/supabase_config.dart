// ============================================================
// HastVeda Supabase Configuration
// ============================================================
// Credentials come from --dart-define / --dart-define-from-file=env.json.
// A local `flutter run` with no defines falls back to the env.json asset.
//
// SUPABASE_PUBLISHABLE_KEY is the new client-facing key (sb_publishable_...).
// It replaces the legacy SUPABASE_ANON_KEY for all Flutter client usage.
//
// The sb_secret_... key is a privileged server-side key and must NEVER
// appear in Flutter, Android APK, env.json, or any client-side code.
//
// DO NOT commit real credentials to a public repository.
// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SupabaseConfig {
  /// Supabase Project URL — injected via --dart-define at build time.
  static const String _envUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// New publishable key (sb_publishable_...) — the correct client-facing key
  /// for the new Supabase API-key system. Injected via --dart-define.
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// Legacy anon key — kept as fallback for builds that have not yet
  /// received the publishable key injection. Will be removed once
  /// SUPABASE_PUBLISHABLE_KEY is confirmed working in production.
  static const String _legacyAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static String _fileUrl = '';
  static String _fileAnonKey = '';
  static String _filePublishableKey = '';

  /// Fills any value that `--dart-define` did not supply.
  /// Render's web build often has no dart-define flags, so env.json is the
  /// runtime source for the public project URL and anon key.
  static Future<void> loadFromEnvFile() async {
    if (isConfigured) return;
    try {
      final raw = await rootBundle.loadString('env.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _fileUrl = _firstUsable([
        decoded['SUPABASE_URL'],
        decoded['SUPABASE_URL_FALLBACK'],
      ]);
      _fileAnonKey = _firstUsable([
        decoded['SUPABASE_ANON_KEY'],
        decoded['SUPABASE_ANON_KEY_FALLBACK'],
      ]);
      _filePublishableKey = _usable(decoded['SUPABASE_PUBLISHABLE_KEY']);
    } catch (e) {
      debugPrint('[HastVeda] env.json was not loaded: $e');
    }
  }

  static String _firstUsable(List<Object?> values) {
    for (final value in values) {
      final text = _usable(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _stringValue(Object? value) {
    if (value is! String) return '';
    return value.trim();
  }

  /// Ignores empty strings and placeholder copies such as COPY_OF_SUPABASE_URL.
  static String _usable(Object? value) {
    final text = _stringValue(value);
    if (text.isEmpty) return '';
    final upper = text.toUpperCase();
    if (upper.startsWith('COPY_OF_') ||
        upper.startsWith('YOUR_') ||
        upper.startsWith('YOUR-')) {
      return '';
    }
    return text;
  }

  /// Returns the Supabase project URL.
  static String get url => _envUrl.isNotEmpty ? _envUrl : _fileUrl;

  /// Returns the client key. Uses the verified legacy anon key as the primary
  /// key; falls back to the publishable key only if the anon key is absent.
  static String get anonKey {
    if (_legacyAnonKey.isNotEmpty) return _legacyAnonKey;
    if (_fileAnonKey.isNotEmpty) return _fileAnonKey;
    if (_publishableKey.isNotEmpty) return _publishableKey;
    return _filePublishableKey;
  }

  /// True when both the URL and a client key are available.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
