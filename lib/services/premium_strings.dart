
/// HastVeda Premium Strings — English & Hindi
/// All premium UI text goes through this class.
/// Never hard-code premium strings in widgets.
class PremiumStrings {
  final String locale;

  const PremiumStrings({this.locale = 'en'});

  bool get _isHindi => locale == 'hi' || locale == 'HI';

  // ============================================================
  // PAYWALL
  // ============================================================

  String get paywallHeadline => _isHindi
      ? 'अपनी पूरी हस्तरेखा कहानी खोलें'
      : 'Unlock Your Complete Palm Story';

  String get paywallSubtitle => _isHindi
      ? 'बुनियादी पठन से आगे जाएं — व्यक्तित्व, रिश्ते, करियर, धन और भविष्य की गहरी अंतर्दृष्टि पाएं।'
      : 'Go beyond the basic reading with deeper insights into your personality, relationships, career, wealth and future tendencies.';

  String get paywallCta => _isHindi ? 'प्रीमियम अनलॉक करें' : 'Unlock Premium';

  String get paywallRestorePurchases =>
      _isHindi ? 'खरीदारी पुनर्स्थापित करें' : 'Restore Purchases';

  String get paywallBillingNote => _isHindi
      ? 'Google Play Billing जल्द आ रहा है'
      : 'Google Play Billing coming soon';

  String get paywallMonthlyLabel => _isHindi ? 'मासिक' : 'Monthly';
  String get paywallYearlyLabel => _isHindi ? 'वार्षिक' : 'Yearly';
  String get paywallBestValue => _isHindi ? 'सर्वोत्तम मूल्य' : 'Best Value';

  /// Launch offer price — shown as the current price
  String get paywallLaunchPrice => '₹199';

  /// Regular/strikethrough price — shown as the original value
  String get paywallRegularPrice => '₹299';

  /// Legacy fields kept for any remaining references — now point to launch pricing
  String get paywallMonthlyPrice => '₹199';
  String get paywallYearlyPrice => '₹199';

  String get paywallSaveLabel => _isHindi ? 'लॉन्च ऑफर' : 'Launch Offer';

  String get paywallLaunchOfferLabel => _isHindi ? 'लॉन्च ऑफर' : 'Launch Offer';

  String get paywallRegularPriceLabel =>
      _isHindi ? 'नियमित मूल्य' : 'Regular Price';

  // ============================================================
  // BENEFIT LABELS
  // ============================================================

  String get benefitLove =>
      _isHindi ? 'प्रेम और रिश्ते' : 'Love & Relationships';
  String get benefitWealth => _isHindi ? 'धन और वित्त' : 'Wealth & Finances';
  String get benefitCareer =>
      _isHindi ? 'करियर और व्यवसाय' : 'Career & Business';
  String get benefitPersonality => _isHindi ? 'व्यक्तित्व' : 'Personality';
  String get benefitPalmLines =>
      _isHindi ? 'विस्तृत हस्तरेखाएं' : 'Detailed Palm Lines';
  String get benefitMarriage =>
      _isHindi ? 'विवाह संकेतक' : 'Marriage Indicators';
  String get benefitFuture =>
      _isHindi ? 'भविष्य की प्रवृत्तियां' : 'Future Tendencies';
  String get benefitPredictions =>
      _isHindi ? 'व्यक्तिगत भविष्यवाणियां' : 'Personalized Predictions';
  String get benefitReports =>
      _isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Reports';
  String get benefitHistory =>
      _isHindi ? 'विस्तारित इतिहास' : 'Extended Reading History';

  // ============================================================
  // PREMIUM STATUS
  // ============================================================

  String get premiumActive =>
      _isHindi ? '✓ प्रीमियम सक्रिय' : '✓ Premium Active';
  String get freePlan => _isHindi ? 'निःशुल्क योजना' : 'Free Plan';
  String get explorePremium =>
      _isHindi ? 'प्रीमियम एक्सप्लोर करें' : 'Explore Premium';
  String get premiumBadge => _isHindi ? 'प्रीमियम' : 'Premium';

  String expiresOn(String date) =>
      _isHindi ? 'समाप्ति: $date' : 'Expires: $date';

  // ============================================================
  // FEATURE LOCK
  // ============================================================

  String get premiumFeatureLabel =>
      _isHindi ? '🔒 प्रीमियम फ़ीचर' : '🔒 Premium Feature';

