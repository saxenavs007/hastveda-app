import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../services/app_strings.dart';
import '../../services/locale_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      title: 'Decode Your Cosmic Blueprint',
      subtitle:
          'HastVeda harnesses advanced AI to unlock the ancient wisdom inscribed in your palm lines — offering deeply personalized insights into your character, life path, and hidden destiny.',
      imageAsset: 'assets/images/hastveda_onboarding_1_cosmic_blueprint.png',
      semanticLabel:
          'Majestic glowing golden mystic palm against a deep cosmic nebula with subtle constellation lines',
    ),
    _OnboardingPage(
      title: 'AI-Powered Palm Analysis',
      subtitle:
          'Our proprietary AI engine meticulously analyzes your Life Line, Heart Line, Head Line, Fate Line, and more — providing interpretations deeply rooted in traditional palmistry but enhanced by modern technology.',
      imageAsset: 'assets/images/hastveda_onboarding_2_ai_analysis.png',
      semanticLabel:
          'Futuristic glowing hand with intricate golden data lines and a biometric grid overlay',
    ),
    _OnboardingPage(
      title: 'Your Personalized Daily Guidance',
      subtitle:
          'Receive daily, weekly, monthly, and yearly predictions uniquely tailored to your personal palm profile. Gain profound clarity on matters of love, career, wealth, and relationships.',
      imageAsset: 'assets/images/hastveda_onboarding_3_daily_guidance.png',
      semanticLabel:
          'Majestic glowing palm filled with floating astrological symbols and celestial sparkling dust',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Track onboarding started
    analytics.track(HastVedaEvents.onboardingStarted);
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      analytics.track(HastVedaEvents.onboardingCompleted);
      context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Compact layout for small screens (< 680px height)
    final isSmall = screenHeight < 680;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Stack(
        children: [
          // Pages
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _pages.length,
            itemBuilder: (context, index) =>
                _OnboardingPageView(page: _pages[index], isSmall: isSmall),
          ),
          // Bottom controls — always visible, adapts to screen size
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                isSmall ? 20 : 32,
                24,
                (bottomPadding > 0 ? bottomPadding : 24) + (isSmall ? 8 : 16),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.backgroundDark.withAlpha(230),
                    AppTheme.backgroundDark,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? AppTheme.gold
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmall ? 16 : 24),
                  // Next / Get Started button
                  SizedBox(
                    width: double.infinity,
                    height: isSmall ? 48 : 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.goldGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.gold.withAlpha(60),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: const Color(0xFF0A0A0F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1
                              ? s.getStarted
                              : s.next,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0A0A0F),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmall ? 4 : 12),
                  // Skip
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: () {
                        analytics.track(
                          HastVedaEvents.onboardingSkipped,
                          properties: {'page': _currentPage},
                        );
                        context.go(AppRoutes.login);
                      },
                      style: TextButton.styleFrom(
                        minimumSize: const Size(88, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        s.skip,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 44),
                ],
              ),
            ),
          ),
          // Top logo — safe area aware
          Positioned(
            top: MediaQuery.of(context).padding.top + (isSmall ? 8 : 16),
            left: 24,
            right: 24,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.gold.withAlpha(60),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: const CustomImageWidget(
                      imageUrl: 'assets/images/hastveda_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppTheme.goldGradient.createShader(bounds),
                  child: Text(
                    'HastVeda',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final String title;
  final String subtitle;
  final String imageAsset;
  final String semanticLabel;

  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.semanticLabel,
  });
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  final bool isSmall;

  const _OnboardingPageView({required this.page, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    // Text block sits above the bottom controls area
    final textBottomOffset = isSmall ? 160.0 : 200.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomImageWidget(
          imageUrl: page.imageAsset,
          fit: BoxFit.cover,
          semanticLabel: page.semanticLabel,
        ),
        // Subtle particle-dimming layer
        Container(color: const Color(0xFF0A0A0F).withAlpha(28)),
        // Warm-golden palm-line enhancement
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.15),
                radius: 0.55,
                colors: [
                  const Color(0xFFD4A843).withAlpha(38),
                  const Color(0xFFEFC96A).withAlpha(18),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        // Gradient overlay for text readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0A0A0F).withAlpha(120),
                Colors.transparent,
                const Color(0xFF0A0A0F).withAlpha(180),
                const Color(0xFF0A0A0F),
              ],
              stops: const [0.0, 0.35, 0.65, 1.0],
            ),
          ),
        ),
        // Text content — positioned above bottom controls
        Positioned(
          bottom: textBottomOffset,
          left: 24,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                page.title,
                style: AppTheme.display(
                  isSmall ? 30 : 36,
                  weight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: isSmall ? 8 : 12),
              Text(
                page.subtitle,
                style: GoogleFonts.outfit(
                  fontSize: isSmall ? 13 : 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
                maxLines: isSmall ? 7 : 8,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
