import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/app_strings.dart';
import '../../services/engagement_alerts_service.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  List<EngagementAlert> _alerts = [];
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final alerts = await EngagementAlertsService.instance.todaysAlerts();
    List<Map<String, dynamic>> stored = [];
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final data = await Supabase.instance.client
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(30);
        stored = List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _notifications = stored;
      _isLoading = false;
    });
  }

  Future<void> _onAlertTap(EngagementAlert alert) async {
    final signedIn = Supabase.instance.client.auth.currentUser != null;
    if (!signedIn) {
      context.push(AppRoutes.login);
      return;
    }
    if (!alert.personalized && alert.body.startsWith('Scan your palm')) {
      context.go(AppRoutes.palmScanScreen);
      return;
    }
    final uri = Uri(
      path: AppRoutes.insightPreview,
      queryParameters: {
        'title': alert.title,
        'teaser': alert.teaser,
        'question': alert.question,
      },
    );
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = themeProvider.isDark;
    final isHindi = localeProvider.languageCode == 'hi';

    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final primaryColor = isDark ? AppTheme.gold : AppTheme.confetti;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        automaticallyImplyLeading: false,
        leading: context.canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
                onPressed: () => context.pop(),
              )
            : null,
        title: Text(
          s.notificationsTitle,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: primaryColor,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                children: [
                  Text(
                    isHindi ? 'आज के संकेत' : 'Today’s alerts',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isHindi
                        ? 'ये कार्ड हर दिन बदलते हैं और आपके सहेजे स्कैन पर आधारित हैं।'
                        : 'These cards refresh daily and follow your saved palm scan.',
                    style: GoogleFonts.outfit(fontSize: 12, color: textSec),
                  ),
                  const SizedBox(height: 12),
                  ..._alerts.map(
                    (alert) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AlertCard(
                        alert: alert,
                        primary: primaryColor,
                        textPri: textPri,
                        textSec: textSec,
                        isDark: isDark,
                        isHindi: isHindi,
                        onTap: () => _onAlertTap(alert),
                      ),
                    ),
                  ),
                  if (_notifications.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      isHindi ? 'खाता सूचनाएं' : 'Account notices',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._notifications.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${n['title'] ?? 'HastVeda'}\n${n['body'] ?? ''}',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: textSec,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final EngagementAlert alert;
  final Color primary;
  final Color textPri;
  final Color textSec;
  final bool isDark;
  final bool isHindi;
  final VoidCallback onTap;

  const _AlertCard({
    required this.alert,
    required this.primary,
    required this.textPri,
    required this.textSec,
    required this.isDark,
    required this.isHindi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppTheme.surfaceElevated : AppTheme.surfaceLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primary.withAlpha(70)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(alert.icon, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.body,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        height: 1.4,
                        color: textSec,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isHindi ? 'और जानें' : 'Know more',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
