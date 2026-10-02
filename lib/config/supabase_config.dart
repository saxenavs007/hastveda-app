// ============================================================
// HastVeda Supabase Configuration
// ============================================================
// Credentials are injected at build time by the Rocket build pipeline
// via --dart-define flags from env.json.
//
// SUPABASE_PUBLISHABLE_KEY is the new client-facing key (sb_publishable_...).
// It replaces the legacy SUPABASE_ANON_KEY for all Flutter client usage.
//
// The sb_secret_... key is a privileged server-side key and must NEVER
// appear in Flutter, Android APK, env.json, or any client-side code.
//
// DO NOT commit real credentials to a public repository.
// ============================================================

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

  /// Returns the Supabase project URL.
  static String get url => _envUrl;

  /// Returns the client key. Uses the verified legacy anon key as the primary
  /// key; falls back to the publishable key only if the anon key is absent.
  static String get anonKey =>
      _legacyAnonKey.isNotEmpty ? _legacyAnonKey : _publishableKey;

  /// True when both the URL and a client key are available.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
