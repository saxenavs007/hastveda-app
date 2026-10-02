import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../presentation/premium_paywall_screen/premium_paywall_screen.dart';
import '../services/entitlement_notifier.dart';
import '../services/entitlement_service.dart';
import '../services/premium_strings.dart';
import '../services/theme_provider.dart';
import '../theme/app_theme.dart';

/// Premium Lock Widget — shown when a FREE user tries to access a Premium feature.
/// Displays a beautiful lock state with feature description and CTA.
/// Never crashes, never shows errors — graceful degradation.
class PremiumLockWidget extends StatelessWidget {
  final String feature;
  final String locale;
  final Widget? child;
  final bool showInline;

  const PremiumLockWidget({
    super.key,
    required this.feature,
    this.locale = 'en',
    this.child,
    this.showInline = true,
  });

  void _openPaywall(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PremiumPaywallScreen(locale: locale),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = PremiumStrings(locale: locale);

    if (showInline) {
      return _InlineLockWidget(
        feature: feature,
        strings: strings,
        onUnlock: () => _openPaywall(context),
      );
    }

    return _FullPageLockWidget(
      feature: feature,
      strings: strings,
      onUnlock: () => _openPaywall(context),
    );
  }
}

/// Inline lock widget — replaces a section within a screen
class _InlineLockWidget extends StatelessWidget {
  final String feature;
  final PremiumStrings strings;
  final VoidCallback onUnlock;

  const _InlineLockWidget({
    required this.feature,
    required this.strings,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1A0E06), AppTheme.primary.withAlpha(15)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(60), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Blur overlay hint
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.primary.withAlpha(30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Feature description (value prop first)
                  Text(
                    strings.featureLockDescription(feature),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: const Color(0xFF8B7355),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Lock badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primary.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strings.premiumFeatureLabel.replaceAll('🔒 ', ''),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Feature title
                  Text(
                    'Unlock your detailed ${strings.featureLockTitle(feature)} analysis.',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2A1A0A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // CTA button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onUnlock,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_open_rounded, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            strings.featureLockCta(feature),
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-page lock widget — used when an entire screen is gated
class _FullPageLockWidget extends StatelessWidget {
  final String feature;
  final PremiumStrings strings;
  final VoidCallback onUnlock;

  const _FullPageLockWidget({
    required this.feature,
    required this.strings,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    // The full-page lock is rendered on both the light category screens and the
    // dark analysis/predictions screens, so its text colours must follow the
    // theme — hardcoded near-black text disappeared on the dark background.
    final isDark = context.watch<ThemeProvider>().isDark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1410);
    final bodyColor = isDark ? AppTheme.textSecondary : const Color(0xFF5C4A3A);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lock icon with glow
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withAlpha(30),
                    AppTheme.primary.withAlpha(8),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primary.withAlpha(60),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.lock_rounded,
                size: 36,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            // Feature title
            Text(
              strings.featureLockTitle(feature),
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Description
            Text(
              strings.featureLockDescription(feature),
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: bodyColor,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            // Premium badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    strings.premiumFeatureLabel.replaceAll('🔒 ', ''),
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // CTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onUnlock,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_open_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      strings.featureLockCta(feature),
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience widget — checks entitlement and shows lock or child
class EntitlementGate extends StatefulWidget {
  final String feature;
  final String locale;
  final Widget child;
  final bool fullPage;

  const EntitlementGate({
    super.key,
    required this.feature,
    required this.child,
    this.locale = 'en',
    this.fullPage = false,
  });

  @override
  State<EntitlementGate> createState() => _EntitlementGateState();
}

class _EntitlementGateState extends State<EntitlementGate> {
  bool? _hasAccess;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final access = await EntitlementService.instance.canUseFeature(
      widget.feature,
      forceRefresh: true,
    );
    if (!mounted) return;
    final premium = context.read<EntitlementNotifier>().isPremium;
    setState(() => _hasAccess = access || premium);
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<EntitlementNotifier>().isPremium;
    if (_hasAccess == null && !premium) {
      // Loading state — show skeleton
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F3),
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    if (premium || _hasAccess == true) {
      return widget.child;
    }

    return PremiumLockWidget(
      feature: widget.feature,
      locale: widget.locale,
      showInline: !widget.fullPage,
    );
  }
}

/// Free tier limit banner — shown when user reaches a free limit
class FreeLimitBanner extends StatelessWidget {
  final String limitType;
  final int limit;
  final String locale;
  final VoidCallback? onUpgrade;

  const FreeLimitBanner({
    super.key,
    required this.limitType,
    required this.limit,
    this.locale = 'en',
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final strings = PremiumStrings(locale: locale);

    String title;
    String message;

    switch (limitType) {
      case 'scans_per_month':
        title = strings.freeLimitScanTitle;
        message = strings.freeLimitScanMessage(limit);
        break;
      case 'predictions_visible':
        title = strings.freeLimitPredictionsTitle;
        message = strings.freeLimitPredictionsMessage(limit);
        break;
      case 'history_days':
        title = strings.freeLimitHistoryTitle;
        message = strings.freeLimitHistoryMessage(limit);
        break;
      default:
        title = strings.freeLimitReached;
        message = strings.upgradeToPremiumBenefits;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryContainer, AppTheme.primary.withAlpha(15)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4A1500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: const Color(0xFF5C3010),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap:
                onUpgrade ??
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PremiumPaywallScreen(locale: locale),
                  ),
                ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                strings.unlockPremiumCta,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
