import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  static ConnectivityService get instance => _instance;

  ConnectivityService._internal() {
    _init();
  }

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  void _init() {
    try {
      Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 4))
          .then((results) {
        _isOnline = _resultsToOnline(results);
        notifyListeners();
      }).catchError((Object error) {
        debugPrint('Connectivity check skipped: $error');
      });

      _subscription = Connectivity().onConnectivityChanged.listen(
        (results) {
          final wasOnline = _isOnline;
          _isOnline = _resultsToOnline(results);
          if (wasOnline != _isOnline) {
            notifyListeners();
          }
        },
        onError: (Object error) {
          debugPrint('Connectivity listener skipped: $error');
        },
      );
    } catch (e) {
      debugPrint('Connectivity init skipped: $e');
    }
  }

  bool _resultsToOnline(List<ConnectivityResult> results) {
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
