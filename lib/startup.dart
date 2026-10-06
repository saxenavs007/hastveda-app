import 'dart:async';

final Completer<void> _startupReady = Completer<void>();

/// Completes when startup has finished or given up. It does not stay pending.
Future<void> get startupReady => _startupReady.future;

void markStartupFinished() {
  if (!_startupReady.isCompleted) _startupReady.complete();
}
