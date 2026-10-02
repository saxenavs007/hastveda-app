// HastVeda Premium Remedies Screen
// Personalized remedies based on the user's actual palm analysis data.
// Premium-gated. Free users see upgrade path.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/premium_strings.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_lock_widget.dart';

class RemedyCategory {
  final String titleEn;
  final String titleHi;
  final String descriptionEn;
  final String descriptionHi;
  final IconData icon;
  final Color color;
  final List<String> remediesEn;
  final List<String> remediesHi;

  const RemedyCategory({
    required this.titleEn,
    required this.titleHi,
    required this.descriptionEn,
    required this.descriptionHi,
    required this.icon,
    required this.color,
    required this.remediesEn,
    required this.remediesHi,
  });
}

class RemediesScreen extends StatefulWidget {
  final String locale;
  const RemediesScreen({super.key, this.locale = 'en'});

  @override
  State<RemediesScreen> createState() => _RemediesScreenState();
}

class _RemediesScreenState extends State<RemediesScreen> {
  bool _isCheckingAccess = true;
  bool _hasAccess = false;
  bool _isLoading = true;
  List<RemedyCategory> _categories = [];
  String? _palmType;
  String? _userName;
  int _expandedIndex = -1;
  bool _appliedLivePremium = false;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _checkAccessAndLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.watch<EntitlementNotifier>().isPremium;
    if (!premium || _hasAccess) return;
    _hasAccess = true;
    _isCheckingAccess = false;
    if (_appliedLivePremium) return;
    _appliedLivePremium = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadRemedies();
    });
  }

  Future<void> _checkAccessAndLoad() async {
    try {
      final canUse = await EntitlementService.instance.canUseFeature(
        PremiumFeatures.detailedReport, // Remedies is a Premium feature
        forceRefresh: true,
      );
      if (!mounted) return;
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _hasAccess = canUse || premium;
        _isCheckingAccess = false;
      });
      if (canUse || premium) await _loadRemedies();
    } catch (_) {
      if (!mounted) return;
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _isCheckingAccess = false;
        if (premium) _hasAccess = true;
      });
      if (premium) await _loadRemedies();
    }
  }

  Future<void> _loadRemedies() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch latest palm analysis
      final analysisData = await SupabaseService.instance.client
          .from('palm_analyses')
          .select('analysis_result, palm_type')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Fetch user name
      try {
        final profile = await SupabaseService.instance.client
            .from('user_profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
        _userName = profile?['full_name'] as String?;
      } catch (_) {}

      if (analysisData != null) {
        _palmType = analysisData['palm_type'] as String?;
        final analysisResult = analysisData['analysis_result'];
        Map<String, dynamic> analysis = {};
        if (analysisResult is Map) {
          analysis = Map<String, dynamic>.from(analysisResult);
        }
        _categories = _buildRemedyCategories(analysis);
      } else {
        _categories = _buildDefaultRemedyCategories();
      }
    } catch (e) {
      debugPrint('loadRemedies error: $e');
      _categories = _buildDefaultRemedyCategories();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<RemedyCategory> _buildRemedyCategories(Map<String, dynamic> analysis) {
    final categories = analysis['categories'] as List? ?? [];
    final Map<String, Map<String, dynamic>> featureMap = {};
    for (final cat in categories) {
      if (cat is Map) {
        final key = (cat['key'] as String? ?? '').toLowerCase();
        featureMap[key] = Map<String, dynamic>.from(cat);
      }
    }

    final palmLines = analysis['palm_lines'] as Map<String, dynamic>? ?? {};
    final lifeLine = palmLines['life_line'] as Map<String, dynamic>? ?? {};
    final heartLine = palmLines['heart_line'] as Map<String, dynamic>? ?? {};
    final headLine = palmLines['head_line'] as Map<String, dynamic>? ?? {};
    final fateLine = palmLines['fate_line'] as Map<String, dynamic>? ?? {};

    final lifeLineObs =
        (lifeLine['observations'] as List?)?.cast<String>() ?? [];
    final heartLineObs =
        (heartLine['observations'] as List?)?.cast<String>() ?? [];
    final headLineObs =
        (headLine['observations'] as List?)?.cast<String>() ?? [];
    final fateLineObs =
        (fateLine['observations'] as List?)?.cast<String>() ?? [];

    final careerCat =
        featureMap['career'] ?? featureMap['career_business'] ?? {};
    final healthCat = featureMap['health'] ?? {};
    final loveCat =
        featureMap['love'] ?? featureMap['love_relationships'] ?? {};
    final wealthCat =
        featureMap['wealth'] ?? featureMap['wealth_finances'] ?? {};

    return [
      RemedyCategory(
        titleEn: 'General Guidance',
        titleHi: 'सामान्य मार्गदर्शन',
        descriptionEn:
            'Traditional Vedic remedies for overall well-being based on your palm reading.',
        descriptionHi:
            'आपके हस्तरेखा पठन के आधार पर समग्र कल्याण के लिए पारंपरिक वैदिक उपाय।',
        icon: Icons.auto_awesome,
        color: AppTheme.gold,
        remediesEn: _buildGeneralRemedies(analysis, lifeLineObs),
        remediesHi: _buildGeneralRemediesHi(analysis, lifeLineObs),
      ),
      RemedyCategory(
        titleEn: 'Career & Professional',
        titleHi: 'करियर और पेशेवर',
        descriptionEn:
            'Guidance for professional growth based on your fate and head lines.',
        descriptionHi:
            'आपकी भाग्य और मस्तिष्क रेखाओं के आधार पर पेशेवर विकास के लिए मार्गदर्शन।',
        icon: Icons.work_outline,
        color: const Color(0xFFE8650A),
        remediesEn: _buildCareerRemedies(careerCat, fateLineObs, headLineObs),
        remediesHi: _buildCareerRemediesHi(careerCat, fateLineObs, headLineObs),
      ),
      RemedyCategory(
        titleEn: 'Financial Guidance',
        titleHi: 'वित्तीय मार्गदर्शन',
        descriptionEn:
            'Traditional guidance for financial well-being from your palm analysis.',
        descriptionHi:
            'आपके हस्तरेखा विश्लेषण से वित्तीय कल्याण के लिए पारंपरिक मार्गदर्शन।',
        icon: Icons.currency_rupee,
        color: const Color(0xFF2D7A4F),
        remediesEn: _buildFinancialRemedies(wealthCat),
        remediesHi: _buildFinancialRemediesHi(wealthCat),
      ),
      RemedyCategory(
        titleEn: 'Relationship Guidance',
        titleHi: 'रिश्ते का मार्गदर्शन',
        descriptionEn:
            'Guidance for love and relationships based on your heart line.',
        descriptionHi:
            'आपकी हृदय रेखा के आधार पर प्रेम और रिश्तों के लिए मार्गदर्शन।',
        icon: Icons.favorite_outline,
        color: const Color(0xFF8B5CF6),
        remediesEn: _buildRelationshipRemedies(loveCat, heartLineObs),
        remediesHi: _buildRelationshipRemediesHi(loveCat, heartLineObs),
      ),
      RemedyCategory(
        titleEn: 'Well-being & Lifestyle',
        titleHi: 'स्वास्थ्य और जीवनशैली',
        descriptionEn:
            'Lifestyle guidance for vitality based on your life line.',
        descriptionHi:
            'आपकी जीवन रेखा के आधार पर जीवनशक्ति के लिए जीवनशैली मार्गदर्शन।',
        icon: Icons.self_improvement,
        color: const Color(0xFF0891B2),
        remediesEn: _buildWellbeingRemedies(healthCat, lifeLineObs),
        remediesHi: _buildWellbeingRemediesHi(healthCat, lifeLineObs),
      ),
      RemedyCategory(
        titleEn: 'Spiritual & Traditional',
        titleHi: 'आध्यात्मिक और पारंपरिक',
        descriptionEn:
            'Ancient Vedic practices and spiritual remedies from Hasta Rekha Shastra.',
        descriptionHi:
            'हस्त रेखा शास्त्र से प्राचीन वैदिक प्रथाएं और आध्यात्मिक उपाय।',
        icon: Icons.temple_hindu,
        color: const Color(0xFFB45309),
        remediesEn: _buildSpiritualRemedies(analysis),
        remediesHi: _buildSpiritualRemediesHi(analysis),
      ),
    ];
  }

  List<String> _buildGeneralRemedies(
    Map<String, dynamic> analysis,
    List<String> lifeObs,
  ) {
    final base = [
      'Begin each morning with 5 minutes of palm meditation — hold your palms upward and breathe deeply to activate your life force energy.',
      'Wear copper or gold on your dominant hand to strengthen the energy channels identified in your palm reading.',
      'Practice gratitude journaling each evening to align your conscious mind with the positive patterns in your palm.',
    ];
    if (lifeObs.isNotEmpty) {
      base.add(
        'Your life line observation "${lifeObs.first}" suggests: maintain consistent daily routines for sustained vitality.',
      );
    }
    return base;
  }

  List<String> _buildGeneralRemediesHi(
    Map<String, dynamic> analysis,
    List<String> lifeObs,
  ) {
    return [
      'प्रत्येक सुबह 5 मिनट हथेली ध्यान से शुरू करें — अपनी हथेलियाँ ऊपर की ओर रखें और जीवन शक्ति ऊर्जा को सक्रिय करने के लिए गहरी सांस लें।',
      'ऊर्जा चैनलों को मजबूत करने के लिए अपने प्रमुख हाथ पर तांबा या सोना पहनें।',
      'अपने सचेत मन को अपनी हथेली के सकारात्मक पैटर्न के साथ संरेखित करने के लिए प्रत्येक शाम कृतज्ञता जर्नलिंग का अभ्यास करें।',
      if (lifeObs.isNotEmpty)
        'आपकी जीवन रेखा का अवलोकन "${lifeObs.first}" सुझाता है: निरंतर जीवनशक्ति के लिए सुसंगत दैनिक दिनचर्या बनाए रखें।',
    ];
  }

  List<String> _buildCareerRemedies(
    Map<String, dynamic> careerCat,
    List<String> fateObs,
    List<String> headObs,
  ) {
    final content =
        (careerCat['content_en'] as String?) ??
        (careerCat['content'] as String?) ??
        '';
    final base = [
      'Strengthen your fate line energy by setting clear professional intentions every Sunday evening.',
      'Place a small piece of yellow sapphire or citrine on your work desk to enhance career clarity (traditional guidance only).',
      'Practice the "open palm" technique before important meetings — open your dominant hand fully for 30 seconds to activate career energy.',
    ];
    if (content.isNotEmpty) {
      base.insert(
        0,
        'Based on your palm analysis: $content — Channel this energy through focused professional development.',
      );
    }
    if (fateObs.isNotEmpty) {
      base.add(
        'Your fate line shows: "${fateObs.first}" — Use this insight to guide your career decisions.',
      );
    }
    return base;
  }

  List<String> _buildCareerRemediesHi(
    Map<String, dynamic> careerCat,
    List<String> fateObs,
    List<String> headObs,
  ) {
    final content =
        (careerCat['content_hi'] as String?) ??
        (careerCat['content_en'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'आपके हस्तरेखा विश्लेषण के आधार पर: $content — इस ऊर्जा को केंद्रित पेशेवर विकास के माध्यम से चैनल करें।',
      'हर रविवार शाम स्पष्ट पेशेवर इरादे निर्धारित करके अपनी भाग्य रेखा ऊर्जा को मजबूत करें।',
      'करियर स्पष्टता बढ़ाने के लिए अपनी कार्य डेस्क पर पीला नीलम या सिट्रीन रखें (केवल पारंपरिक मार्गदर्शन)।',
      if (fateObs.isNotEmpty)
        'आपकी भाग्य रेखा दर्शाती है: "${fateObs.first}" — इस अंतर्दृष्टि का उपयोग अपने करियर निर्णयों का मार्गदर्शन करने के लिए करें।',
    ];
  }

  List<String> _buildFinancialRemedies(Map<String, dynamic> wealthCat) {
    final content =
        (wealthCat['content_en'] as String?) ??
        (wealthCat['content'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'Your palm\'s wealth indicators suggest: $content — Apply this wisdom to your financial planning.',
      'Keep a small amount of saffron or turmeric in your wallet as a traditional symbol of financial abundance.',
      'Avoid major financial decisions on new moon days — your palm\'s energy patterns are most receptive during the waxing moon.',
      'Practice the "wealth mudra" (Kubera mudra) for 5 minutes daily to align your palm energy with financial intentions.',
      'Disclaimer: These are traditional Vedic guidance practices. They do not guarantee financial outcomes. Always consult a qualified financial advisor for investment decisions.',
    ];
  }

  List<String> _buildFinancialRemediesHi(Map<String, dynamic> wealthCat) {
    final content =
        (wealthCat['content_hi'] as String?) ??
        (wealthCat['content_en'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'आपकी हथेली के धन संकेतक सुझाते हैं: $content — इस ज्ञान को अपनी वित्तीय योजना में लागू करें।',
      'वित्तीय प्रचुरता के पारंपरिक प्रतीक के रूप में अपने बटुए में थोड़ी मात्रा में केसर या हल्दी रखें।',
      'अमावस्या के दिनों में बड़े वित्तीय निर्णय लेने से बचें।',
      'अपनी हथेली ऊर्जा को वित्तीय इरादों के साथ संरेखित करने के लिए प्रतिदिन 5 मिनट "धन मुद्रा" (कुबेर मुद्रा) का अभ्यास करें।',
      'अस्वीकरण: ये पारंपरिक वैदिक मार्गदर्शन प्रथाएं हैं। ये वित्तीय परिणामों की गारंटी नहीं देती हैं।',
    ];
  }

  List<String> _buildRelationshipRemedies(
    Map<String, dynamic> loveCat,
    List<String> heartObs,
  ) {
    final content =
        (loveCat['content_en'] as String?) ??
        (loveCat['content'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'Your heart line reveals: $content — Nurture these relationship qualities consciously.',
      'Wear rose quartz or pearl on your left hand to strengthen heart line energy (traditional guidance).',
      'Practice "heart opening" breathing: place both palms on your chest for 2 minutes each morning.',
      if (heartObs.isNotEmpty)
        'Your heart line observation "${heartObs.first}" suggests: focus on authentic emotional expression in your relationships.',
      'Light a rose or jasmine incense on Friday evenings as a traditional Vedic practice for relationship harmony.',
    ];
  }

  List<String> _buildRelationshipRemediesHi(
    Map<String, dynamic> loveCat,
    List<String> heartObs,
  ) {
    final content =
        (loveCat['content_hi'] as String?) ??
        (loveCat['content_en'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'आपकी हृदय रेखा प्रकट करती है: $content — इन रिश्ते की गुणवत्ताओं को सचेत रूप से पोषित करें।',
      'हृदय रेखा ऊर्जा को मजबूत करने के लिए अपने बाएं हाथ पर गुलाबी क्वार्ट्ज या मोती पहनें।',
      '"हृदय खोलने" की श्वास का अभ्यास करें: प्रत्येक सुबह 2 मिनट के लिए दोनों हथेलियाँ अपनी छाती पर रखें।',
      if (heartObs.isNotEmpty)
        'आपकी हृदय रेखा का अवलोकन "${heartObs.first}" सुझाता है: अपने रिश्तों में प्रामाणिक भावनात्मक अभिव्यक्ति पर ध्यान दें।',
    ];
  }

  List<String> _buildWellbeingRemedies(
    Map<String, dynamic> healthCat,
    List<String> lifeObs,
  ) {
    final content =
        (healthCat['content_en'] as String?) ??
        (healthCat['content'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'Your life line indicates: $content — Honor these vitality patterns with mindful lifestyle choices.',
      'Practice palm self-massage for 5 minutes each morning to stimulate the energy points mapped in your reading.',
      'Drink copper-vessel water each morning as a traditional Ayurvedic practice for vitality.',
      if (lifeObs.isNotEmpty)
        'Your life line shows: "${lifeObs.first}" — Align your daily routine with this energy pattern.',
      'Disclaimer: These are traditional wellness guidance practices. They are not medical advice. Consult a qualified healthcare professional for medical concerns.',
    ];
  }

  List<String> _buildWellbeingRemediesHi(
    Map<String, dynamic> healthCat,
    List<String> lifeObs,
  ) {
    final content =
        (healthCat['content_hi'] as String?) ??
        (healthCat['content_en'] as String?) ??
        '';
    return [
      if (content.isNotEmpty)
        'आपकी जीवन रेखा दर्शाती है: $content — सचेत जीवनशैली विकल्पों के साथ इन जीवनशक्ति पैटर्न का सम्मान करें।',
      'ऊर्जा बिंदुओं को उत्तेजित करने के लिए प्रत्येक सुबह 5 मिनट हथेली स्व-मालिश का अभ्यास करें।',
      'जीवनशक्ति के लिए पारंपरिक आयुर्वेदिक अभ्यास के रूप में प्रत्येक सुबह तांबे के बर्तन का पानी पिएं।',
      if (lifeObs.isNotEmpty)
        'आपकी जीवन रेखा दर्शाती है: "${lifeObs.first}" — इस ऊर्जा पैटर्न के साथ अपनी दैनिक दिनचर्या संरेखित करें।',
      'अस्वीकरण: ये पारंपरिक कल्याण मार्गदर्शन प्रथाएं हैं। ये चिकित्सा सलाह नहीं हैं।',
    ];
  }

  List<String> _buildSpiritualRemedies(Map<String, dynamic> analysis) {
    return [
      'Recite the Gayatri Mantra 108 times on Sunday mornings while holding your palms upward — this activates the solar energy in your palm lines.',
      'Perform "Surya Namaskar" (Sun Salutation) facing east each morning to align your palm energy with cosmic forces.',
      'Light a ghee lamp on Thursday evenings as a traditional practice for wisdom and clarity (associated with Jupiter/Brihaspati).',
      'Meditate on the "Hamsa" symbol — the sacred hand — for 10 minutes weekly to deepen your connection with your palm\'s wisdom.',
      'Visit a temple or sacred space on the day associated with your dominant mount (as identified in your palm analysis) for spiritual alignment.',
      'These are traditional Vedic and palmistry-based spiritual practices. They represent cultural wisdom, not guaranteed outcomes.',
    ];
  }

  List<String> _buildSpiritualRemediesHi(Map<String, dynamic> analysis) {
    return [
      'रविवार की सुबह अपनी हथेलियाँ ऊपर की ओर रखते हुए 108 बार गायत्री मंत्र का जाप करें।',
      'अपनी हथेली ऊर्जा को ब्रह्मांडीय शक्तियों के साथ संरेखित करने के लिए प्रत्येक सुबह पूर्व की ओर मुख करके "सूर्य नमस्कार" करें।',
      'ज्ञान और स्पष्टता के लिए पारंपरिक अभ्यास के रूप में गुरुवार की शाम घी का दीपक जलाएं।',
      'अपनी हथेली की बुद्धि के साथ अपने संबंध को गहरा करने के लिए साप्ताहिक 10 मिनट "हंस" प्रतीक पर ध्यान करें।',
      'ये पारंपरिक वैदिक और हस्तरेखा-आधारित आध्यात्मिक प्रथाएं हैं। ये सांस्कृतिक ज्ञान का प्रतिनिधित्व करती हैं, गारंटीकृत परिणाम नहीं।',
    ];
  }

  List<RemedyCategory> _buildDefaultRemedyCategories() {
    return _buildRemedyCategories({});
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          _isHindi ? '🌿  उपाय' : '🌿  Remedies',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.homeScreen),
        ),
      ),
      body: _isCheckingAccess
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : !_hasAccess
          ? _buildLockedState(context, isDark)
          : _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _buildContent(context, isDark),
    );
  }

  Widget _buildLockedState(BuildContext context, bool isDark) {
    final strings = PremiumStrings(locale: widget.locale);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Text('🌿', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            _isHindi ? 'प्रीमियम उपाय' : 'Premium Remedies',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isHindi
                ? 'आपके वास्तविक हस्तरेखा विश्लेषण के आधार पर व्यक्तिगत पारंपरिक उपाय और मार्गदर्शन।'
                : 'Personalized traditional remedies and guidance based on your actual palm analysis.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.textSecondaryLight,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          PremiumLockWidget(
            feature: PremiumFeatures.detailedReport,
            locale: widget.locale,
            child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                '${AppRoutes.premiumPaywall}?locale=${widget.locale}',
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                _isHindi ? 'प्रीमियम अनलॉक करें' : 'Unlock Premium',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A0F05), Color(0xFF2D1A0A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🌿', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isHindi ? 'HastVeda उपाय' : 'HastVeda Remedies',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gold,
                          ),
                        ),
                        Text(
                          _isHindi
                              ? 'प्राचीन ज्ञान। बुद्धिमान अंतर्दृष्टि।'
                              : 'Ancient Wisdom. Intelligent Insights.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_userName != null || _palmType != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.gold.withAlpha(40)),
                  ),
                  child: Text(
                    _isHindi
                        ? 'व्यक्तिगत${_userName != null ? " — $_userName" : ""}${_palmType != null ? " • $_palmType" : ""}'
                        : 'Personalized${_userName != null ? " for $_userName" : ""}${_palmType != null ? " • $_palmType" : ""}',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _isHindi
                    ? 'ये उपाय आपके वास्तविक हस्तरेखा विश्लेषण के आधार पर पारंपरिक वैदिक मार्गदर्शन हैं। ये चिकित्सीय, वित्तीय या कानूनी सलाह नहीं हैं।'
                    : 'These remedies are traditional Vedic guidance based on your actual palm analysis. They are not medical, financial, or legal advice.',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Remedy categories
        ..._categories.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          final isExpanded = _expandedIndex == i;
          final remedies = _isHindi ? cat.remediesHi : cat.remediesEn;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: surfaceEl,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isExpanded ? cat.color.withAlpha(80) : border,
                width: isExpanded ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _expandedIndex = isExpanded ? -1 : i),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cat.color.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(cat.icon, color: cat.color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isHindi ? cat.titleHi : cat.titleEn,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textPri,
                                ),
                              ),
                              Text(
                                _isHindi
                                    ? cat.descriptionHi
                                    : cat.descriptionEn,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: textSec,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: cat.color,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded) ...[
                  Divider(color: border, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: remedies.asMap().entries.map((e) {
                        final isDisclaimer =
                            e.value.toLowerCase().startsWith('disclaimer') ||
                            e.value.toLowerCase().startsWith('अस्वीकरण');
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDisclaimer
                                ? Colors.orange.withAlpha(15)
                                : cat.color.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDisclaimer
                                  ? Colors.orange.withAlpha(40)
                                  : cat.color.withAlpha(30),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isDisclaimer
                                    ? Icons.info_outline
                                    : Icons.spa_outlined,
                                size: 16,
                                color: isDisclaimer ? Colors.orange : cat.color,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.value,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: isDisclaimer
                                        ? Colors.orange.shade800
                                        : textPri,
                                    height: 1.5,
                                    fontStyle: isDisclaimer
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
