// Client-side palm failure logging.
//
// The Edge Function logs every failure it reaches. This covers the failures it
// never sees: no connectivity, upload errors, and any exception thrown before
// or around the function call. Together they mean a failed scan always leaves
// exactly one diagnosable row in `palm_analysis_failures`.
//
// Writes are best-effort by design — a diagnostics failure must never turn into
// a second user-visible error.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './analytics_service.dart' show currentPlatform;
import './palm_analysis_service.dart';
import './palm_failure_reason.dart';

const String kAppVersion = '1.0.0';

/// Device model string, best-effort and without adding a plugin dependency.
String? get _deviceModel {
  if (kIsWeb) return 'web';
  try {
    // e.g. "Version 16 (API 36)" on Android — enough to spot a device-specific
    // capture problem when several failures share one model.
    return Platform.operatingSystemVersion.length > 80
        ? Platform.operatingSystemVersion.substring(0, 80)
        : Platform.operatingSystemVersion;
  } catch (_) {
    return null;
  }
}

class PalmFailureLogger {
  PalmFailureLogger._();
  static final PalmFailureLogger instance = PalmFailureLogger._();

  /// Metadata sent with every analyze request so server-side failure rows carry
  /// the same device context as client-side ones.
  static Map<String, dynamic> clientMeta() => {
    'app_version': kAppVersion,
    'platform': currentPlatform,
    if (_deviceModel != null) 'device_model': _deviceModel,
  };

  /// Records a failure the server could not.
  ///
  /// [serverLogged] should be true when the Edge Function already wrote a row
  /// for this failure — the client then skips writing a duplicate.
  Future<void> logClientFailure({
    required PalmFailureReason reason,
    required String stage,
    String? scanId,
    String? handSide,
    String? language,
    String? imagePath,
    int? imageBytes,
    Object? error,
    bool serverLogged = false,
  }) async {
    if (serverLogged) return;

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return; // RLS requires an authenticated user.

      await client.from('palm_analysis_failures').insert({
        'user_id': userId,
        'scan_id': scanId,
        'hand_side': handSide,
        'language': language,
        'stage': stage,
        'failure_code': reason.code,
        'reason': _sanitize(error?.toString() ?? reason.code),
        'image_path': imagePath,
        'image_bytes': imageBytes,
        'app_version': kAppVersion,
        'platform': currentPlatform,
        'device_model': _deviceModel,
      });
    } catch (e) {
      debugPrint('PalmFailureLogger: could not record failure — $e');
    }
  }

  /// True when the Edge Function itself already wrote the failure row, i.e. the
  /// request reached it and came back with a structured reason.
  static bool wasLoggedByServer(Object error) {
    if (error is ImageQualityException) return true;
    if (error is FreeScanLimitException) return true;
    return palmAnalysisErrorCode(error) != null;
  }

  static String _sanitize(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[A-Za-z0-9_\-]{32,}'), '[REDACTED]')
        .replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [REDACTED]')
        .replaceAll(
          RegExp(r'(key|token|secret)[=:]\s*\S+', caseSensitive: false),
          r'$1=[REDACTED]',
        );
    // Bound against the cleaned length — redaction can shorten the string.
    return cleaned.substring(0, cleaned.length.clamp(0, 2000));
  }
}
