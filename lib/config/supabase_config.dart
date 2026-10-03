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

  /// Reads SUPABASE_URL and the client key from env.json when dart-defines
  /// were not passed. Compile-time values always win.
  static Future<void> loadFromEnvFile() async {
    if (_compileTimeConfigured) return;
    try {
      final raw = await rootBundle.loadString('env.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _fileUrl = _stringValue(decoded['SUPABASE_URL']);
      _fileAnonKey = _stringValue(decoded['SUPABASE_ANON_KEY']);
      _filePublishableKey = _stringValue(decoded['SUPABASE_PUBLISHABLE_KEY']);
    } catch (_) {
      // main.dart reports a missing configuration if both sources are empty.
    }
  }

  static String _stringValue(Object? value) {
    if (value is! String) return '';
    return value.trim();
  }

  static bool get _compileTimeConfigured =>
      _envUrl.isNotEmpty &&
      (_legacyAnonKey.isNotEmpty || _publishableKey.isNotEmpty);

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