  String get unlockPremiumCta =>
      _isHindi ? 'प्रीमियम अनलॉक करें' : 'Unlock Premium';

  String get featureLockGenericTitle =>
      _isHindi ? 'प्रीमियम फ़ीचर' : 'Premium Feature';

  String get featureLockGenericSubtitle => _isHindi
      ? 'यह फ़ीचर प्रीमियम सदस्यों के लिए उपलब्ध है।'
      : 'This feature is available for Premium members.';

  // Feature-specific lock messages
  String featureLockTitle(String feature) {
    switch (feature) {
      case 'detailed_fate_line':
        return _isHindi ? 'भाग्य रेखा विश्लेषण' : 'Fate Line Analysis';
      case 'detailed_heart_line':
        return _isHindi ? 'हृदय रेखा विश्लेषण' : 'Heart Line Analysis';
      case 'detailed_head_line':
        return _isHindi ? 'मस्तिष्क रेखा विश्लेषण' : 'Head Line Analysis';
      case 'detailed_life_line':
        return _isHindi ? 'जीवन रेखा विश्लेषण' : 'Life Line Analysis';
      case 'detailed_sun_line':
      case 'sun_line':
        return _isHindi ? 'सूर्य रेखा विश्लेषण' : 'Sun Line Analysis';
      case 'mercury_line':
        return _isHindi ? 'बुध रेखा विश्लेषण' : 'Mercury Line Analysis';
      case 'marriage_indicators':
        return _isHindi ? 'विवाह संकेतक' : 'Marriage Indicators';
      case 'mount_analysis':
        return _isHindi ? 'पर्वत विश्लेषण' : 'Mount Analysis';
      case 'love_relationships':
        return _isHindi ? 'प्रेम और रिश्ते' : 'Love & Relationships';
      case 'wealth_finances':
        return _isHindi ? 'धन और वित्त' : 'Wealth & Finances';
      case 'career_business':
        return _isHindi ? 'करियर और व्यवसाय' : 'Career & Business';
      case 'future_tendencies':
        return _isHindi ? 'भविष्य की प्रवृत्तियां' : 'Future Tendencies';
      case 'detailed_predictions':
      case 'deep_predictions':
        return _isHindi
            ? 'गहन भविष्य और भविष्यवाणियां'
            : 'Deep Future & Predictions';
      case 'palm_marks':
        return _isHindi ? 'हस्त चिह्न और संकेत' : 'Palm Marks & Signs';
      case 'detailed_strengths':
        return _isHindi
            ? 'विस्तृत शक्तियां और कमजोरियां'
            : 'Detailed Strengths & Weaknesses';
      case 'remedies_guidance':
        return _isHindi ? 'उपाय और मार्गदर्शन' : 'Remedies & Guidance';
      case 'advanced_analysis':
        return _isHindi
            ? 'उन्नत व्यक्तिगत विश्लेषण'
            : 'Advanced Personalized Analysis';
      case 'ask_hastveda':
        return _isHindi ? 'HastVeda से पूछें' : 'Ask HastVeda';
      case 'extended_history':
        return _isHindi ? 'विस्तारित इतिहास' : 'Extended History';
      case 'detailed_reports':
        return _isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Reports';
      case 'complete_reading':
        return _isHindi ? 'पूर्ण पठन' : 'Complete Reading';
      case 'couple_reading':
        return _isHindi ? 'युगल पठन' : 'Couple Reading';
      case 'detailed_report':
        return _isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Report';
      default:
        return featureLockGenericTitle;
    }
  }

