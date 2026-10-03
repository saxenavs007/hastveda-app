import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/app_strings.dart';
import '../../services/connectivity_service.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/entitlement_service.dart';
import '../../services/fcm_service.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  /// Where to send the user once they are signed in. Set when the router
  /// bounced them here from a screen that requires an account (palm scan).
  /// Falls back to the home screen for a normal sign-in.
  final String? redirectTo;

  const LoginScreen({super.key, this.redirectTo});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signIn(AppStrings s) async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _errorMessage = s.enterEmailAndPassword);
      return;
    }
    final connectivity = ConnectivityService.instance;
    if (connectivity.isOffline) {
      setState(() => _errorMessage = s.offlineAuthError);
      return;
    }
    analytics.track(HastVedaEvents.signInStarted);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      analytics.track(HastVedaEvents.signInSuccess);
      // Invalidate entitlement cache so the next screen always fetches fresh
      // Premium state from the server (critical after a payment was made).
      EntitlementService.instance.invalidateCache();
      // Identify user in analytics
      final userId = response.user?.id;
      if (userId != null) {
        analytics.identify(userId: userId);
        // Capture FCM token after sign-in
        FCMService.instance.captureToken().then((token) {
          if (token != null) FCMService.instance.persistToken(token);
        });
      }
      if (mounted) context.go(widget.redirectTo ?? AppRoutes.homeScreen);
    } on AuthException catch (e) {
      analytics.track(
        HastVedaEvents.signInFailed,
        properties: {'reason': 'auth_exception'},
      );
      setState(() => _errorMessage = e.message);
    } catch (_) {
      final isOffline = ConnectivityService.instance.isOffline;
      analytics.track(
        HastVedaEvents.signInFailed,
        properties: {'reason': isOffline ? 'offline' : 'unknown'},
      );
      setState(
        () => _errorMessage = isOffline ? s.offlineAuthError : s.signInFailed,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp(AppStrings s) async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _errorMessage = s.fillAllFields);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = s.passwordsDoNotMatch);
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _errorMessage = s.passwordTooShort);
      return;
    }
    final connectivity = ConnectivityService.instance;
    if (connectivity.isOffline) {
      setState(() => _errorMessage = s.offlineAuthError);
      return;
    }
    analytics.track(HastVedaEvents.signUpStarted);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {'full_name': _nameController.text.trim()},
      );
      analytics.track(HastVedaEvents.signUpSuccess);
      final userId = response.user?.id;
      if (userId != null) {
        analytics.identify(userId: userId);
        FCMService.instance.captureToken().then((token) {
          if (token != null) FCMService.instance.persistToken(token);
        });
      }
      // With email confirmation enabled, signUp returns a user but no session.
      // Sending them to a screen that requires an account would bounce them
      // straight back here, so only honour redirectTo once a session exists.
      final signedIn = response.session != null;
      if (mounted) {
        context.go(
          signedIn
              ? (widget.redirectTo ?? AppRoutes.homeScreen)
              : AppRoutes.homeScreen,
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      final isOffline = ConnectivityService.instance.isOffline;
      setState(
        () => _errorMessage = isOffline ? s.offlineAuthError : s.signUpFailed,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final outline = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final textMut = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;
    final primaryColor = isDark ? AppTheme.gold : AppTheme.confetti;

    return Scaffold(
      backgroundColor: bg,
      // resizeToAvoidBottomInset ensures keyboard doesn't cover inputs
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Top row: language + theme toggles
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Language toggle
                  GestureDetector(
                    onTap: () async {
                      final newLang = localeProvider.isHindi ? 'en' : 'hi';
                      await localeProvider.setLocale(newLang);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceEl,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: outline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            localeProvider.isHindi ? '🇮🇳' : '🇬🇧',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            localeProvider.isHindi ? 'हिंदी' : 'EN',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Theme toggle
                  GestureDetector(
                    onTap: () => themeProvider.toggleTheme(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceEl,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: outline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            size: 16,
                            color: isDark ? AppTheme.gold : AppTheme.confetti,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isDark ? s.darkMode : s.lightMode,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? AppTheme.gold : AppTheme.confetti)
                          .withAlpha(80),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/hastveda_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.goldGradient.createShader(bounds),
                child: Text(
                  s.appName,
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.tagline,
                style: GoogleFonts.outfit(fontSize: 13, color: textSec),
              ),
              // Shown when the router sent the user here from a screen that
              // requires an account, so the reason is obvious rather than the
              // sign-in page appearing out of nowhere.
              if (widget.redirectTo != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primaryColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withAlpha(80)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.accountRequiredTitle,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.accountRequiredForScan,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                height: 1.45,
                                color: textSec,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              // Tab bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: surfaceEl,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: outline),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: isDark
                        ? AppTheme.goldGradient
                        : AppTheme.purpleGradientLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: isDark ? const Color(0xFF0A0A0F) : Colors.white,
                  unselectedLabelColor: textSec,
                  labelStyle: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [
                    Tab(text: s.signIn),
                    Tab(text: s.signUp),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Error message
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withAlpha(80)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: const Color(0xFFFF8080),
                    ),
                  ),
                ),
              // Forms
              SizedBox(
                height: 340,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _LoginForm(
                      emailController: _emailController,
                      passwordController: _passwordController,
                      obscurePassword: _obscurePassword,
                      onTogglePassword: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onSubmit: () => _signIn(s),
                      isLoading: _isLoading,
                      isDark: isDark,
                      surfaceEl: surfaceEl,
                      outline: outline,
                      textPri: textPri,
                      textSec: textSec,
                      textMut: textMut,
                      primaryColor: primaryColor,
                      buttonLabel: s.signIn,
                      emailLabel: s.email,
                      emailHint: s.enterEmail,
                      passwordLabel: s.password,
                      passwordHint: s.enterPassword,
                    ),
                    _SignUpFormWidget(
                      nameController: _nameController,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      confirmPasswordController: _confirmPasswordController,
                      obscurePassword: _obscurePassword,
                      obscureConfirm: _obscureConfirm,
                      onTogglePassword: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onToggleConfirm: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      onSubmit: () => _signUp(s),
                      isLoading: _isLoading,
                      isDark: isDark,
                      surfaceEl: surfaceEl,
                      outline: outline,
                      textPri: textPri,
                      textSec: textSec,
                      textMut: textMut,
                      primaryColor: primaryColor,
                      buttonLabel: s.createAccount,
                      nameLabel: s.fullName,
                      nameHint: s.enterName,
                      emailLabel: s.email,
                      emailHint: s.enterEmail,
                      passwordLabel: s.password,
                      passwordHint: s.enterPassword,
                      confirmLabel: s.confirmPassword,
                      confirmHint: s.enterConfirmPassword,
                    ),
                  ],
                ),
              ),
              // Guest access was removed deliberately. Palm scanning stores
              // biometric data against a user account and draws on that
              // account's monthly free-scan quota, neither of which can be
              // done for an anonymous visitor.
              const SizedBox(height: 24),
              Text(
                'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: textMut,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable themed text field ────────────────────────────────────────────────
class _ThemedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final TextInputType keyboardType;
  final IconData prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final Color surfaceEl;
  final Color outline;
  final Color textPri;
  final Color textSec;
  final Color textMut;
  final bool isDark;

  const _ThemedTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    required this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    required this.surfaceEl,
    required this.outline,
    required this.textPri,
    required this.textSec,
    required this.textMut,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final focusBorder = isDark ? AppTheme.gold : AppTheme.confetti;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.outfit(fontSize: 14, color: textPri),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.outfit(fontSize: 13, color: textSec),
        hintStyle: GoogleFonts.outfit(fontSize: 13, color: textMut),
        filled: true,
        fillColor: surfaceEl,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusBorder, width: 1.5),
        ),
        prefixIcon: Icon(prefixIcon, color: textMut, size: 20),
        suffixIcon: suffixIcon != null
            ? GestureDetector(
                onTap: onSuffixTap,
                child: Icon(suffixIcon, color: textMut, size: 20),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ── Sign In form ──────────────────────────────────────────────────────────────
class _LoginForm extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final bool isLoading;
  final bool isDark;
  final Color surfaceEl, outline, textPri, textSec, textMut, primaryColor;
  final String buttonLabel, emailLabel, emailHint, passwordLabel, passwordHint;

  const _LoginForm({
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.isLoading,
    required this.isDark,
    required this.surfaceEl,
    required this.outline,
    required this.textPri,
    required this.textSec,
    required this.textMut,
    required this.primaryColor,
    required this.buttonLabel,
    required this.emailLabel,
    required this.emailHint,
    required this.passwordLabel,
    required this.passwordHint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ThemedTextField(
          controller: emailController,
          label: emailLabel,
          hint: emailHint,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.email_outlined,
          surfaceEl: surfaceEl,
          outline: outline,
          textPri: textPri,
          textSec: textSec,
          textMut: textMut,
          isDark: isDark,
        ),
        const SizedBox(height: 14),
        _ThemedTextField(
          controller: passwordController,
          label: passwordLabel,
          hint: passwordHint,
          obscureText: obscurePassword,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          onSuffixTap: onTogglePassword,
          surfaceEl: surfaceEl,
          outline: outline,
          textPri: textPri,
          textSec: textSec,
          textMut: textMut,
          isDark: isDark,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppTheme.goldGradient
                  : AppTheme.purpleGradientLight,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withAlpha(60),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Sign Up form ──────────────────────────────────────────────────────────────
class _SignUpFormWidget extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;
  final bool isLoading;
  final bool isDark;
  final Color surfaceEl, outline, textPri, textSec, textMut, primaryColor;
  final String buttonLabel, nameLabel, nameHint, emailLabel, emailHint;
  final String passwordLabel, passwordHint, confirmLabel, confirmHint;

  const _SignUpFormWidget({
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
    required this.isLoading,
    required this.isDark,
    required this.surfaceEl,
    required this.outline,
    required this.textPri,
    required this.textSec,
    required this.textMut,
    required this.primaryColor,
    required this.buttonLabel,
    required this.nameLabel,
    required this.nameHint,
    required this.emailLabel,
    required this.emailHint,
    required this.passwordLabel,
    required this.passwordHint,
    required this.confirmLabel,
    required this.confirmHint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ThemedTextField(
          controller: nameController,
          label: nameLabel,
          hint: nameHint,
          prefixIcon: Icons.person_outline_rounded,
          surfaceEl: surfaceEl,
          outline: outline,
          textPri: textPri,
          textSec: textSec,
          textMut: textMut,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        _ThemedTextField(
          controller: emailController,
          label: emailLabel,
          hint: emailHint,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.email_outlined,
          surfaceEl: surfaceEl,
          outline: outline,
          textPri: textPri,
          textSec: textSec,
          textMut: textMut,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        _ThemedTextField(
          controller: passwordController,
          label: passwordLabel,
          hint: passwordHint,
          obscureText: obscurePassword,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          onSuffixTap: onTogglePassword,
          surfaceEl: surfaceEl,
          outline: outline,
          textPri: textPri,
          textSec: textSec,
          textMut: textMut,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        _ThemedTextField(
          controller: confirmPasswordController,
          label: confirmLabel,
          hint: confirmHint,
          obscureText: obscureConfirm,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: obscureConfirm
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          onSuffixTap: onToggleConfirm,
          surfaceEl: surfaceEl,
          outline: outline,
          textPri: textPri,
          textSec: textSec,
          textMut: textMut,
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppTheme.goldGradient
                  : AppTheme.purpleGradientLight,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withAlpha(60),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
