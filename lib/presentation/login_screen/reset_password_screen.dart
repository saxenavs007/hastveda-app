import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/app_strings.dart';
import '../../services/locale_provider.dart';
import '../../theme/app_theme.dart';

/// Lands here from the Supabase recovery email
/// (`https://www.hastveda.co/reset-password`).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  StreamSubscription<AuthState>? _authSub;
  bool _canReset = false;
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _canReset = Supabase.instance.client.auth.currentSession != null;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final recovery = state.event == AuthChangeEvent.passwordRecovery;
      final signedIn = state.session != null;
      if ((recovery || signedIn) && mounted) {
        setState(() => _canReset = true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save(AppStrings s) async {
    if (_passwordController.text.length < 6) {
      setState(() => _error = s.passwordTooShort);
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = s.passwordsDoNotMatch);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (mounted) setState(() => _done = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = s.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context.watch<LocaleProvider>().languageCode);
    final hindi = context.watch<LocaleProvider>().languageCode == 'hi';

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        foregroundColor: AppTheme.textPrimary,
        title: Text(
          hindi ? 'पासवर्ड रीसेट' : 'Reset password',
          style: GoogleFonts.cormorantGaramond(fontSize: 24),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            children: [
              Text(
                hindi
                    ? 'ValueNest Technologies Private Limited द्वारा HastVeda'
                    : 'Choose a new password for your HastVeda account.',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              if (_done)
                Text(
                  hindi
                      ? 'पासवर्ड बदल गया। अब साइन इन करें।'
                      : 'Password updated. You can sign in now.',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    color: AppTheme.goldLight,
                  ),
                )
              else if (!_canReset)
                Text(
                  hindi
                      ? 'ईमेल में भेजा गया रीसेट लिंक खोलें, फिर नया पासवर्ड सेट करें।'
                      : 'Open the reset link from your email, then set a new password here.',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.45,
                    color: AppTheme.textPrimary,
                  ),
                )
              else ...[
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: GoogleFonts.outfit(color: AppTheme.textPrimary),
                  decoration: InputDecoration(labelText: s.password),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  style: GoogleFonts.outfit(color: AppTheme.textPrimary),
                  decoration: InputDecoration(labelText: s.confirmPassword),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: GoogleFonts.outfit(color: AppTheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _save(s),
                    child: Text(_saving ? '...' : (hindi ? 'सहेजें' : 'Save password')),
                  ),
                ),
              ],
              if (_done) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => context.go(AppRoutes.login),
                  child: Text(s.signIn),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
