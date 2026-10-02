import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/app_strings.dart';
import '../services/connectivity_service.dart';
import '../services/locale_provider.dart';
import '../theme/app_theme.dart';

/// Subtle offline/online status banner shown at the top of the screen.
/// Non-intrusive: appears briefly when status changes, then auto-hides when back online.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnim;
  bool _showBanner = false;
  bool _isOnline = true;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<double>(
      begin: -1,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleConnectivityChange(bool isOnline) {
    if (!mounted) return;

    if (!isOnline && _isOnline) {
      // Just went offline
      setState(() {
        _isOnline = false;
        _showBanner = true;
        _wasOffline = true;
      });
      _controller.forward();
    } else if (isOnline && !_isOnline) {
      // Just came back online
      setState(() {
        _isOnline = true;
        _showBanner = true;
      });
      _controller.forward();
      // Auto-hide "back online" after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _controller.reverse().then((_) {
            if (mounted) setState(() => _showBanner = false);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);

    // React to connectivity changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleConnectivityChange(connectivity.isOnline);
    });

    return Column(
      children: [
        if (_showBanner)
          AnimatedBuilder(
            animation: _slideAnim,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _slideAnim.value * 48),
                child: child,
              );
            },
            child: _ConnectivityBannerContent(
              isOnline: _isOnline,
              onlineLabel: s.backOnline,
              offlineLabel: s.youAreOffline,
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _ConnectivityBannerContent extends StatelessWidget {
  final bool isOnline;
  final String onlineLabel;
  final String offlineLabel;

  const _ConnectivityBannerContent({
    required this.isOnline,
    required this.onlineLabel,
    required this.offlineLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppTheme.success : const Color(0xFF8B4513);
    final bgColor = isOnline
        ? AppTheme.success.withAlpha(20)
        : const Color(0xFF2A1000);
    final icon = isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded;
    final label = isOnline ? onlineLabel : offlineLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline-required feature blocker widget.
/// Shows when an online-only action is attempted while offline.
class OfflineFeatureBlocker extends StatelessWidget {
  final Widget child;
  final bool requiresInternet;

  const OfflineFeatureBlocker({
    super.key,
    required this.child,
    this.requiresInternet = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!requiresInternet) return child;

    final connectivity = context.watch<ConnectivityService>();
    if (connectivity.isOnline) return child;

    AppStrings s;
    try {
      final lp = context.read<LocaleProvider>();
      s = AppStrings.of(lp.languageCode);
    } catch (_) {
      s = AppStrings.en;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF1A1000)
                    : const Color(0xFFFFF3E0),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFD4A843),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.youAreOffline,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.internetRequired,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: textSec,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Trigger a connectivity re-check by popping and retrying
                if (context.mounted) {
                  (context as Element).markNeedsBuild();
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(s.tryAgain),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: const Color(0xFF0A0A0F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
