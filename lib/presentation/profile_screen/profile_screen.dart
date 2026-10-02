import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../services/app_strings.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/notification_preferences_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hastveda_error_widget.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _subscription;
  String? _email;
  int _totalScans = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }
      _email = user.email;

      final results = await Future.wait([
        SupabaseService.instance.client
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle(),
        SupabaseService.instance.client
            .from('subscriptions')
            .select()
            .eq('user_id', user.id)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle()
            .catchError((_) => null),
        SupabaseService.instance.client
            .from('palm_scans')
            .select('id')
            .eq('user_id', user.id)
            .count(CountOption.exact)
            .then((r) => r.count)
            .catchError((_) => 0),
      ]);

      if (mounted) {
        setState(() {
          _profile = results[0] as Map<String, dynamic>?;
          _subscription = results[1] as Map<String, dynamic>?;
          _totalScans = (results[2] as int?) ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _signOut(AppStrings s) async {
    final confirmed = await _showConfirmDialog(
      title: s.signOut,
      message: s.signOutConfirm,
      confirmLabel: s.signOut,
      confirmColor: AppTheme.error,
    );
    if (confirmed == true && mounted) {
      analytics.track(HastVedaEvents.logout);
      analytics.reset();
      NotificationPreferencesService.instance.reset();
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go(AppRoutes.login);
    }
  }

  Future<void> _deleteAccount(AppStrings s) async {
    final confirmed = await _showConfirmDialog(
      title: s.deleteAccount,
      message: s.deleteAccountWarning,
      confirmLabel: s.deleteAccount,
      confirmColor: AppTheme.error,
      isDangerous: true,
    );
    if (confirmed != true || !mounted) return;

    // Second confirmation for destructive action
    final doubleConfirmed = await _showConfirmDialog(
      title: s.deleteAccountFinal,
      message: s.deleteAccountFinalWarning,
      confirmLabel: s.deleteAccountConfirm,
      confirmColor: AppTheme.error,
      isDangerous: true,
    );
    if (doubleConfirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Soft-delete: deactivate profile (RLS prevents accessing other users' data)
      await SupabaseService.instance.client
          .from('user_profiles')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      analytics.track('account_deleted');
      analytics.reset();
      NotificationPreferencesService.instance.reset();
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go(AppRoutes.login);
    } catch (e) {
      debugPrint('Delete account error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.somethingWentWrong)));
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    bool isDangerous = false,
  }) {
    final isDark = context.read<ThemeProvider>().isDark;
    final bg = isDark ? const Color(0xFF1A1A26) : Colors.white;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: isDangerous ? AppTheme.error : textPri,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.outfit(color: textSec, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: GoogleFonts.outfit(
                color: confirmColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials() {
    final name = _profile?['full_name'] as String? ?? _email ?? 'U';
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final dt = DateTime.parse(isoDate);
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
      return '${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = themeProvider.isDark;

    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final primaryColor = isDark ? AppTheme.gold : AppTheme.deepPurple;
    final cardBg = isDark ? AppTheme.surfaceElevated : AppTheme.surfaceLight;
    final cardBorder = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final divider = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    final name =
        _profile?['full_name'] as String? ?? _email?.split('@').first ?? 'User';
    final tier = _profile?['tier'] as String? ?? 'free';
    final isPremium =
        tier == 'premium' || context.watch<EntitlementNotifier>().isPremium;
    final memberSince = _formatDate(_profile?['created_at'] as String?);
    final langPref = _profile?['language_preference'] as String? ?? 'en';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          s.myProfile,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: textSec),
            tooltip: s.settings,
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : _hasError
          ? HastVedaInlineError(
              title: s.somethingWentWrong,
              message: s.troubleConnecting,
              onRetry: _loadProfile,
            )
          : RefreshIndicator(
              color: primaryColor,
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // ── Avatar & Name ─────────────────────────────────────
                    _buildAvatarSection(
                      isDark: isDark,
                      name: name,
                      isPremium: isPremium,
                      primaryColor: primaryColor,
                      textPri: textPri,
                      textSec: textSec,
                      s: s,
                    ),
                    const SizedBox(height: 24),

                    // ── Stats Row ─────────────────────────────────────────
                    _buildStatsRow(
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      textPri: textPri,
                      textSec: textSec,
                      primaryColor: primaryColor,
                      memberSince: memberSince,
                      totalScans: _totalScans,
                      s: s,
                    ),
                    const SizedBox(height: 20),

                    // ── Profile Info Card ─────────────────────────────────
                    _buildInfoCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      divider: divider,
                      textPri: textPri,
                      textSec: textSec,
                      primaryColor: primaryColor,
                      name: name,
                      email: _email ?? '—',
                      langPref: langPref,
                      isPremium: isPremium,
                      s: s,
                    ),
                    const SizedBox(height: 20),

                    // ── Subscription Card ─────────────────────────────────
                    _buildSubscriptionCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      textPri: textPri,
                      textSec: textSec,
                      primaryColor: primaryColor,
                      isPremium: isPremium,
                      subscription: _subscription,
                      s: s,
                    ),
                    const SizedBox(height: 20),

                    // ── My Readings ───────────────────────────────────────
                    _buildMenuSection(
                      title: s.myReadings,
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      divider: divider,
                      textPri: textPri,
                      primaryColor: primaryColor,
                      items: [
                        _MenuItem(
                          icon: Icons.history_rounded,
                          label: s.readingHistory,
                          onTap: () => context.push(AppRoutes.reportHistory),
                        ),
                        _MenuItem(
                          icon: Icons.description_outlined,
                          label: s.detailedReport,
                          onTap: () => context.push(AppRoutes.detailedReport),
                        ),
                        _MenuItem(
                          icon: Icons.favorite_border_rounded,
                          label: s.coupleReading,
                          onTap: () =>
                              context.push(AppRoutes.coupleReadingHistory),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Account ───────────────────────────────────────────
                    _buildMenuSection(
                      title: s.account,
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      divider: divider,
                      textPri: textPri,
                      primaryColor: primaryColor,
                      items: [
                        _MenuItem(
                          icon: Icons.edit_outlined,
                          label: s.editProfile,
                          onTap: () => _showEditProfileSheet(
                            s,
                            isDark,
                            textPri,
                            textSec,
                            primaryColor,
                          ),
                        ),
                        _MenuItem(
                          icon: Icons.lock_outline_rounded,
                          label: s.changePassword,
                          onTap: () => _showChangePasswordSheet(
                            s,
                            isDark,
                            textPri,
                            textSec,
                            primaryColor,
                          ),
                        ),
                        _MenuItem(
                          icon: Icons.notifications_outlined,
                          label: s.notifications,
                          onTap: () => context.push(AppRoutes.settings),
                        ),
                        _MenuItem(
                          icon: Icons.language_rounded,
                          label: s.language,
                          onTap: () =>
                              context.push(AppRoutes.languageSelection),
                        ),
                        _MenuItem(
                          icon: Icons.settings_outlined,
                          label: s.settings,
                          onTap: () => context.push(AppRoutes.settings),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Support ───────────────────────────────────────────
                    _buildMenuSection(
                      title: s.helpSupport,
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      divider: divider,
                      textPri: textPri,
                      primaryColor: primaryColor,
                      items: [
                        _MenuItem(
                          icon: Icons.info_outline_rounded,
                          label: s.aboutHastVeda,
                          onTap: () => context.push(AppRoutes.helpAbout),
                        ),
                        _MenuItem(
                          icon: Icons.privacy_tip_outlined,
                          label: s.privacyPolicy,
                          onTap: () => context.push(AppRoutes.privacyPolicy),
                        ),
                        _MenuItem(
                          icon: Icons.article_outlined,
                          label: s.termsConditions,
                          onTap: () => context.push(AppRoutes.termsConditions),
                        ),
                        _MenuItem(
                          icon: Icons.auto_awesome_outlined,
                          label: s.aiDisclaimer,
                          onTap: () => context.push(AppRoutes.aiDisclaimer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Sign Out ──────────────────────────────────────────
                    if (Supabase.instance.client.auth.currentUser != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _signOut(s),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: Text(
                            s.signOut,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: BorderSide(
                              color: AppTheme.error.withAlpha(80),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => _deleteAccount(s),
                        child: Text(
                          s.deleteAccount,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: AppTheme.error.withAlpha(160),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAvatarSection({
    required bool isDark,
    required String name,
    required bool isPremium,
    required Color primaryColor,
    required Color textPri,
    required Color textSec,
    required AppStrings s,
  }) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isDark
                    ? AppTheme.goldGradient
                    : AppTheme.purpleGradientLight,
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withAlpha(60),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _getInitials(),
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (isPremium)
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? AppTheme.backgroundDark
                        : AppTheme.backgroundLight,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          name,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        if (_email != null) ...[
          const SizedBox(height: 4),
          Text(
            _email!,
            style: GoogleFonts.outfit(fontSize: 13, color: textSec),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isPremium
                ? (isDark ? AppTheme.goldMuted : AppTheme.goldMutedLight)
                : (isDark
                      ? AppTheme.surfaceElevated
                      : AppTheme.surfaceElevatedLight),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isPremium
                  ? primaryColor.withAlpha(80)
                  : (isDark ? AppTheme.outlineDark : AppTheme.outlineLight),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPremium ? Icons.star_rounded : Icons.person_outline_rounded,
                size: 14,
                color: isPremium ? AppTheme.gold : textSec,
              ),
              const SizedBox(width: 6),
              Text(
                isPremium ? s.premiumMember : s.freePlan,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPremium ? AppTheme.gold : textSec,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow({
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textPri,
    required Color textSec,
    required Color primaryColor,
    required String memberSince,
    required int totalScans,
    required AppStrings s,
  }) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: s.memberSince,
            value: memberSince,
            icon: Icons.calendar_today_outlined,
            isDark: isDark,
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPri: textPri,
            textSec: textSec,
            primaryColor: primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: s.totalScans,
            value: totalScans.toString(),
            icon: Icons.back_hand_outlined,
            isDark: isDark,
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPri: textPri,
            textSec: textSec,
            primaryColor: primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color divider,
    required Color textPri,
    required Color textSec,
    required Color primaryColor,
    required String name,
    required String email,
    required String langPref,
    required bool isPremium,
    required AppStrings s,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          _InfoRow(
            label: s.fullName,
            value: name,
            icon: Icons.person_outline_rounded,
            primaryColor: primaryColor,
            textPri: textPri,
            textSec: textSec,
          ),
          Divider(height: 1, color: divider, indent: 50),
          _InfoRow(
            label: s.email,
            value: email,
            icon: Icons.email_outlined,
            primaryColor: primaryColor,
            textPri: textPri,
            textSec: textSec,
          ),
          Divider(height: 1, color: divider, indent: 50),
          _InfoRow(
            label: s.language,
            value: langPref == 'hi' ? 'हिंदी 🇮🇳' : 'English 🇬🇧',
            icon: Icons.language_rounded,
            primaryColor: primaryColor,
            textPri: textPri,
            textSec: textSec,
          ),
          Divider(height: 1, color: divider, indent: 50),
          _InfoRow(
            label: s.accountType,
            value: isPremium ? s.premiumMember : s.freePlan,
            icon: isPremium ? Icons.star_rounded : Icons.person_outline_rounded,
            primaryColor: primaryColor,
            textPri: textPri,
            textSec: textSec,
            valueColor: isPremium ? AppTheme.gold : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard({
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textPri,
    required Color textSec,
    required Color primaryColor,
    required bool isPremium,
    required Map<String, dynamic>? subscription,
    required AppStrings s,
  }) {
    final expiresAt = subscription?['expires_at'] as String?;
    final status = subscription?['status'] as String?;
    final autoRenewing = subscription?['auto_renewing'] as bool? ?? false;

    return Container(
      decoration: BoxDecoration(
        color: isPremium
            ? (isDark ? AppTheme.goldMuted : AppTheme.goldMutedLight)
            : cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPremium ? AppTheme.gold.withAlpha(60) : cardBorder,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.star_border_rounded,
                color: isPremium ? AppTheme.gold : textSec,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                s.subscription,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSec,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isPremium ? s.premiumMember : s.freePlan,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isPremium ? AppTheme.gold : textPri,
            ),
          ),
          if (isPremium && status != null) ...[
            const SizedBox(height: 6),
            Text(
              '${s.subscriptionStatus}: ${_capitalise(status)}',
              style: GoogleFonts.outfit(fontSize: 13, color: textSec),
            ),
          ],
          if (isPremium && expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '${s.renewalDate}: ${_formatDate(expiresAt)}',
              style: GoogleFonts.outfit(fontSize: 13, color: textSec),
            ),
            if (autoRenewing) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.autorenew_rounded,
                    size: 14,
                    color: AppTheme.success,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    s.autoRenewOn,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (!isPremium) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.premiumPaywall),
                icon: const Icon(Icons.star_rounded, size: 16),
                label: Text(
                  s.upgradeToPremium,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppTheme.gold : AppTheme.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuSection({
    required String title,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color divider,
    required Color textPri,
    required Color primaryColor,
    required List<_MenuItem> items,
  }) {
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final chevron = isDark ? const Color(0xFF5A5870) : AppTheme.textMutedLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textSec,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cardBorder),
          ),
          child: Column(
            children: List.generate(items.length, (i) {
              final item = items[i];
              return Column(
                children: [
                  InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, color: primaryColor, size: 20),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              item.label,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPri,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: chevron,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (i < items.length - 1)
                    Divider(height: 1, color: divider, indent: 50),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  void _showEditProfileSheet(
    AppStrings s,
    bool isDark,
    Color textPri,
    Color textSec,
    Color primaryColor,
  ) {
    final nameCtrl = TextEditingController(
      text: _profile?['full_name'] as String? ?? '',
    );
    final bg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final fieldBg = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s.editProfile,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s.fullName,
                    style: GoogleFonts.outfit(fontSize: 13, color: textSec),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.outfit(color: textPri),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: fieldBg,
                      hintText: s.enterName,
                      hintStyle: GoogleFonts.outfit(color: textSec),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              setSheetState(() => saving = true);
                              try {
                                final userId = Supabase
                                    .instance
                                    .client
                                    .auth
                                    .currentUser
                                    ?.id;
                                if (userId != null) {
                                  await SupabaseService.instance.client
                                      .from('user_profiles')
                                      .update({
                                        'full_name': nameCtrl.text.trim(),
                                        'updated_at': DateTime.now()
                                            .toIso8601String(),
                                      })
                                      .eq('id', userId);
                                  if (mounted) {
                                    setState(() {
                                      _profile = {
                                        ...?_profile,
                                        'full_name': nameCtrl.text.trim(),
                                      };
                                    });
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(s.profileSaved),
                                        backgroundColor: AppTheme.success,
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                setSheetState(() => saving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(s.somethingWentWrong),
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              s.save,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showChangePasswordSheet(
    AppStrings s,
    bool isDark,
    Color textPri,
    Color textSec,
    Color primaryColor,
  ) {
    final emailCtrl = TextEditingController(text: _email ?? '');
    final bg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final fieldBg = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool sending = false;
        bool sent = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s.changePassword,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.changePasswordDesc,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: textSec,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (sent)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.successContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.success.withAlpha(60),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            color: AppTheme.success,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.passwordResetSent,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TextField(
                      controller: emailCtrl,
                      readOnly: true,
                      style: GoogleFonts.outfit(color: textSec),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: fieldBg,
                        hintText: s.email,
                        hintStyle: GoogleFonts.outfit(color: textSec),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: sending
                            ? null
                            : () async {
                                setSheetState(() => sending = true);
                                try {
                                  await Supabase.instance.client.auth
                                      .resetPasswordForEmail(
                                        emailCtrl.text.trim(),
                                      );
                                  setSheetState(() {
                                    sending = false;
                                    sent = true;
                                  });
                                } catch (e) {
                                  setSheetState(() => sending = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(s.somethingWentWrong),
                                      ),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                s.sendResetLink,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Stat Card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDark;
  final Color cardBg;
  final Color cardBorder;
  final Color textPri;
  final Color textSec;
  final Color primaryColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    required this.cardBg,
    required this.cardBorder,
    required this.textPri,
    required this.textSec,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: primaryColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: primaryColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPri,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: GoogleFonts.outfit(fontSize: 11, color: textSec),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info Row ──────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color primaryColor;
  final Color textPri;
  final Color textSec;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.primaryColor,
    required this.textPri,
    required this.textSec,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(fontSize: 11, color: textSec),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? textPri,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Menu Item ─────────────────────────────────────────────────────────────────
class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
