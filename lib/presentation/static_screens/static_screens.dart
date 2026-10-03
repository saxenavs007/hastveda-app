import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../services/app_strings.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';

/// Language Selection Screen
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  late String _selected;

  final List<_LangOption> _languages = const [
    _LangOption(code: 'en', name: 'English', native: 'English', flag: '🇬🇧'),
    _LangOption(code: 'hi', name: 'Hindi', native: 'हिंदी', flag: '🇮🇳'),
    _LangOption(
      code: 'hi-Latn',
      name: 'Hinglish',
      native: 'Hinglish (Roman)',
      flag: '🇮🇳',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selected = 'en';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected = context.read<LocaleProvider>().languageCode;
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
    final primaryColor = isDark ? AppTheme.gold : AppTheme.confetti;
    final cardBg = isDark ? AppTheme.surfaceElevated : AppTheme.surfaceLight;
    final cardBorder = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        title: Text(
          '${s.language} / भाषा',
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.selectLanguage,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPri,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'अपनी पसंदीदा भाषा चुनें',
              style: GoogleFonts.outfit(fontSize: 14, color: textSec),
            ),
            const SizedBox(height: 24),
            ..._languages.map(
              (lang) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selected = lang.code);
                    // Apply immediately
                    localeProvider.setLocale(lang.code);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _selected == lang.code
                          ? primaryColor.withAlpha(isDark ? 30 : 20)
                          : cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selected == lang.code
                            ? primaryColor
                            : cardBorder,
                        width: _selected == lang.code ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(lang.flag, style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: textPri,
                                ),
                              ),
                              Text(
                                lang.native,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: textSec,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selected == lang.code)
                          Icon(
                            Icons.check_circle_rounded,
                            color: primaryColor,
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _selected == 'hi' ? 'सहेजें' : 'Save',
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

class _LangOption {
  final String code;
  final String name;
  final String native;
  final String flag;

  const _LangOption({
    required this.code,
    required this.name,
    required this.native,
    required this.flag,
  });
}

/// Help & About Screen
class HelpAboutScreen extends StatelessWidget {
  const HelpAboutScreen({super.key});

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
    final primaryColor = isDark ? AppTheme.gold : AppTheme.confetti;
    final cardBg = isDark ? AppTheme.surfaceElevated : AppTheme.surfaceLight;
    final cardBorder = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        title: Text(
          s.aboutHastVeda,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
                      )
                    : LinearGradient(
                        colors: [
                          AppTheme.purpleMutedLight,
                          AppTheme.surfaceElevatedLight,
                        ],
                      ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  Icon(Icons.back_hand_rounded, color: primaryColor, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'HastVeda',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.ancientWisdom,
                    style: GoogleFonts.outfit(fontSize: 13, color: textSec),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'HastVeda combines traditional palmistry wisdom with modern AI technology to provide personalized insights about your personality, relationships, career, and life tendencies.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: textSec,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _HelpSection(
              title: 'How It Works',
              isDark: isDark,
              textPri: textPri,
              textSec: textSec,
              primaryColor: primaryColor,
              cardBg: cardBg,
              cardBorder: cardBorder,
              items: const [
                _HelpItem(
                  icon: Icons.back_hand_outlined,
                  title: 'Scan Your Palm',
                  desc:
                      'Use your camera to capture a clear image of your palm.',
                ),
                _HelpItem(
                  icon: Icons.auto_awesome_outlined,
                  title: 'AI Analysis',
                  desc: 'Our AI analyzes your palm lines, mounts, and marks.',
                ),
                _HelpItem(
                  icon: Icons.insights_rounded,
                  title: 'Get Insights',
                  desc:
                      'Receive personalized interpretations based on traditional palmistry.',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _HelpSection(
              title: 'Important Disclaimer',
              isDark: isDark,
              textPri: textPri,
              textSec: textSec,
              primaryColor: primaryColor,
              cardBg: cardBg,
              cardBorder: cardBorder,
              items: const [
                _HelpItem(
                  icon: Icons.info_outline_rounded,
                  title: 'Interpretive Only',
                  desc:
                      'HastVeda provides traditional palmistry interpretations. These are not scientific facts.',
                ),
                _HelpItem(
                  icon: Icons.medical_services_outlined,
                  title: 'Not Medical Advice',
                  desc:
                      'Do not use HastVeda readings for medical decisions. Consult qualified professionals.',
                ),
                _HelpItem(
                  icon: Icons.account_balance_outlined,
                  title: 'Not Financial Advice',
                  desc:
                      'Palm readings do not guarantee financial outcomes. Consult financial advisors.',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '${s.version} 1.0.0',
              style: GoogleFonts.outfit(fontSize: 12, color: textSec),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<_HelpItem> items;
  final bool isDark;
  final Color textPri, textSec, primaryColor, cardBg, cardBorder;

  const _HelpSection({
    required this.title,
    required this.items,
    required this.isDark,
    required this.textPri,
    required this.textSec,
    required this.primaryColor,
    required this.cardBg,
    required this.cardBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        const SizedBox(height: 12),
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
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon, color: primaryColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textPri,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.desc,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: textSec,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < items.length - 1)
                    Divider(height: 1, color: cardBorder, indent: 46),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _HelpItem {
  final IconData icon;
  final String title;
  final String desc;

  const _HelpItem({
    required this.icon,
    required this.title,
    required this.desc,
  });
}

/// Privacy Policy Screen
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    return _LegalScreen(
      title: s.privacyPolicy,
      content: '''
**HastVeda Privacy Policy**

Last updated: August 2026

**1. Information We Collect**
We collect information you provide directly, including your name, email address, and palm images when you use our scanning feature.

**2. How We Use Your Information**
Your palm images are used solely for AI analysis to provide palmistry interpretations. We do not share your palm images with third parties.

**3. Data Security**
Palm images are stored securely with encryption. Only you can access your palm data through your authenticated account.

**4. Palm Images**
Palm images are stored privately and are not publicly accessible. Images are used only for analysis purposes.

**5. Predictions and Interpretations**
HastVeda provides traditional palmistry interpretations. These are not scientific facts and should not be used for medical, financial, or major life decisions.

**6. Your Rights**
You may request deletion of your account and associated data at any time by contacting support.

**7. Contact**
For privacy concerns, contact us through the app's support section.
''',
    );
  }
}

/// Terms & Conditions Screen
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    return _LegalScreen(
      title: s.termsConditions,
      content: '''
**HastVeda Terms & Conditions**

Last updated: August 2026

**1. Acceptance of Terms**
By using HastVeda, you agree to these terms. If you do not agree, please do not use the app.

**2. Nature of Service**
HastVeda provides traditional palmistry interpretations powered by AI. These interpretations are for entertainment and personal reflection purposes only.

**3. Not Professional Advice**
HastVeda readings are NOT:
- Medical advice or diagnosis
- Financial advice or investment guidance
- Legal advice
- Guaranteed predictions of future events

Always consult qualified professionals for medical, financial, and legal matters.

**4. User Responsibilities**
You are responsible for maintaining the security of your account credentials.

**5. Premium Features**
Premium features are available through in-app purchases. All purchases are final unless required by applicable law.

**6. Intellectual Property**
All content, designs, and technology in HastVeda are proprietary.

**7. Limitation of Liability**
HastVeda is not liable for decisions made based on palmistry interpretations.

**8. Changes to Terms**
We may update these terms. Continued use constitutes acceptance of updated terms.
''',
    );
  }
}

/// AI / Palm Reading Disclaimer Screen
class AiDisclaimerScreen extends StatelessWidget {
  const AiDisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = themeProvider.isDark;
    return _LegalScreen(
      title: s.aiDisclaimer,
      content: '''
**AI & Palm Reading Disclaimer**

**Important Notice**
HastVeda uses artificial intelligence to provide palmistry interpretations based on traditional practices. Please read this disclaimer carefully before using the app.

**What HastVeda Is**
HastVeda is an entertainment and personal reflection tool that combines traditional palmistry with AI technology. Our interpretations are based on centuries-old palmistry traditions.

**What HastVeda Is NOT**
- A scientific or medically validated tool
- A substitute for professional medical advice
- A financial or investment advisory service
- A legal advisory service
- A guaranteed predictor of future events

**AI Limitations**
Our AI analyzes palm images to identify lines, mounts, and marks. The interpretations provided are based on traditional palmistry knowledge and should be treated as one perspective among many.

**Accuracy**
Palmistry is a traditional interpretive art, not a science. Results may vary and should not be taken as absolute truth.

**Medical Disclaimer**
Do not use HastVeda to make medical decisions. Always consult a qualified healthcare professional for medical concerns.

**Financial Disclaimer**
Do not use HastVeda to make financial decisions. Always consult a qualified financial advisor.

**Data Privacy**
Your palm images are processed securely and are not shared with third parties. See our Privacy Policy for full details.

**Consent**
By using HastVeda, you acknowledge that you understand the interpretive and non-scientific nature of palmistry readings.
''',
    );
  }
}

class _LegalScreen extends StatelessWidget {
  final String title;
  final String content;

  const _LegalScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        title: Text(
          title,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content.split('\n').map((line) {
            if (line.startsWith('**') && line.endsWith('**')) {
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(
                  line.replaceAll('**', ''),
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPri,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: textSec,
                  height: 1.6,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
