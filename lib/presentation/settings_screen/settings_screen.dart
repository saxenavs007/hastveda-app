import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../services/app_strings.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/locale_provider.dart';
import '../../services/in_app_review_service.dart';
import '../../services/theme_provider.dart';
import '../../services/notification_preferences_service.dart';
import '../../services/analytics_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAdminUser() {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;
      final meta = user.userMetadata ?? {};
      final appMeta = user.appMetadata ?? {};
      return meta['role'] == 'admin' || appMeta['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationPreferencesService.instance.load();
    });
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
    final sectionHeaderColor = isDark
        ? const Color(0xFF8B7355)
        : AppTheme.textSecondaryLight;
    final dividerColor = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          s.settings,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Appearance ────────────────────────────────────────────────
            _SettingsSection(
              title: s.appearance,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              children: [
                _ThemeSelector(
                  s: s,
                  isDark: isDark,
                  themeProvider: themeProvider,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Language ──────────────────────────────────────────────────
            _SettingsSection(
              title: s.language,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              children: [
                _SettingsTile(
                  icon: Icons.language_rounded,
                  label: s.language,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localeProvider.isHinglish
                            ? '🇮🇳'
                            : localeProvider.isHindi
                            ? '🇮🇳'
                            : '🇬🇧',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        localeProvider.isHinglish
                            ? 'Hinglish'
                            : localeProvider.isHindi
                            ? 'हिंदी'
                            : 'English',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => context.push(AppRoutes.languageSelection),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Notifications ─────────────────────────────────────────────
            _NotificationSection(
              s: s,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              textPri: textPri,
              textSec: textSec,
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 16),

            // ── Subscription ──────────────────────────────────────────────
            _SettingsSection(
              title: s.subscription,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              children: [
                _SettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  label: s.premium,
                  trailing: _PremiumBadge(
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                  onTap: () => context.push(AppRoutes.premiumPaywall),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Account ───────────────────────────────────────────────────
            _SettingsSection(
              title: s.account,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              children: [
                _SettingsTile(
                  icon: Icons.edit_outlined,
                  label: s.editProfile,
                  onTap: () => context.push(AppRoutes.profile),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  label: s.changePassword,
                  onTap: () => context.push(AppRoutes.profile),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  label: s.signOut,
                  labelColor: AppTheme.error,
                  onTap: () async {
                    final confirmed = await _showConfirmDialog(
                      context: context,
                      title: s.signOut,
                      message: s.signOutConfirm,
                      confirmLabel: s.signOut,
                      confirmColor: AppTheme.error,
                      isDark: isDark,
                    );
                    if (confirmed == true && context.mounted) {
                      analytics.track(HastVedaEvents.logout);
                      analytics.reset();
                      NotificationPreferencesService.instance.reset();
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) context.go(AppRoutes.login);
                    }
                  },
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Privacy & Legal ───────────────────────────────────────────
            _SettingsSection(
              title: s.privacyLegal,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              children: [
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  label: s.privacyPolicy,
                  onTap: () => context.push(AppRoutes.privacyPolicy),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                _SettingsTile(
                  icon: Icons.article_outlined,
                  label: s.termsConditions,
                  onTap: () => context.push(AppRoutes.termsConditions),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                _SettingsTile(
                  icon: Icons.auto_awesome_outlined,
                  label: s.aiDisclaimer,
                  onTap: () => context.push(AppRoutes.aiDisclaimer),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── About ─────────────────────────────────────────────────────
            _SettingsSection(
              title: s.about,
              isDark: isDark,
              sectionHeaderColor: sectionHeaderColor,
              dividerColor: dividerColor,
              children: [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  label: s.aboutHastVeda,
                  onTap: () => context.push(AppRoutes.helpAbout),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  label: s.helpSupport,
                  onTap: () => context.push(AppRoutes.helpAbout),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                _SettingsTile(
                  icon: Icons.star_rate_rounded,
                  label: 'Rate HastVeda on Google Play',
                  onTap: () => InAppReviewService.instance.openStoreListing(),
                  isDark: isDark,
                  textPri: textPri,
                  primaryColor: primaryColor,
                ),
                // Admin-only: Discount Code Dashboard
                if (_isAdminUser())
                  _SettingsTile(
                    icon: Icons.discount_outlined,
                    label: 'Admin: Discount Codes',
                    onTap: () => context.push(AppRoutes.adminDiscountDashboard),
                    isDark: isDark,
                    textPri: textPri,
                    primaryColor: primaryColor,
                  ),
                if (_isAdminUser())
                  _SettingsTile(
                    icon: Icons.star_rounded,
                    label: 'Admin: Reviews Dashboard',
                    onTap: () => context.push(AppRoutes.adminReviewsDashboard),
                    isDark: isDark,
                    textPri: textPri,
                    primaryColor: primaryColor,
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ── App Info Footer ───────────────────────────────────────────
            _AppInfoFooter(isDark: isDark, s: s),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Theme Selector ────────────────────────────────────────────────────────────
class _ThemeSelector extends StatelessWidget {
  final AppStrings s;
  final bool isDark;
  final ThemeProvider themeProvider;
  final Color textPri;
  final Color primaryColor;

  const _ThemeSelector({
    required this.s,
    required this.isDark,
    required this.themeProvider,
    required this.textPri,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      _ThemeOption(
        mode: ThemeMode.light,
        label: s.lightMode,
        icon: Icons.light_mode_rounded,
      ),
      _ThemeOption(
        mode: ThemeMode.dark,
        label: s.darkMode,
        icon: Icons.dark_mode_rounded,
      ),
      _ThemeOption(
        mode: ThemeMode.system,
        label: s.systemDefault,
        icon: Icons.brightness_auto_rounded,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: primaryColor,
                size: 20,
              ),
              const SizedBox(width: 14),
              Text(
                s.theme,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textPri,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: options.map((opt) {
              final isSelected = themeProvider.themeMode == opt.mode;
              final selectedBg = isDark
                  ? AppTheme.goldMuted
                  : AppTheme.purpleMutedLight;
              final selectedText = isDark ? AppTheme.gold : AppTheme.deepPurple;
              final unselectedText = isDark
                  ? AppTheme.textMuted
                  : AppTheme.textMutedLight;
              final cardBorder = isDark
                  ? AppTheme.outlineDark
                  : AppTheme.outlineLight;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    themeProvider.setTheme(opt.mode);
                    analytics.track(
                      HastVedaEvents.themeChanged,
                      properties: {'theme': opt.mode.name},
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? (isDark ? AppTheme.gold : AppTheme.deepPurple)
                                  .withAlpha(80)
                            : cardBorder,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          opt.icon,
                          size: 18,
                          color: isSelected ? selectedText : unselectedText,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          opt.label,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected ? selectedText : unselectedText,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption {
  final ThemeMode mode;
  final String label;
  final IconData icon;
  const _ThemeOption({
    required this.mode,
    required this.label,
    required this.icon,
  });
}

// ── Notification Section ──────────────────────────────────────────────────────
class _NotificationSection extends StatelessWidget {
  final AppStrings s;
  final bool isDark;
  final Color sectionHeaderColor;
  final Color dividerColor;
  final Color textPri;
  final Color textSec;
  final Color primaryColor;

  const _NotificationSection({
    required this.s,
    required this.isDark,
    required this.sectionHeaderColor,
    required this.dividerColor,
    required this.textPri,
    required this.textSec,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationPreferencesService.instance,
      builder: (context, _) {
        final svc = NotificationPreferencesService.instance;
        final prefs = svc.preferences;

        return _SettingsSection(
          title: s.notifications,
          isDark: isDark,
          sectionHeaderColor: sectionHeaderColor,
          dividerColor: dividerColor,
          children: [
            // FCM note
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: textSec),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.fcmStatusDisabled,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: textSec,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor, indent: 16),
            // Master push toggle
            _SettingsToggle(
              icon: Icons.notifications_outlined,
              label: s.pushNotifications,
              subtitle: s.notificationSettingsDesc,
              value: prefs.pushEnabled,
              onChanged: (v) async {
                await svc.togglePush(v);
                analytics.track(
                  v
                      ? HastVedaEvents.notificationsEnabled
                      : HastVedaEvents.notificationsDisabled,
                  properties: {'category': 'push_master'},
                );
              },
              isDark: isDark,
              textPri: textPri,
              primaryColor: primaryColor,
            ),
            if (prefs.pushEnabled) ...[
              Divider(height: 1, color: dividerColor, indent: 50),
              _SettingsToggle(
                icon: Icons.wb_sunny_outlined,
                label: s.notifCategoryDailyPrediction,
                subtitle: s.notifCategoryDailyPredictionDesc,
                value: prefs.dailyPrediction,
                onChanged: (v) async {
                  await svc.toggleDailyPrediction(v);
                },
                isDark: isDark,
                textPri: textPri,
                primaryColor: primaryColor,
                indent: true,
              ),
              Divider(height: 1, color: dividerColor, indent: 50),
              _SettingsToggle(
                icon: Icons.auto_awesome_outlined,
                label: s.notifCategoryReadingReady,
                subtitle: s.notifCategoryReadingReadyDesc,
                value: prefs.readingReady,
                onChanged: (v) async {
                  await svc.toggleReadingReady(v);
                },
                isDark: isDark,
                textPri: textPri,
                primaryColor: primaryColor,
                indent: true,
              ),
              Divider(height: 1, color: dividerColor, indent: 50),
              _SettingsToggle(
                icon: Icons.description_outlined,
                label: s.notifCategoryReportReady,
                subtitle: s.notifCategoryReportReadyDesc,
                value: prefs.reportReady,
                onChanged: (v) async {
                  await svc.toggleReportReady(v);
                },
                isDark: isDark,
                textPri: textPri,
                primaryColor: primaryColor,
                indent: true,
              ),
              Divider(height: 1, color: dividerColor, indent: 50),
              _SettingsToggle(
                icon: Icons.star_outline_rounded,
                label: s.notifCategoryPremiumUpdates,
                subtitle: s.notifCategoryPremiumUpdatesDesc,
                value: prefs.premiumUpdates,
                onChanged: (v) async {
                  await svc.togglePremiumUpdates(v);
                },
                isDark: isDark,
                textPri: textPri,
                primaryColor: primaryColor,
                indent: true,
              ),
              Divider(height: 1, color: dividerColor, indent: 50),
              _SettingsToggle(
                icon: Icons.shield_outlined,
                label: s.notifCategoryImportantAccount,
                subtitle: s.notifCategoryImportantAccountDesc,
                value: prefs.importantAccount,
                onChanged: (v) async {
                  await svc.toggleImportantAccount(v);
                },
                isDark: isDark,
                textPri: textPri,
                primaryColor: primaryColor,
                indent: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Premium Badge ─────────────────────────────────────────────────────────────
class _PremiumBadge extends StatelessWidget {
  final bool isDark;
  final Color primaryColor;

  const _PremiumBadge({required this.isDark, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    if (context.watch<EntitlementNotifier>().isPremium) {
      return _tierBadge(isDark: isDark, isPremium: true);
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('user_profiles')
          .select('tier')
          .eq('id', user.id)
          .maybeSingle(),
      builder: (context, snapshot) {
        final tier = snapshot.data?['tier'] as String? ?? 'free';
        return _tierBadge(isDark: isDark, isPremium: tier == 'premium');
      },
    );
  }

  Widget _tierBadge({required bool isDark, required bool isPremium}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPremium
            ? (isDark ? AppTheme.goldMuted : AppTheme.goldMutedLight)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isPremium
              ? AppTheme.gold.withAlpha(80)
              : (isDark ? AppTheme.outlineDark : AppTheme.outlineLight),
        ),
      ),
      child: Text(
        isPremium ? '✨ Premium' : 'Free',
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isPremium
              ? AppTheme.gold
              : (isDark ? AppTheme.textMuted : AppTheme.textMutedLight),
        ),
      ),
    );
  }
}

// ── App Info Footer ───────────────────────────────────────────────────────────
class _AppInfoFooter extends StatelessWidget {
  final bool isDark;
  final AppStrings s;

  const _AppInfoFooter({required this.isDark, required this.s});

  @override
  Widget build(BuildContext context) {
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;
    final primaryColor = isDark ? AppTheme.gold : AppTheme.deepPurple;

    return Column(
      children: [
        // Logo
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isDark
                ? AppTheme.goldGradient
                : AppTheme.purpleGradientLight,
          ),
          child: Center(
            child: Text(
              'H',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'HastVeda',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${s.version} 1.0.0',
          style: GoogleFonts.outfit(fontSize: 12, color: textSec),
        ),
        const SizedBox(height: 4),
        Text(
          s.ancientWisdom,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: textMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ── Settings section ──────────────────────────────────────────────────────────
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isDark;
  final Color sectionHeaderColor;
  final Color dividerColor;

  const _SettingsSection({
    required this.title,
    required this.children,
    required this.isDark,
    required this.sectionHeaderColor,
    required this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppTheme.surfaceElevated : AppTheme.surfaceLight;
    final cardBorder = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

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
              color: sectionHeaderColor,
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
            children: List.generate(children.length, (i) {
              return Column(
                children: [
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, color: dividerColor, indent: 50),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── Settings tile ─────────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDark;
  final Color textPri;
  final Color primaryColor;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.labelColor,
    this.trailing,
    this.onTap,
    required this.isDark,
    required this.textPri,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final chevronColor = isDark
        ? const Color(0xFF5A5870)
        : AppTheme.textMutedLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: labelColor ?? primaryColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: labelColor ?? textPri,
                ),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: chevronColor,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }
}

// ── Settings toggle ───────────────────────────────────────────────────────────
class _SettingsToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final Color textPri;
  final Color primaryColor;
  final bool indent;

  const _SettingsToggle({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
    required this.textPri,
    required this.primaryColor,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    return Padding(
      padding: EdgeInsets.only(
        left: indent ? 28 : 16,
        right: 16,
        top: 10,
        bottom: 10,
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: indent ? 18 : 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: indent ? 13 : 14,
                    fontWeight: FontWeight.w500,
                    color: textPri,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.outfit(fontSize: 11, color: textSec),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: isDark ? AppTheme.gold : AppTheme.deepPurple,
          ),
        ],
      ),
    );
  }
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────
Future<bool?> _showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
  required bool isDark,
}) {
  final bg = isDark ? const Color(0xFF1A1A26) : Colors.white;
  final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
  final textSec = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          color: textPri,
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
