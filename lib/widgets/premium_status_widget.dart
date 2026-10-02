import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/entitlement_notifier.dart';
import '../services/entitlement_service.dart';
import '../services/premium_strings.dart';
import '../theme/app_theme.dart';
import '../presentation/premium_paywall_screen/premium_paywall_screen.dart';

/// Premium Status Widget — shows Premium Active or Free Plan
/// Used on Home screen and Profile/Dashboard
class PremiumStatusWidget extends StatefulWidget {
  final String locale;
  final bool compact;

  const PremiumStatusWidget({
    super.key,
    this.locale = 'en',
    this.compact = false,
  });

  @override
  State<PremiumStatusWidget> createState() => _PremiumStatusWidgetState();
}

class _PremiumStatusWidgetState extends State<PremiumStatusWidget> {
  EntitlementSummary? _summary;
  bool _isLoading = true;
  int _summaryGeneration = 0;
  bool _reloadedForLivePremium = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final generation = ++_summaryGeneration;
    try {
      // Force-refresh so the widget always reflects the latest entitlement
      // from the server (handles post-payment and post-login cases).
      final summary = await EntitlementService.instance.getEntitlementSummary(
        forceRefresh: true,
      );
      if (!mounted || generation != _summaryGeneration) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _summaryGeneration) return;
      setState(() => _isLoading = false);
    }
  }

  void _openPaywall() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            PremiumPaywallScreen(locale: widget.locale),
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
    final notifier = context.watch<EntitlementNotifier>();
    final notifierPremium = notifier.isPremium;
    if (notifierPremium &&
        _summary?.hasPremium != true &&
        !_reloadedForLivePremium) {
      _reloadedForLivePremium = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSummary();
      });
    }

    if (_isLoading && !notifier.isLoaded && !notifierPremium) {
      return _buildSkeleton();
    }

    final strings = PremiumStrings(locale: widget.locale);
    // Once the notifier has loaded, it is the source of truth so a logout
    // or a fresh FREE read cannot stay hidden behind a stale summary.
    final isPremium = notifier.isLoaded
        ? notifierPremium
        : (_summary?.isPremiumActive ?? false);

    if (widget.compact) {
      return _buildCompact(isPremium, strings);
    }

    return isPremium ? _buildPremiumCard(strings) : _buildFreeCard(strings);
  }

  Widget _buildSkeleton() {
    return Container(
      height: widget.compact ? 36 : 80,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildCompact(bool isPremium, PremiumStrings strings) {
    if (isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: AppTheme.goldGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF0A0A0F),
              size: 12,
            ),
            const SizedBox(width: 5),
            Text(
              strings.premiumBadge,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A0A0F),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _openPaywall,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.goldMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.gold.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 12, color: AppTheme.gold),
            const SizedBox(width: 5),
            Text(
              strings.freePlan,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildPremiumCard(PremiumStrings strings) {
    final expiresAt = _summary?.premiumExpiresAt;
    final expiryText = expiresAt != null
        ? strings.expiresOn(
            '${expiresAt.day.toString().padLeft(2, '0')} '
            '${_monthName(expiresAt.month)} '
            '${expiresAt.year}',
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.purpleMuted, AppTheme.goldMuted],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gold.withAlpha(80), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.gold.withAlpha(30),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.gold,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.premiumActive,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (expiryText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    expiryText,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              strings.premiumBadge,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A0A0F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeCard(PremiumStrings strings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineDark),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.goldMuted,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppTheme.gold,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.freePlan,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Limited features',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _openPaywall,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                strings.explorePremium,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0A0A0F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
