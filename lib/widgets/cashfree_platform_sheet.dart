import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Browser checkout uses the Cashfree JS SDK. Android and iOS use the native SDK.
bool get cashfreeCheckoutSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<void> showCashfreePlatformSheet(
  BuildContext context, {
  required bool isHindi,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A0E06),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📱', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 12),
            Text(
              isHindi ? 'ऐप में खोलें' : 'Open in the app',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isHindi
                  ? '₹59 (₹50 + GST) का Cashfree भुगतान Android ऐप में पूरा होता है। वेब पर ऑर्डर शुरू नहीं किया जाता।'
                  : 'The ₹59 (₹50 + GST) Cashfree payment completes in the HastVeda Android app. No order is started on web or desktop.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.45,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: const Color(0xFF1A0E06),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  isHindi ? 'ठीक है' : 'Got it',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
