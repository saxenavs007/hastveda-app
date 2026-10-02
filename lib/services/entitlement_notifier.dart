import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './entitlement_service.dart';

/// A [ChangeNotifier] that wraps [EntitlementService] and broadcasts
/// entitlement state changes to the widget tree.
///
/// This is the missing reactive layer: [EntitlementService] is a plain
/// singleton with an in-memory cache. After a payment succeeds and the cache
/// is invalidated + refreshed, nothing previously told widgets to rebuild.
/// Widgets that called [EntitlementService] in [initState] kept showing the
/// stale FREE state until the user logged out and back in.
///
/// Usage:
///   - Register in main.dart: ChangeNotifierProvider(create: (_) => EntitlementNotifier())
///   - After payment: context.read<EntitlementNotifier>().notifyPremiumGranted()
///   - In widgets: context.watch<EntitlementNotifier>().isPremium
class EntitlementNotifier extends ChangeNotifier {
  bool _isPremium = false;
  bool _isLoaded = false;
  int _epoch = 0;
  StreamSubscription<AuthState>? _authSub;

  bool get isPremium => _isPremium;
  bool get isLoaded => _isLoaded;

  EntitlementNotifier() {
    _loadInitial();
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        _onAuth,
      );
    } catch (e) {
      debugPrint('EntitlementNotifier auth listen skipped: $e');
    }
  }

  void _onAuth(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.signedOut:
        _epoch++;
        _isPremium = false;
        _isLoaded = true;
        EntitlementService.instance.invalidateCache();
        notifyListeners();
        break;
      case AuthChangeEvent.signedIn:
        _loadInitial();
        break;
      default:
        break;
    }
  }

  Future<void> _loadInitial() async {
    final epoch = ++_epoch;
    try {
      final summary = await EntitlementService.instance.getEntitlementSummary(
        forceRefresh: true,
      );
      if (epoch != _epoch) return;
      _isPremium = summary.hasPremium;
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('EntitlementNotifier initial load failed: $e');
      if (epoch != _epoch) return;
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Called after Cashfree verification has succeeded and Supabase has
  /// granted PREMIUM.
  ///
  /// Forces a fresh read of `entitlements` from Postgres, sets Premium
  /// active, and calls [notifyListeners] so open screens rebuild without
  /// a logout/login. A lagging or failed read cannot leave the session FREE:
  /// verification already committed the grant.
  Future<void> notifyPremiumGranted() async {
    final epoch = ++_epoch;
    EntitlementService.instance.invalidateCache();

    var confirmedInDb = false;
    for (var attempt = 0; attempt < 3 && !confirmedInDb; attempt++) {
      if (epoch != _epoch) return;
      try {
        final summary = await EntitlementService.instance.getEntitlementSummary(
          forceRefresh: true,
        );
        confirmedInDb = summary.hasPremium;
      } catch (e) {
        debugPrint('notifyPremiumGranted fetch failed: $e');
      }
      if (!confirmedInDb && attempt < 2 && epoch == _epoch) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    if (epoch != _epoch) return;

    if (!confirmedInDb) {
      // Drop a negative cache so the next read hits Postgres again instead
      // of sticking on FREE for the cache TTL.
      EntitlementService.instance.invalidateCache();
    }

    _isPremium = true;
    _isLoaded = true;
    debugPrint('EntitlementNotifier: PREMIUM active (dbConfirmed=$confirmedInDb)');
    notifyListeners();
  }

  /// Force-refresh from Supabase (e.g. on app resume or restore purchases).
  Future<void> refresh() async {
    final epoch = ++_epoch;
    EntitlementService.instance.invalidateCache();
    try {
      final summary = await EntitlementService.instance.getEntitlementSummary(
        forceRefresh: true,
      );
      if (epoch != _epoch) return;
      _isPremium = summary.hasPremium;
      _isLoaded = true;
    } catch (e) {
      debugPrint('EntitlementNotifier refresh failed: $e');
      if (epoch != _epoch) return;
      _isLoaded = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
