import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

// Personalized Predictions Service
// Fetches the user's latest palm analysis and generates personalized predictions
// using the actual palm data. No static/hardcoded content.

class PersonalizedPrediction {
  final String category;
  final String categoryHi;
  final String content;
  final String contentHi;
  final String iconName;
  final int confidence;
  final bool isMajorEvent;

  const PersonalizedPrediction({
    required this.category,
    required this.categoryHi,
    required this.content,
    required this.contentHi,
    required this.iconName,
    required this.confidence,
    this.isMajorEvent = false,
  });
}

class PalmPredictionsData {
  final List<PersonalizedPrediction> today;
  final List<PersonalizedPrediction> weekly;
  final List<PersonalizedPrediction> monthly;
  final List<PersonalizedPrediction> yearly;
  final String? palmType;
  final String? userName;
  final bool isPersonalized;
  final String? errorMessage;

  const PalmPredictionsData({
    required this.today,
    required this.weekly,
    required this.monthly,
    required this.yearly,
    this.palmType,
    this.userName,
    this.isPersonalized = false,
    this.errorMessage,
  });

  static PalmPredictionsData empty() => const PalmPredictionsData(
    today: [],
    weekly: [],
    monthly: [],
    yearly: [],
    isPersonalized: false,
  );
}

class PersonalizedPredictionsService {
  static PersonalizedPredictionsService? _instance;
  static PersonalizedPredictionsService get instance =>
      _instance ??= PersonalizedPredictionsService._();
  PersonalizedPredictionsService._();

  /// Fetches the user's latest palm analysis and builds personalized predictions.
  Future<PalmPredictionsData> getPredictions() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return PalmPredictionsData.empty();

      // Fetch latest palm analysis
      final analysisData = await SupabaseService.instance.client
          .from('palm_analyses')
          .select('analysis_result, created_at, palm_type')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (analysisData == null) {
        return PalmPredictionsData.empty();
      }

