import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Suppresses the OS screen timeout for the duration of a long, hands-off task.
///
/// The palm flow is the motivating case: the user holds a palm up to the camera
/// and then waits on AI generation without ever touching the screen, so the
/// system timeout can fire mid-analysis. This service is deliberately scoped —
/// nothing acquires it at app start, and the OS timeout is restored as soon as
/// the last holder lets go.
///
/// On Android the plugin sets `FLAG_KEEP_SCREEN_ON` on the Flutter activity's
/// window, so it needs no `WAKE_LOCK` permission and stops applying on its own
/// while the app is backgrounded. On iOS it toggles `isIdleTimerDisabled`.
class ScreenWakeService {
  ScreenWakeService._internal();

  static final ScreenWakeService _instance = ScreenWakeService._internal();
  static ScreenWakeService get instance => _instance;

  /// The plugin exposes one global on/off switch, so overlapping callers are
  /// reference-counted here: the timeout comes back only once every holder has
  /// released. Holders are identity-compared, so a `State` can pass `this`.
  final Set<Object> _holders = <Object>{};

  /// Serializes platform calls so a fast acquire→release pair can't land out of
  /// order and leave the flag stuck on.
  Future<void> _pending = Future<void>.value();

  @visibleForTesting
  bool get isHeld => _holders.isNotEmpty;

  /// Keeps the screen on until [release] is called with the same [holder].
  /// Calling twice with the same holder is a no-op.
  Future<void> acquire(Object holder) {
    final wasIdle = _holders.isEmpty;
    final added = _holders.add(holder);
    if (!added || !wasIdle) return _pending;
    return _apply(enable: true);
  }

  /// Releases [holder]'s claim. The screen timeout returns to normal once no
  /// other holder is left. Safe to call for a holder that never acquired.
  Future<void> release(Object holder) {
    final removed = _holders.remove(holder);
    if (!removed || _holders.isNotEmpty) return _pending;
    return _apply(enable: false);
  }

  Future<void> _apply({required bool enable}) {
    _pending = _pending.then((_) async {
      try {
        await WakelockPlus.toggle(enable: enable);
      } catch (e) {
        // A missing platform implementation (or a browser without the Screen
        // Wake Lock API) must never break the flow that asked for the lock —
        // the worst case is the screen dimming as it does today.
        debugPrint('ScreenWakeService: toggle(enable: $enable) failed — $e');
      }
    });
    return _pending;
  }
}
