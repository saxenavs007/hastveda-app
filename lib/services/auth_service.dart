import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './entitlement_service.dart';
import './fcm_service.dart';
import './supabase_service.dart';

/// Centralized authentication service for HastVeda.
/// Handles sign-up, sign-in, sign-out, and auth state.
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  final SupabaseService _supabase = SupabaseService.instance;

  User? get currentUser => _supabase.currentUser;
  bool get isAuthenticated => _supabase.isAuthenticated;
  Stream<AuthState> get authStateChanges => _supabase.authStateChanges;

  /// Sign up with email and password.
  /// Returns null on success, error message on failure.
  Future<String?> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _supabase.signUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      if (response.user == null) {
        return 'Sign up failed. Please try again.';
      }
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('signUp error: $e');
      return 'An unexpected error occurred.';
    }
  }

  /// Sign in with email and password.
  /// Returns null on success, error message on failure.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.signIn(email: email, password: password);
      if (response.user == null) {
        return 'Sign in failed. Please check your credentials.';
      }
      return null;
    } on AuthException catch (e, stack) {
      debugPrint('[HastVeda] signIn AuthException: ${e.message} (${e.statusCode})');
      debugPrint('$stack');
      return e.message;
    } catch (e, stack) {
      debugPrint('[HastVeda] signIn failed: $e');
      debugPrint('$stack');
      return e.toString();
    }
  }

  /// Revokes every server session, then drops the cached token on this device.
  Future<void> signOut() async {
    try {
      await FCMService.instance.clearToken();
    } catch (e) {
      debugPrint('[HastVeda] FCM token clear skipped: $e');
    }
    try {
      if (SupabaseService.isReady) {
        await Supabase.instance.client.auth
            .signOut(scope: SignOutScope.global)
            .timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      debugPrint('[HastVeda] global signOut: $e');
      try {
        if (SupabaseService.isReady) {
          await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        }
      } catch (localError) {
        debugPrint('[HastVeda] local signOut: $localError');
      }
    }
    try {
      await _supabase.clearLocalAuthState();
    } catch (e) {
      debugPrint('[HastVeda] auth storage clear: $e');
    }
    if (SupabaseService.isReady &&
        Supabase.instance.client.auth.currentSession != null) {
      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        await _supabase.clearLocalAuthState();
      } catch (e) {
        debugPrint('[HastVeda] leftover session clear: $e');
      }
    }
    EntitlementService.instance.invalidateCache();
  }

  /// Send password reset email.
  Future<String?> resetPassword(String email) async {
    try {
      await _supabase.resetPassword(email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Failed to send reset email.';
    }
  }

  /// Get the current user's profile.
  Future<UserProfile?> getUserProfile() => _supabase.getUserProfile();

  /// Update the current user's profile.
  Future<UserProfile?> updateProfile(Map<String, dynamic> updates) =>
      _supabase.updateUserProfile(updates);

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() => _supabase.completeOnboarding();
}