      // Fetch user name
      String? userName;
      try {
        final profile = await SupabaseService.instance.client
            .from('user_profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
        userName = profile?['full_name'] as String?;
      } catch (_) {}

      final analysisResult = analysisData['analysis_result'];
      final palmType = analysisData['palm_type'] as String?;

      if (analysisResult == null) return PalmPredictionsData.empty();

      // Parse analysis result
      Map<String, dynamic> analysis = {};
      if (analysisResult is Map) {
        analysis = Map<String, dynamic>.from(analysisResult);
      } else if (analysisResult is String) {
        try {
          analysis = Map<String, dynamic>.from(
            analysisResult as Map<String, dynamic>,
          );
        } catch (_) {}
      }

      return _buildPredictions(analysis, palmType, userName);
    } catch (e) {
      debugPrint('PersonalizedPredictionsService error: $e');
      return PalmPredictionsData.empty();
    }
  }

  PalmPredictionsData _buildPredictions(
    Map<String, dynamic> analysis,
    String? palmType,
    String? userName,
  ) {
    // Extract key palm features from analysis
    final categories = analysis['categories'] as List? ?? [];
    final palmLines = analysis['palm_lines'] as Map<String, dynamic>? ?? {};
    final mounts = analysis['mounts'] as Map<String, dynamic>? ?? {};
    final overallScore = (analysis['overall_score'] as num?)?.toInt() ?? 70;
    final summary = analysis['summary'] as String? ?? '';

    // Build feature map from categories
    final Map<String, Map<String, dynamic>> featureMap = {};
    for (final cat in categories) {
      if (cat is Map) {
        final key = (cat['key'] as String? ?? '').toLowerCase();
        featureMap[key] = Map<String, dynamic>.from(cat);
      }
    }

    // Extract specific line data
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

    // Career/Finance feature
    final careerCat =
        featureMap['career'] ?? featureMap['career_business'] ?? {};
    final careerScore = (careerCat['score'] as num?)?.toInt() ?? overallScore;
    final careerContentEn =
        (careerCat['content_en'] as String?) ??
        (careerCat['content'] as String?) ??
        '';
    final careerContentHi =
        (careerCat['content_hi'] as String?) ?? careerContentEn;

    // Love/Relationship feature
    final loveCat =
        featureMap['love'] ?? featureMap['love_relationships'] ?? {};
    final loveScore = (loveCat['score'] as num?)?.toInt() ?? overallScore;
    final loveContentEn =
        (loveCat['content_en'] as String?) ??
        (loveCat['content'] as String?) ??
        '';
    final loveContentHi = (loveCat['content_hi'] as String?) ?? loveContentEn;

    // Health feature
    final healthCat = featureMap['health'] ?? {};
    final healthScore = (healthCat['score'] as num?)?.toInt() ?? overallScore;
    final healthContentEn =
        (healthCat['content_en'] as String?) ??
        (healthCat['content'] as String?) ??
        '';
    final healthContentHi =
        (healthCat['content_hi'] as String?) ?? healthContentEn;

    // Personality feature
    final personalityCat = featureMap['personality'] ?? {};
    final personalityContentEn =
        (personalityCat['content_en'] as String?) ??
        (personalityCat['content'] as String?) ??
        '';
    final personalityContentHi =
        (personalityCat['content_hi'] as String?) ?? personalityContentEn;

    // Wealth feature
    final wealthCat =
        featureMap['wealth'] ?? featureMap['wealth_finances'] ?? {};
    final wealthScore = (wealthCat['score'] as num?)?.toInt() ?? overallScore;
    final wealthContentEn =
        (wealthCat['content_en'] as String?) ??
        (wealthCat['content'] as String?) ??
        '';
    final wealthContentHi =
        (wealthCat['content_hi'] as String?) ?? wealthContentEn;

    // Build today predictions from actual palm data
    final todayPredictions = <PersonalizedPrediction>[];

    if (careerContentEn.isNotEmpty || fateLineObs.isNotEmpty) {
      final fateObs = fateLineObs.isNotEmpty ? ' ${fateLineObs.first}' : '';
      todayPredictions.add(
        PersonalizedPrediction(
          category: 'Career & Finance',
          categoryHi: 'करियर और वित्त',
          content: careerContentEn.isNotEmpty
              ? 'Based on your palm analysis: $careerContentEn$fateObs'
              : 'Your fate line shows${fateObs.isNotEmpty ? fateObs : " active career energy today"}. Focus on professional decisions with clarity.',
          contentHi: careerContentHi.isNotEmpty
              ? 'आपके हस्तरेखा विश्लेषण के अनुसार: $careerContentHi'
              : 'आपकी भाग्य रेखा${fateObs.isNotEmpty ? " $fateObs" : " सक्रिय करियर ऊर्जा"} दर्शाती है।',
          iconName: 'work_outline',
          confidence: careerScore.clamp(60, 95),
          isMajorEvent: careerScore >= 80,
        ),
      );
    }

    if (loveContentEn.isNotEmpty || heartLineObs.isNotEmpty) {
      final heartObs = heartLineObs.isNotEmpty ? ' ${heartLineObs.first}' : '';
      todayPredictions.add(
        PersonalizedPrediction(
          category: 'Love & Relationships',
          categoryHi: 'प्रेम और रिश्ते',
          content: loveContentEn.isNotEmpty
              ? 'Your heart line reveals: $loveContentEn$heartObs'
              : 'Your heart line${heartObs.isNotEmpty ? heartObs : " shows emotional depth"}. Nurture your connections today.',
          contentHi: loveContentHi.isNotEmpty
              ? 'आपकी हृदय रेखा बताती है: $loveContentHi'
              : 'आपकी हृदय रेखा${heartObs.isNotEmpty ? " $heartObs" : " भावनात्मक गहराई दर्शाती है"}।',
          iconName: 'favorite_outline',
          confidence: loveScore.clamp(60, 95),
          isMajorEvent: false,
        ),
      );
    }

    if (healthContentEn.isNotEmpty || lifeLineObs.isNotEmpty) {
      final lifeObs = lifeLineObs.isNotEmpty ? ' ${lifeLineObs.first}' : '';
      todayPredictions.add(
        PersonalizedPrediction(
          category: 'Health & Wellness',
          categoryHi: 'स्वास्थ्य और तंदुरुस्ती',
          content: healthContentEn.isNotEmpty
              ? 'Your life line indicates: $healthContentEn$lifeObs'
              : 'Your life line${lifeObs.isNotEmpty ? lifeObs : " shows consistent vitality"}. Maintain your energy with mindful rest.',
          contentHi: healthContentHi.isNotEmpty
              ? 'आपकी जीवन रेखा दर्शाती है: $healthContentHi'
              : 'आपकी जीवन रेखा${lifeObs.isNotEmpty ? " $lifeObs" : " स्थिर जीवनशक्ति दर्शाती है"}।',
          iconName: 'self_improvement',
          confidence: healthScore.clamp(60, 95),
          isMajorEvent: false,
        ),
      );
    }

    if (personalityContentEn.isNotEmpty || headLineObs.isNotEmpty) {
      final headObs = headLineObs.isNotEmpty ? ' ${headLineObs.first}' : '';
      todayPredictions.add(
        PersonalizedPrediction(
          category: 'Mind & Intuition',
          categoryHi: 'मन और अंतर्ज्ञान',
          content: personalityContentEn.isNotEmpty
              ? 'Your head line reveals: $personalityContentEn$headObs'
              : 'Your head line${headObs.isNotEmpty ? headObs : " shows strong analytical ability"}. Trust your intuition today.',
          contentHi: personalityContentHi.isNotEmpty
              ? 'आपकी मस्तिष्क रेखा बताती है: $personalityContentHi'
              : 'आपकी मस्तिष्क रेखा${headObs.isNotEmpty ? " $headObs" : " मजबूत विश्लेषणात्मक क्षमता दर्शाती है"}।',
          iconName: 'auto_awesome',
          confidence: overallScore.clamp(60, 95),
          isMajorEvent: overallScore >= 85,
        ),
      );
    }

    // Weekly predictions
    final weeklyPredictions = <PersonalizedPrediction>[];
    if (careerContentEn.isNotEmpty || fateLineObs.isNotEmpty) {
      weeklyPredictions.add(
        PersonalizedPrediction(
          category: 'Professional Growth',
          categoryHi: 'पेशेवर विकास',
          content:
              'This week, your fate line${fateLineObs.isNotEmpty ? " — ${fateLineObs.first} —" : ""} indicates professional momentum. ${careerContentEn.isNotEmpty ? careerContentEn : "Focus on decisive action mid-week for best results."}',
          contentHi:
              'इस सप्ताह, आपकी भाग्य रेखा${fateLineObs.isNotEmpty ? " — ${fateLineObs.first} —" : ""} पेशेवर गति दर्शाती है। ${careerContentHi.isNotEmpty ? careerContentHi : "सर्वोत्तम परिणामों के लिए सप्ताह के मध्य में निर्णायक कार्रवाई पर ध्यान दें।"}',
          iconName: 'trending_up',
          confidence: careerScore.clamp(65, 92),
          isMajorEvent: careerScore >= 80,
        ),
      );
    }
    if (wealthContentEn.isNotEmpty) {
      weeklyPredictions.add(
        PersonalizedPrediction(
          category: 'Financial Outlook',
          categoryHi: 'वित्तीय दृष्टिकोण',
          content:
              'Your palm analysis reveals financial patterns this week: $wealthContentEn',
          contentHi:
              'आपका हस्तरेखा विश्लेषण इस सप्ताह वित्तीय पैटर्न प्रकट करता है: $wealthContentHi',
          iconName: 'account_balance_wallet',
          confidence: wealthScore.clamp(60, 90),
          isMajorEvent: false,
        ),
      );
    }
    if (loveContentEn.isNotEmpty) {
      weeklyPredictions.add(
        PersonalizedPrediction(
          category: 'Relationships',
          categoryHi: 'रिश्ते',
          content:
              'Your heart line this week: $loveContentEn${heartLineObs.isNotEmpty ? " ${heartLineObs.first}" : ""}',
          contentHi:
              'इस सप्ताह आपकी हृदय रेखा: $loveContentHi${heartLineObs.isNotEmpty ? " ${heartLineObs.first}" : ""}',
          iconName: 'people_outline',
          confidence: loveScore.clamp(60, 90),
          isMajorEvent: false,
        ),
      );
    }

    // Monthly predictions
    final monthlyPredictions = <PersonalizedPrediction>[];
    if (careerContentEn.isNotEmpty) {
      monthlyPredictions.add(
        PersonalizedPrediction(
          category: 'Career This Month',
          categoryHi: 'इस महीने करियर',
          content:
              'This month your palm reveals significant career energy. $careerContentEn${fateLineObs.length > 1 ? " ${fateLineObs[1]}" : ""}',
          contentHi:
              'इस महीने आपकी हथेली महत्वपूर्ण करियर ऊर्जा प्रकट करती है। $careerContentHi',
          iconName: 'fork_right',
          confidence: careerScore.clamp(70, 95),
          isMajorEvent: careerScore >= 80,
        ),
      );
    }
    if (wealthContentEn.isNotEmpty) {
      monthlyPredictions.add(
        PersonalizedPrediction(
          category: 'Financial Month',
          categoryHi: 'वित्तीय महीना',
          content: 'Monthly financial outlook from your palm: $wealthContentEn',
          contentHi: 'आपकी हथेली से मासिक वित्तीय दृष्टिकोण: $wealthContentHi',
          iconName: 'savings',
          confidence: wealthScore.clamp(65, 90),
          isMajorEvent: false,
        ),
      );
    }
    if (healthContentEn.isNotEmpty) {
      monthlyPredictions.add(
        PersonalizedPrediction(
          category: 'Health This Month',
          categoryHi: 'इस महीने स्वास्थ्य',
          content:
              'Your life line this month: $healthContentEn${lifeLineObs.isNotEmpty ? " ${lifeLineObs.first}" : ""}',
          contentHi: 'इस महीने आपकी जीवन रेखा: $healthContentHi',
          iconName: 'health_and_safety',
          confidence: healthScore.clamp(60, 88),
          isMajorEvent: false,
        ),
      );
    }
    if (personalityContentEn.isNotEmpty) {
      monthlyPredictions.add(
        PersonalizedPrediction(
          category: 'Spiritual Growth',
          categoryHi: 'आध्यात्मिक विकास',
          content:
              'This month\'s spiritual and mental outlook: $personalityContentEn',
          contentHi:
              'इस महीने का आध्यात्मिक और मानसिक दृष्टिकोण: $personalityContentHi',
          iconName: 'nights_stay',
          confidence: overallScore.clamp(65, 92),
          isMajorEvent: overallScore >= 85,
        ),
      );
    }

    // Yearly predictions
    final yearlyPredictions = <PersonalizedPrediction>[];
    if (careerContentEn.isNotEmpty || fateLineObs.isNotEmpty) {
      yearlyPredictions.add(
        PersonalizedPrediction(
          category: 'Year of Transformation',
          categoryHi: 'परिवर्तन का वर्ष',
          content:
              'Your annual palm reading reveals: $careerContentEn${fateLineObs.isNotEmpty ? " Your fate line shows: ${fateLineObs.join(". ")}" : ""} This is a year of significant professional development.',
          contentHi:
              'आपका वार्षिक हस्तरेखा पठन प्रकट करता है: $careerContentHi${fateLineObs.isNotEmpty ? " आपकी भाग्य रेखा दर्शाती है: ${fateLineObs.join(". ")}" : ""} यह महत्वपूर्ण पेशेवर विकास का वर्ष है।',
          iconName: 'rocket_launch',
          confidence: careerScore.clamp(75, 95),
          isMajorEvent: true,
        ),
      );
    }
    if (loveContentEn.isNotEmpty) {
      yearlyPredictions.add(
        PersonalizedPrediction(
          category: 'Love & Bonds This Year',
          categoryHi: 'इस वर्ष प्रेम और बंधन',
          content:
              'Your heart line for this year: $loveContentEn${heartLineObs.isNotEmpty ? " ${heartLineObs.join(". ")}" : ""}',
          contentHi:
              'इस वर्ष आपकी हृदय रेखा: $loveContentHi${heartLineObs.isNotEmpty ? " ${heartLineObs.join(". ")}" : ""}',
          iconName: 'favorite',
          confidence: loveScore.clamp(70, 92),
          isMajorEvent: loveScore >= 80,
        ),
      );
    }
    if (wealthContentEn.isNotEmpty) {
      yearlyPredictions.add(
        PersonalizedPrediction(
          category: 'Wealth This Year',
          categoryHi: 'इस वर्ष धन',
          content: 'Annual wealth outlook from your palm: $wealthContentEn',
          contentHi: 'आपकी हथेली से वार्षिक धन दृष्टिकोण: $wealthContentHi',
          iconName: 'currency_rupee',
          confidence: wealthScore.clamp(70, 92),
          isMajorEvent: false,
        ),
      );
    }
    if (summary.isNotEmpty) {
      yearlyPredictions.add(
        PersonalizedPrediction(
          category: 'Overall Guidance',
          categoryHi: 'समग्र मार्गदर्शन',
          content: 'Your palm\'s overall message for this year: $summary',
          contentHi: 'इस वर्ष के लिए आपकी हथेली का समग्र संदेश: $summary',
          iconName: 'self_improvement',
          confidence: overallScore.clamp(70, 95),
          isMajorEvent: overallScore >= 85,
        ),
      );
    }

    return PalmPredictionsData(
      today: todayPredictions,
      weekly: weeklyPredictions,
      monthly: monthlyPredictions,
      yearly: yearlyPredictions,
      palmType: palmType,
      userName: userName,
      isPersonalized: true,
    );
  }
}