  String featureLockDescription(String feature) {
    switch (feature) {
      case 'detailed_fate_line':
        return _isHindi
            ? 'आपकी भाग्य रेखा करियर दिशा और जीवन के प्रमुख बदलावों से जुड़े महत्वपूर्ण पैटर्न प्रकट करती है।'
            : 'Your Fate Line reveals important patterns related to career direction and major life transitions.';
      case 'detailed_heart_line':
        return _isHindi
            ? 'आपकी हृदय रेखा आपकी भावनात्मक प्रकृति, प्रेम जीवन और रिश्तों की गहराई दर्शाती है।'
            : 'Your Heart Line reveals your emotional nature, love life, and depth of relationships.';
      case 'detailed_head_line':
        return _isHindi
            ? 'आपकी मस्तिष्क रेखा आपकी बौद्धिक क्षमता, निर्णय लेने की शैली और मानसिक शक्ति दर्शाती है।'
            : 'Your Head Line reveals your intellectual capacity, decision-making style, and mental strengths.';
      case 'detailed_life_line':
        return _isHindi
            ? 'आपकी जीवन रेखा आपकी जीवन शक्ति, स्वास्थ्य और जीवन की प्रमुख घटनाओं का विस्तृत विश्लेषण प्रदान करती है।'
            : 'Your Life Line provides a detailed analysis of your vitality, health, and major life events.';
      case 'marriage_indicators':
        return _isHindi
            ? 'विवाह रेखाएं और संकेतक आपके प्रेम जीवन और विवाह के बारे में गहरी अंतर्दृष्टि प्रदान करते हैं।'
            : 'Marriage lines and indicators provide deep insights into your love life and partnerships.';
      case 'love_relationships':
        return _isHindi
            ? 'आपके हाथ में प्रेम, रिश्ते और भावनात्मक जीवन के बारे में विस्तृत अंतर्दृष्टि।'
            : 'Detailed insights about love, relationships, and emotional life from your palm.';
      case 'wealth_finances':
        return _isHindi
            ? 'आपके हाथ में धन, वित्तीय सफलता और समृद्धि के संकेत।'
            : 'Signs of wealth, financial success, and prosperity in your palm.';
      case 'career_business':
        return _isHindi
            ? 'करियर की दिशा, व्यावसायिक सफलता और पेशेवर विकास के संकेत।'
            : 'Career direction, business success, and professional growth indicators.';
      case 'detailed_predictions':
        return _isHindi
            ? 'AI-संचालित विस्तृत, व्यक्तिगत भविष्यवाणियां आपकी हस्तरेखा पर आधारित।'
            : 'AI-powered detailed, personalized predictions based on your palm reading.';
      case 'extended_history':
        return _isHindi
            ? 'अपने सभी पिछले पठन और भविष्यवाणियों का पूरा इतिहास देखें।'
            : 'View your complete history of all past readings and predictions.';
      default:
        return featureLockGenericSubtitle;
    }
  }

  String featureLockCta(String feature) {
    switch (feature) {
      case 'complete_reading':
        return _isHindi ? 'पूर्ण पठन अनलॉक करें' : 'Unlock Complete Reading';
      case 'couple_reading':
        return _isHindi ? 'युगल पठन अनलॉक करें' : 'Unlock Couple Reading';
      case 'detailed_report':
        return _isHindi
            ? 'विस्तृत रिपोर्ट अनलॉक करें'
            : 'Unlock Detailed Report';
      default:
        return unlockPremiumCta;
    }
  }

  // ============================================================
  // FREE TIER LIMITS
  // ============================================================

  String get freeLimitReached => _isHindi
      ? 'आपने अपनी निःशुल्क सीमा पूरी कर ली है।'
      : 'You\'ve reached your free reading limit.';

  String get freeLimitScanTitle =>
      _isHindi ? 'मासिक स्कैन सीमा पूरी हुई' : 'Monthly Scan Limit Reached';

  String freeLimitScanMessage(int limit) => _isHindi
      ? 'आप प्रति माह $limit स्कैन कर सकते हैं। अधिक स्कैन के लिए प्रीमियम अपग्रेड करें।'
      : 'You can scan $limit times per month. Upgrade to Premium for unlimited scans.';

  String get freeLimitPredictionsTitle =>
      _isHindi ? 'भविष्यवाणी सीमा' : 'Prediction Limit';

  String freeLimitPredictionsMessage(int limit) => _isHindi
      ? 'निःशुल्क उपयोगकर्ता $limit भविष्यवाणियां देख सकते हैं। सभी के लिए प्रीमियम अपग्रेड करें।'
      : 'Free users can view $limit predictions. Upgrade to Premium to see all.';

  String get freeLimitHistoryTitle =>
      _isHindi ? 'इतिहास सीमा' : 'History Limit';

  String freeLimitHistoryMessage(int days) => _isHindi
      ? 'निःशुल्क उपयोगकर्ता $days दिनों का इतिहास देख सकते हैं। पूरे इतिहास के लिए प्रीमियम अपग्रेड करें।'
      : 'Free users can view $days days of history. Upgrade to Premium for full history.';

  String get upgradeToPremiumBenefits => _isHindi
      ? 'प्रीमियम के साथ असीमित स्कैन, विस्तृत विश्लेषण और बहुत कुछ पाएं।'
      : 'Get unlimited scans, detailed analysis, and much more with Premium.';
}
