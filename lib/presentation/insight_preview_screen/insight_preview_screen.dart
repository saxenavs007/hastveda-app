import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../services/engagement_alerts_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/locale_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cashfree_platform_sheet.dart';

/// One-line palm teaser. Payment starts only after Know More.
class InsightPreviewScreen extends StatefulWidget {
  final String? title;
  final String? teaser;
  final String? question;

  const InsightPreviewScreen({
    super.key,
    this.title,
    this.teaser,
    this.question,
  });

  @override
  State<InsightPreviewScreen> createState() => _InsightPreviewScreenState();
}

class _InsightPreviewScreenState extends State<InsightPreviewScreen> {
  EngagementAlert? _loaded;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if ((widget.teaser ?? '').trim().isEmpty) {
      _loading = true;
      _loadFirstAlert();
    }
  }

  Future<void> _loadFirstAlert() async {
    final alerts = await EngagementAlertsService.instance.todaysAlerts();
    if (!mounted) return;
    setState(() {
      _loaded = alerts.isEmpty ? null : alerts.first;
      _loading = false;
    });
  }

  String get _title =>
      (widget.title ?? '').trim().isNotEmpty
          ? widget.title!.trim()
          : (_loaded?.title ?? 'A palm signal is waiting');

  String get _teaser =>
      (widget.teaser ?? '').trim().isNotEmpty
          ? widget.teaser!.trim()
          : (_loaded?.teaser ??
              'A hidden shift in your fate line indicates an unexpected turn...');

  String get _question =>
      (widget.question ?? '').trim().isNotEmpty
          ? widget.question!.trim()
          : (_loaded?.question ??
              'What does my latest palm scan say about this change?');

  Future<void> _knowMore() async {
    final isHindi = context.read<LocaleProvider>().languageCode == 'hi';
    final premium = context.read<EntitlementNotifier>().isPremium;
    if (premium) {
      _openAsk(startPayment: false);
      return;
    }
    await showModalBottomSheet<void>(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isHindi ? 'पूरा संकेत खोलें' : 'Unlock the full insight',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isHindi
                    ? 'एक प्रश्न ₹59 (₹50 + GST)। भुगतान के बाद पूरा उत्तर खुलता है।'
                    : 'One question for ₹59 (₹50 + GST). The full answer unlocks after payment.',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    if (!cashfreeCheckoutSupported) {
                      await showCashfreePlatformSheet(
                        context,
                        isHindi: isHindi,
                      );
                      return;
                    }
                    _openAsk(startPayment: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    isHindi
                        ? '₹59 में जानें (₹50 + GST)'
                        : 'Know more for ₹59 (₹50 + GST)',
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

  void _openAsk({required bool startPayment}) {
    final locale = context.read<LocaleProvider>().languageCode;
    final uri = Uri(
      path: AppRoutes.askHastveda,
      queryParameters: {
        'locale': locale,
        'question': _question,
        if (startPayment) 'pay': '1',
      },
    );
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final isHindi = context.watch<LocaleProvider>().languageCode == 'hi';
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        foregroundColor: Colors.white,
        title: Text(
          isHindi ? 'आपका संकेत' : 'Your signal',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary.withAlpha(90)),
                      color: AppTheme.primary.withAlpha(18),
                    ),
                    child: Text(
                      _teaser,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        height: 1.45,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _knowMore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: const Color(0xFF1A0E06),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        isHindi ? 'और जानें' : 'Know More',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
