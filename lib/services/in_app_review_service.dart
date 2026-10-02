// HastVeda In-App Review Service
// Wraps in_app_review with conditional imports for web compatibility.
// Keeps HastVeda feedback system and Google Play rating separate.

import 'package:flutter/foundation.dart';

// Conditional import: web stub vs native
import 'in_app_review_stub.dart' if (dart.library.io) 'in_app_review_io.dart';

class InAppReviewService {
  static InAppReviewService? _instance;
  static InAppReviewService get instance =>
      _instance ??= InAppReviewService._();
  InAppReviewService._();

  /// Request the native Google Play in-app review dialog.
  /// Only works on Android. Does nothing on web.
  Future<void> requestReview() async {
    if (kIsWeb) return;
    try {
      await requestNativeReview();
    } catch (e) {
      debugPrint('InAppReviewService: $e');
    }
  }

  /// Open the app store listing directly (fallback).
  Future<void> openStoreListing() async {
    if (kIsWeb) return;
    try {
      await openNativeStoreListing();
    } catch (e) {
      debugPrint('InAppReviewService openStoreListing: $e');
    }
  }
}
