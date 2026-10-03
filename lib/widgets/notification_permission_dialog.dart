// HastVeda Notification Permission Dialog
// Contextual, non-intrusive permission request shown after onboarding.
// NOT shown on first launch — shown at an appropriate moment.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/app_strings.dart';
import '../services/locale_provider.dart';
import '../services/theme_provider.dart';
import '../services/fcm_service.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';

class NotificationPermissionDialog extends StatelessWidget {
  const NotificationPermissionDialog({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    final alreadyRequested = await FCMService.instance.hasRequestedPermission();
    if (alreadyRequested) return;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NotificationPermissionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = themeProvider.isDark;

    final bg = isDark ? AppTheme.surfaceElevated : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final primaryColor = isDark ? AppTheme.gold : AppTheme.confetti;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withAlpha(30),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: primaryColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              s.notifPermissionTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
            ),
            const SizedBox(height: 8),
            // Description
            Text(
              s.notifPermissionDesc,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: textSec,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Allow button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final granted = await FCMService.instance.requestPermission();
                  analytics.track(
                    granted
                        ? HastVedaEvents.notificationsEnabled
                        : HastVedaEvents.notificationsDisabled,
                    properties: {'source': 'permission_dialog'},
                  );
                  if (granted) {
                    await FCMService.instance.captureToken();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  s.notifPermissionAllow,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Not now button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                analytics.track(
                  HastVedaEvents.notificationsDisabled,
                  properties: {'source': 'permission_dialog_dismissed'},
                );
                // Mark as requested so we don't show again
                FCMService.instance.hasRequestedPermission();
              },
              child: Text(
                s.notifPermissionNotNow,
                style: GoogleFonts.outfit(fontSize: 14, color: textSec),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
