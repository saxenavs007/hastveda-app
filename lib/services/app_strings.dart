// HastVeda Centralized Translations
// Supports: English (en), Hindi (hi), Hinglish (hi-Latn)

class AppStrings {
  final String languageCode;
  const AppStrings._(this.languageCode);

  static const AppStrings en = AppStrings._('en');
  static const AppStrings hi = AppStrings._('hi');
  static const AppStrings hiLatn = AppStrings._('hi-Latn');

  static AppStrings of(String code) {
    switch (code) {
      case 'hi':
        return hi;
      case 'hi-Latn':
        return hiLatn;
      default:
        return en;
    }
  }

  // ── App ──────────────────────────────────────────────────────────────────
  String get appName => _s('HastVeda', 'HastVeda', 'HastVeda');
  String get tagline => _s(
    'Your Palm Journey Awaits',
    'आपकी हथेली की यात्रा शुरू होती है',
    'Aapki palm journey shuru hoti hai',
  );
  String get ancientWisdom => _s(
    'Ancient Wisdom · Modern Insight',
    'प्राचीन ज्ञान · आधुनिक अंतर्दृष्टि',
    'Prachin Gyan · Modern Insight',
  );

  // ── Navigation ───────────────────────────────────────────────────────────
  String get home => _s('Home', 'होम', 'Home');
  String get scan => _s('Scan', 'स्कैन', 'Scan');
  String get readings => _s('Readings', 'पठन', 'Readings');
  String get couple => _s('Couple', 'जोड़ी', 'Couple');
  String get premium => _s('Premium', 'प्रीमियम', 'Premium');
  String get profile => _s('Profile', 'प्रोफ़ाइल', 'Profile');

  // ── Authentication ───────────────────────────────────────────────────────
  String get signIn => _s('Sign In', 'साइन इन', 'Sign In');
  String get signUp => _s('Sign Up', 'साइन अप', 'Sign Up');
  String get email => _s('Email', 'ईमेल', 'Email');
  String get password => _s('Password', 'पासवर्ड', 'Password');
  String get confirmPassword => _s(
    'Confirm Password',
    'पासवर्ड की पुष्टि करें',
    'Password confirm karein',
  );
  String get fullName => _s('Full Name', 'पूरा नाम', 'Full Name');
  String get continueAsGuest => _s(
    'Continue as Guest',
    'अतिथि के रूप में जारी रखें',
    'Guest ke roop mein continue karein',
  );
  String get forgotPassword =>
      _s('Forgot Password?', 'पासवर्ड भूल गए?', 'Password bhool gaye?');
  String get createAccount =>
      _s('Create Account', 'खाता बनाएं', 'Account banayein');
  String get alreadyHaveAccount => _s(
    'Already have an account?',
    'पहले से खाता है?',
    'Pehle se account hai?',
  );
  String get dontHaveAccount =>
      _s("Don't have an account?", 'खाता नहीं है?', 'Account nahi hai?');
  String get signInWithGoogle => _s(
    'Sign in with Google',
    'Google से साइन इन करें',
    'Google se sign in karein',
  );
  String get orContinueWith =>
      _s('or continue with', 'या जारी रखें', 'ya continue karein');
  String get enterEmail =>
      _s('Enter your email', 'अपना ईमेल दर्ज करें', 'Apna email daalen');
  String get enterPassword => _s(
    'Enter your password',
    'अपना पासवर्ड दर्ज करें',
    'Apna password daalen',
  );
  String get enterName => _s(
    'Enter your full name',
    'अपना पूरा नाम दर्ज करें',
    'Apna full name daalen',
  );
  String get enterConfirmPassword => _s(
    'Confirm your password',
    'पासवर्ड की पुष्टि करें',
    'Password confirm karein',
  );
  String get signInFailed => _s(
    'Sign in failed. Please try again.',
    'साइन इन विफल। कृपया पुनः प्रयास करें।',
    'Sign in fail hua. Please dobara try karein.',
  );
  String get signUpFailed => _s(
    'Sign up failed. Please try again.',
    'साइन अप विफल। कृपया पुनः प्रयास करें।',
    'Sign up fail hua. Please dobara try karein.',
  );
  String get fillAllFields => _s(
    'Please fill in all fields.',
    'कृपया सभी फ़ील्ड भरें।',
    'Please sabhi fields bharein.',
  );
  String get passwordsDoNotMatch => _s(
    'Passwords do not match.',
    'पासवर्ड मेल नहीं खाते।',
    'Passwords match nahi kar rahe.',
  );
  String get passwordTooShort => _s(
    'Password must be at least 6 characters.',
    'पासवर्ड कम से कम 6 अक्षर का होना चाहिए।',
    'Password kam se kam 6 characters ka hona chahiye.',
  );
  String get enterEmailAndPassword => _s(
    'Please enter your email and password.',
    'कृपया अपना ईमेल और पासवर्ड दर्ज करें।',
    'Please apna email aur password daalen.',
  );
  String get offlineAuthError => _s(
    'No internet connection. Please connect to sign in.',
    'इंटरनेट कनेक्शन नहीं है। साइन इन करने के लिए कनेक्ट करें।',
    'Internet connection nahi hai. Sign in ke liye connect karein.',
  );

  // ── Home ─────────────────────────────────────────────────────────────────
  String get goodMorning => _s('Good Morning', 'सुप्रभात', 'Good Morning');
  String get goodAfternoon =>
      _s('Good Afternoon', 'शुभ दोपहर', 'Good Afternoon');
  String get goodEvening => _s('Good Evening', 'शुभ संध्या', 'Good Evening');
  String get todaysReading =>
      _s("Today's Reading", 'आज का पठन', "Aaj ka Reading");
  String get todaysHighlight =>
      _s("Today's Highlight", 'आज की मुख्य बात', "Aaj ki Highlight");
  String get recentReadings =>
      _s('Recent Readings', 'हाल के पठन', 'Recent Readings');
  String get scanYourPalm =>
      _s('Scan Your Palm', 'अपनी हथेली स्कैन करें', 'Apna Palm Scan karein');
  String get explorePremium =>
      _s('Explore Premium', 'प्रीमियम देखें', 'Premium dekhein');
  String get yourPalmJourney => _s(
    'Your Palm Journey Starts Here',
    'आपकी हथेली की यात्रा यहाँ शुरू होती है',
    'Aapki Palm Journey yahan se shuru hoti hai',
  );
  String get noReadingsYet =>
      _s('No readings yet', 'अभी तक कोई पठन नहीं', 'Abhi tak koi reading nahi');
  String get startFirstScan => _s(
    'Start your first palm scan to begin your journey',
    'अपनी यात्रा शुरू करने के लिए पहला हथेली स्कैन करें',
    'Apni journey shuru karne ke liye pehla palm scan karein',
  );
  String get viewAll => _s('View All', 'सभी देखें', 'Sab dekhein');
  String get premiumFeatures =>
      _s('Premium Features', 'प्रीमियम सुविधाएं', 'Premium Features');
  String get coupleReading =>
      _s('Couple Reading', 'जोड़ी पठन', 'Couple Reading');
  String get detailedReport =>
      _s('Detailed Report', 'विस्तृत रिपोर्ट', 'Detailed Report');
  String get history => _s('History', 'इतिहास', 'History');
  String get explorer => _s('Guest', 'अतिथि', 'Guest');

  // ── Palm Scan ────────────────────────────────────────────────────────────
  String get palmScan => _s('Palm Scan', 'हथेली स्कैन', 'Palm Scan');
  String get capturePalm =>
      _s('Capture Palm', 'हथेली कैप्चर करें', 'Palm capture karein');
  String get scanAgain =>
      _s('Scan Again', 'फिर से स्कैन करें', 'Dobara scan karein');
  String get processing =>
      _s('Processing...', 'प्रक्रिया हो रही है...', 'Processing...');
  String get analysisComplete =>
      _s('Analysis Complete', 'विश्लेषण पूर्ण', 'Analysis complete');
  String get positionPalm => _s(
    'Position your palm within the frame',
    'अपनी हथेली को फ्रेम में रखें',
    'Apna palm frame mein rakhein',
  );
  String get holdSteady => _s(
    'Hold steady for best results',
    'सर्वोत्तम परिणाम के लिए स्थिर रहें',
    'Best results ke liye steady rahein',
  );
  String get cameraPermission => _s(
    'Camera permission required',
    'कैमरा अनुमति आवश्यक है',
    'Camera permission chahiye',
  );
  String get unableToScan =>
      _s('Unable to scan', 'स्कैन करने में असमर्थ', 'Scan nahi ho pa raha');
  String get palmNotDetected =>
      _s('Palm not detected', 'हथेली नहीं मिली', 'Palm detect nahi hua');
  String get tryAgain =>
      _s('Try Again', 'पुनः प्रयास करें', 'Dobara try karein');
  String get analyzing => _s(
    'Analyzing your palm...',
    'आपकी हथेली का विश्लेषण हो रहा है...',
    'Aapka palm analyze ho raha hai...',
  );
  String get uploadFromGallery => _s(
    'Upload from Gallery',
    'गैलरी से अपलोड करें',
    'Gallery se upload karein',
  );
  String get takePhoto => _s('Take Photo', 'फ़ोटो लें', 'Photo lein');
  String get demoMode => _s('Demo Mode', 'डेमो मोड', 'Demo Mode');
  String get useDemoImage =>
      _s('Use Demo Image', 'डेमो छवि उपयोग करें', 'Demo image use karein');
  String get unableToCompleteScan => _s(
    'Unable to complete the palm scan.',
    'हथेली स्कैन पूरा करने में असमर्थ।',
    'Palm scan complete nahi ho pa raha.',
  );
  String get aiServiceBusy => _s(
    'The AI service is busy right now.\n\nThis usually clears in a moment — please try again.',
    'AI सेवा अभी व्यस्त है।\n\nयह आमतौर पर कुछ ही क्षणों में ठीक हो जाता है — कृपया पुनः प्रयास करें।',
    'AI service abhi busy hai.\n\nThodi der mein theek ho jayega — please dobara try karein.',
  );
  String get imageUploadProblem => _s(
    "We couldn't process your palm photo.\n\nPlease try capturing it again.",
    'हम आपकी हथेली की फ़ोटो संसाधित नहीं कर सके।\n\nकृपया इसे दोबारा कैप्चर करें।',
    'Aapki palm photo process nahi ho payi.\n\nPlease dobara capture karein.',
  );
  String get analysisIncomplete => _s(
    'The analysis was cut short.\n\nPlease try again.',
    'विश्लेषण अधूरा रह गया।\n\nकृपया पुनः प्रयास करें।',
    'Analysis adhoora reh gaya.\n\nPlease dobara try karein.',
  );

  // ── Account required for palm scanning ──────────────────────────────────────
  String get accountRequiredTitle =>
      _s('Account Required', 'खाता आवश्यक है', 'Account chahiye');
  String get accountRequiredForScan => _s(
    'Please create an account or sign in to scan your palm. Your reading is saved to your account so you can revisit it anytime.',
    'हथेली स्कैन करने के लिए कृपया खाता बनाएं या साइन इन करें। आपका पठन आपके खाते में सहेजा जाता है ताकि आप इसे कभी भी देख सकें।',
    'Palm scan ke liye please account banayein ya sign in karein. Aapki reading aapke account mein save hoti hai.',
  );
  String get scanRequiresAccountHint => _s(
    'Palm scanning requires an account',
    'हथेली स्कैन के लिए खाता आवश्यक है',
    'Palm scan ke liye account chahiye',
  );

  // ── Free tier scan limit ────────────────────────────────────────────────────
  String get freeScanLimitTitle => _s(
    'Monthly Limit Reached',
    'मासिक सीमा पूरी हो गई',
    'Monthly limit poori ho gayi',
  );
  String freeScanLimitReached(int limit) => _s(
    'You have used all $limit palm scans for this month. Normal accounts can scan 2 times a month. Premium accounts can scan 5 times a month. Your allowance resets next month.',
    'आपने इस महीने के सभी $limit हथेली स्कैन उपयोग कर लिए हैं। सामान्य खाते महीने में 2 बार और प्रीमियम खाते 5 बार स्कैन कर सकते हैं। सीमा अगले महीने फिर से शुरू होगी।',
    'Aapne is mahine ke saare $limit palm scans use kar liye hain. Normal account mahine mein 2 baar aur Premium 5 baar scan kar sakta hai. Limit agle mahine reset hogi.',
  );
  String get signInToContinue => _s(
    'Sign In to Continue',
    'जारी रखने के लिए साइन इन करें',
    'Continue karne ke liye sign in karein',
  );

  // ── Palm Analysis ────────────────────────────────────────────────────────
  String get palmAnalysis =>
      _s('Palm Analysis', 'हथेली विश्लेषण', 'Palm Analysis');
  String get palmProfile =>
      _s('Palm Profile', 'हथेली प्रोफ़ाइल', 'Palm Profile');
  String get lifeLine => _s('Life Line', 'जीवन रेखा', 'Life Line');
  String get heartLine => _s('Heart Line', 'हृदय रेखा', 'Heart Line');
  String get headLine => _s('Head Line', 'मस्तिष्क रेखा', 'Head Line');
  String get fateLine => _s('Fate Line', 'भाग्य रेखा', 'Fate Line');
  String get sunLine =>
      _s('Sun / Success Line', 'सूर्य / सफलता रेखा', 'Sun / Success Line');
  String get mercuryLine => _s('Mercury Line', 'बुध रेखा', 'Mercury Line');
  String get marriageIndicators =>
      _s('Marriage Indicators', 'विवाह संकेतक', 'Marriage Indicators');
  String get mountAnalysis =>
      _s('Mount Analysis', 'पर्वत विश्लेषण', 'Mount Analysis');
  String get palmMarks => _s('Palm Marks', 'हथेली के चिह्न', 'Palm Marks');
  String get personality => _s('Personality', 'व्यक्तित्व', 'Personality');
  String get loveRelationships =>
      _s('Love & Relationships', 'प्रेम और रिश्ते', 'Love & Relationships');
  String get wealthFinances =>
      _s('Wealth & Finances', 'धन और वित्त', 'Wealth & Finances');
  String get careerBusiness =>
      _s('Career & Business', 'करियर और व्यवसाय', 'Career & Business');
  String get futureTendencies =>
      _s('Future Tendencies', 'भविष्य की प्रवृत्तियां', 'Future Tendencies');
  String get aiPalmAnalysis =>
      _s('AI Palm Analysis', 'AI हथेली विश्लेषण', 'AI Palm Analysis');
  String get confidenceScore =>
      _s('Confidence Score', 'विश्वास स्कोर', 'Confidence Score');
  String get viewFullAnalysis =>
      _s('View Full Analysis', 'पूर्ण विश्लेषण देखें', 'Full analysis dekhein');
  String get unableToCompleteAnalysis => _s(
    'Unable to complete the palm analysis.',
    'हथेली विश्लेषण पूरा करने में असमर्थ।',
    'Palm analysis complete nahi ho pa raha.',
  );

  // ── Predictions ──────────────────────────────────────────────────────────
  String get predictions => _s('Predictions', 'भविष्यवाणी', 'Predictions');
  String get daily => _s('Daily', 'दैनिक', 'Daily');
  String get weekly => _s('Weekly', 'साप्ताहिक', 'Weekly');
  String get monthly => _s('Monthly', 'मासिक', 'Monthly');
  String get yearly => _s('Yearly', 'वार्षिक', 'Yearly');
  String get today => _s('Today', 'आज', 'Aaj');
  String get thisWeek => _s('This Week', 'इस सप्ताह', 'Is hafte');
  String get thisMonth => _s('This Month', 'इस महीने', 'Is mahine');
  String get thisYear => _s('This Year', 'इस वर्ष', 'Is saal');
  String get dailyPrediction =>
      _s('Daily Prediction', 'दैनिक भविष्यवाणी', 'Daily Prediction');
  String get weeklyPrediction =>
      _s('Weekly Prediction', 'साप्ताहिक भविष्यवाणी', 'Weekly Prediction');
  String get monthlyPrediction =>
      _s('Monthly Prediction', 'मासिक भविष्यवाणी', 'Monthly Prediction');
  String get yearlyPrediction =>
      _s('Yearly Prediction', 'वार्षिक भविष्यवाणी', 'Yearly Prediction');
  String get loveToday => _s('Love Today', 'आज का प्रेम', 'Aaj ka Love');
  String get careerToday => _s('Career Today', 'आज का करियर', 'Aaj ka Career');
  String get healthToday =>
      _s('Health Today', 'आज का स्वास्थ्य', 'Aaj ki Health');
  String get wealthToday => _s('Wealth Today', 'आज का धन', 'Aaj ka Wealth');

  // ── Premium ──────────────────────────────────────────────────────────────
  String get unlockPremium =>
      _s('Unlock Premium', 'प्रीमियम अनलॉक करें', 'Premium unlock karein');
  String get unlockCompleteStory => _s(
    'Unlock Your Complete Palm Story',
    'अपनी पूरी हथेली की कहानी अनलॉक करें',
    'Apni poori palm story unlock karein',
  );
  String get completeReading =>
      _s('Complete Reading', 'पूर्ण पठन', 'Complete Reading');
  String get premiumFeature =>
      _s('Premium Feature', 'प्रीमियम सुविधा', 'Premium Feature');
  String get premiumRequired =>
      _s('Premium Required', 'प्रीमियम आवश्यक है', 'Premium chahiye');
  String get upgradeToPremium => _s(
    'Upgrade to Premium',
    'प्रीमियम में अपग्रेड करें',
    'Premium mein upgrade karein',
  );
  String get premiumMember =>
      _s('Premium Member', 'प्रीमियम सदस्य', 'Premium Member');
  String get freePlan => _s('Free Plan', 'मुफ़्त योजना', 'Free Plan');
  String get viewPremiumPlans => _s(
    'View Premium Plans',
    'प्रीमियम योजनाएं देखें',
    'Premium plans dekhein',
  );
  String get premiumUnlocked =>
      _s('Premium Unlocked', 'प्रीमियम अनलॉक हो गया', 'Premium unlock ho gaya');
  String get comingSoon =>
      _s('Coming Soon', 'जल्द आ रहा है', 'Jald aa raha hai');
  String get premiumVerificationFailed => _s(
    'Unable to verify Premium status. Please try again.',
    'प्रीमियम स्थिति सत्यापित करने में असमर्थ। कृपया पुनः प्रयास करें।',
    'Premium status verify nahi ho pa raha. Please dobara try karein.',
  );

  // ── Couple Reading ───────────────────────────────────────────────────────
  String get coupleCompatibility =>
      _s('Couple Compatibility', 'जोड़ी अनुकूलता', 'Couple Compatibility');
  String get person1 => _s('Person 1', 'व्यक्ति 1', 'Person 1');
  String get person2 => _s('Person 2', 'व्यक्ति 2', 'Person 2');
  String get generateReading =>
      _s('Generate Reading', 'पठन उत्पन्न करें', 'Reading generate karein');
  String get compatibilityScore =>
      _s('Compatibility Score', 'अनुकूलता स्कोर', 'Compatibility Score');
  String get loveCompatibility =>
      _s('Love Compatibility', 'प्रेम अनुकूलता', 'Love Compatibility');
  String get emotionalCompatibility => _s(
    'Emotional Compatibility',
    'भावनात्मक अनुकूलता',
    'Emotional Compatibility',
  );
  String get communicationCompatibility =>
      _s('Communication', 'संचार', 'Communication');
  String get financialCompatibility => _s(
    'Financial Compatibility',
    'वित्तीय अनुकूलता',
    'Financial Compatibility',
  );
  String get careerCompatibility =>
      _s('Career & Lifestyle', 'करियर और जीवनशैली', 'Career & Lifestyle');
  String get marriageIndicatorsLabel =>
      _s('Marriage Indicators', 'विवाह संकेतक', 'Marriage Indicators');
  String get strengthsTogether =>
      _s('Strengths Together', 'साथ में शक्तियां', 'Saath mein Strengths');
  String get challengesTogether =>
      _s('Potential Challenges', 'संभावित चुनौतियां', 'Potential Challenges');
  String get growthTogether =>
      _s('Growth Together', 'साथ में विकास', 'Saath mein Growth');
  String get futureTendenciesCouple =>
      _s('Future Tendencies', 'भविष्य की प्रवृत्तियां', 'Future Tendencies');
  String get overallCompatibility =>
      _s('Overall Compatibility', 'कुल अनुकूलता', 'Overall Compatibility');
  String get scanPalmForPerson => _s(
    'Scan palm for this person',
    'इस व्यक्ति के लिए हथेली स्कैन करें',
    'Is person ke liye palm scan karein',
  );
  String get enterPersonName =>
      _s('Enter name', 'नाम दर्ज करें', 'Naam daalen');
  String get coupleReadingFailed => _s(
    'Unable to complete the couple reading.',
    'जोड़ी पठन पूरा करने में असमर्थ।',
    'Couple reading complete nahi ho pa raha.',
  );

  // ── Reports ──────────────────────────────────────────────────────────────
  String get detailedReportTitle =>
      _s('Detailed Report', 'विस्तृत रिपोर्ट', 'Detailed Report');
  String get reportHistory =>
      _s('Report History', 'रिपोर्ट इतिहास', 'Report History');
  String get viewReport => _s('View Report', 'रिपोर्ट देखें', 'Report dekhein');
  String get downloadReport => _s('Download', 'डाउनलोड', 'Download');
  String get shareReport => _s('Share', 'साझा करें', 'Share karein');
  String get generatedOn =>
      _s('Generated On', 'उत्पन्न किया गया', 'Generate kiya gaya');
  String get generateReport =>
      _s('Generate Report', 'रिपोर्ट उत्पन्न करें', 'Report generate karein');
  String get reportType => _s('Report Type', 'रिपोर्ट प्रकार', 'Report Type');
  String get noReportsYet => _s(
    'No reports yet',
    'अभी तक कोई रिपोर्ट नहीं',
    'Abhi tak koi report nahi',
  );
  String get executiveSummary =>
      _s('Executive Summary', 'कार्यकारी सारांश', 'Executive Summary');
  String get personalizedRecommendations => _s(
    'Personalized Recommendations',
    'व्यक्तिगत सिफारिशें',
    'Personalized Recommendations',
  );
  String get pdfComingSoon => _s(
    'PDF export coming soon',
    'PDF निर्यात जल्द आ रहा है',
    'PDF export jald aa raha hai',
  );
  String get unableToLoadReport => _s(
    'Unable to load this report.',
    'यह रिपोर्ट लोड करने में असमर्थ।',
    'Yeh report load nahi ho pa rahi.',
  );
  String get unableToLoadHistory => _s(
    'Unable to load report history.',
    'रिपोर्ट इतिहास लोड करने में असमर्थ।',
    'Report history load nahi ho pa rahi.',
  );

  // ── Settings ─────────────────────────────────────────────────────────────
  String get settings => _s('Settings', 'सेटिंग्स', 'Settings');
  String get language => _s('Language', 'भाषा', 'Language');
  String get theme => _s('Theme', 'थीम', 'Theme');
  String get lightMode => _s('Light', 'लाइट', 'Light');
  String get darkMode => _s('Dark', 'डार्क', 'Dark');
  String get systemDefault =>
      _s('System Default', 'सिस्टम डिफ़ॉल्ट', 'System Default');
  String get notifications => _s('Notifications', 'सूचनाएं', 'Notifications');
  String get pushNotifications =>
      _s('Push Notifications', 'पुश सूचनाएं', 'Push Notifications');
  String get account => _s('Account', 'खाता', 'Account');
  String get privacy => _s('Privacy', 'गोपनीयता', 'Privacy');
  String get terms => _s('Terms', 'नियम', 'Terms');
  String get about => _s('About', 'के बारे में', 'About');
  String get aboutHastVeda =>
      _s('About HastVeda', 'HastVeda के बारे में', 'HastVeda ke baare mein');
  String get privacyPolicy =>
      _s('Privacy Policy', 'गोपनीयता नीति', 'Privacy Policy');
  String get termsConditions =>
      _s('Terms & Conditions', 'नियम और शर्तें', 'Terms & Conditions');
  String get helpSupport =>
      _s('Help & Support', 'सहायता और समर्थन', 'Help & Support');
  String get signOut => _s('Sign Out', 'साइन आउट', 'Sign Out');
  String get preferences => _s('Preferences', 'प्राथमिकताएं', 'Preferences');
  String get appearance => _s('Appearance', 'दिखावट', 'Appearance');
  String get version => _s('Version', 'संस्करण', 'Version');

  // ── Language Selection ────────────────────────────────────────────────────
  String get selectLanguage =>
      _s('Select Language', 'भाषा चुनें', 'Language chunein');
  String get english => _s('English', 'अंग्रेज़ी', 'English');
  String get hindi => _s('Hindi', 'हिंदी', 'Hindi');
  String get hinglish => _s('Hinglish', 'हिंग्लिश', 'Hinglish');
  String get languageChanged =>
      _s('Language updated', 'भाषा अपडेट की गई', 'Language update ho gayi');

  // ── Profile ───────────────────────────────────────────────────────────────
  String get myProfile => _s('My Profile', 'मेरी प्रोफ़ाइल', 'Meri Profile');
  String get editProfile =>
      _s('Edit Profile', 'प्रोफ़ाइल संपादित करें', 'Profile edit karein');
  String get totalScans => _s('Total Scans', 'कुल स्कैन', 'Total Scans');
  String get memberSince => _s('Member Since', 'सदस्य बने', 'Member bane');
  String get palmReadings => _s('Palm Readings', 'हथेली पठन', 'Palm Readings');
  String get subscription => _s('Subscription', 'सदस्यता', 'Subscription');
  String get accountType => _s('Account Type', 'खाता प्रकार', 'Account Type');
  String get changePassword =>
      _s('Change Password', 'पासवर्ड बदलें', 'Password badlein');
  String get changePasswordDesc => _s(
    'We will send a password reset link to your email address.',
    'हम आपके ईमेल पते पर पासवर्ड रीसेट लिंक भेजेंगे।',
    'Hum aapke email par password reset link bhejenge.',
  );
  String get sendResetLink =>
      _s('Send Reset Link', 'रीसेट लिंक भेजें', 'Reset link bhejein');
  String get passwordResetSent => _s(
    'Password reset email sent. Check your inbox.',
    'पासवर्ड रीसेट ईमेल भेजा गया। अपना इनबॉक्स जांचें।',
    'Password reset email bheja gaya. Apna inbox check karein.',
  );
  String get profileSaved => _s(
    'Profile saved successfully.',
    'प्रोफ़ाइल सफलतापूर्वक सहेजी गई।',
    'Profile successfully save ho gayi.',
  );
  String get signOutConfirm => _s(
    'Are you sure you want to sign out?',
    'क्या आप वाकई साइन आउट करना चाहते हैं?',
    'Kya aap sach mein sign out karna chahte hain?',
  );
  String get deleteAccount =>
      _s('Delete Account', 'खाता हटाएं', 'Account delete karein');
  String get deleteAccountWarning => _s(
    'This will permanently deactivate your account. Your reading history will no longer be accessible.',
    'यह आपके खाते को स्थायी रूप से निष्क्रिय कर देगा। आपका पठन इतिहास अब उपलब्ध नहीं होगा।',
    'Yeh aapka account permanently deactivate kar dega. Aapki reading history accessible nahi rahegi.',
  );
  String get deleteAccountFinal => _s(
    'Are you absolutely sure?',
    'क्या आप बिल्कुल निश्चित हैं?',
    'Kya aap bilkul sure hain?',
  );
  String get deleteAccountFinalWarning => _s(
    'This action cannot be undone. All your data will be permanently deactivated.',
    'यह क्रिया पूर्ववत नहीं की जा सकती। आपका सारा डेटा स्थायी रूप से निष्क्रिय हो जाएगा।',
    'Yeh action undo nahi ho sakta. Aapka saara data permanently deactivate ho jayega.',
  );
  String get deleteAccountConfirm =>
      _s('Yes, Delete', 'हाँ, हटाएं', 'Haan, delete karein');
  String get myReadings => _s('My Readings', 'मेरे पठन', 'Mere Readings');
  String get subscriptionStatus => _s('Status', 'स्थिति', 'Status');
  String get renewalDate => _s('Renewal Date', 'नवीनीकरण तिथि', 'Renewal Date');
  String get autoRenewOn =>
      _s('Auto-renew on', 'स्वतः नवीनीकरण चालू', 'Auto-renew on');
  String get privacyLegal =>
      _s('Privacy & Legal', 'गोपनीयता और कानूनी', 'Privacy & Legal');
  String get aiDisclaimer => _s(
    'AI & Palm Reading Disclaimer',
    'AI और हस्तरेखा अस्वीकरण',
    'AI & Palm Reading Disclaimer',
  );

  // ── Reading History ───────────────────────────────────────────────────────
  String get readingHistory =>
      _s('Reading History', 'पठन इतिहास', 'Reading History');
  String get noReadingsHistory => _s(
    'No reading history yet',
    'अभी तक कोई पठन इतिहास नहीं',
    'Abhi tak koi reading history nahi',
  );
  String get viewReading => _s('View Reading', 'पठन देखें', 'Reading dekhein');
  String get detailedReading =>
      _s('Detailed Reading', 'विस्तृत पठन', 'Detailed Reading');

  // ── Reading Comparison ────────────────────────────────────────────────────
  String get compareReadings => _s('Compare', 'तुलना', 'Compare');
  String get readingComparison =>
      _s('Reading Comparison', 'पठन तुलना', 'Reading Comparison');
  String get compareNow =>
      _s('Compare Now', 'अभी तुलना करें', 'Abhi compare karein');
  String get needTwoReadings => _s(
    'You need at least two saved readings to compare.',
    'तुलना के लिए कम से कम दो सहेजे गए पठन आवश्यक हैं।',
    'Compare karne ke liye kam se kam do saved readings chahiye.',
  );
  String get needTwoReadingsDesc => _s(
    'Complete a palm scan to save your first reading, then scan again to compare.',
    'अपना पहला पठन सहेजने के लिए हथेली स्कैन करें, फिर तुलना के लिए दोबारा स्कैन करें।',
    'Pehli reading save karne ke liye palm scan karein, phir compare ke liye dobara scan karein.',
  );
  String get selectTwoReadings => _s(
    'Select two readings to compare',
    'तुलना के लिए दो पठन चुनें',
    'Compare ke liye do readings chunein',
  );
  String get aiComparisonAnalysis => _s(
    'AI Comparison Analysis',
    'AI तुलना विश्लेषण',
    'AI Comparison Analysis',
  );
  String get fieldByFieldComparison => _s(
    'Field-by-Field Comparison',
    'क्षेत्र-वार तुलना',
    'Field-by-Field Comparison',
  );
  String get improved => _s('↑ Improved', '↑ बेहतर', '↑ Better');
  String get declined => _s('↓ Declined', '↓ कम', '↓ Kam');
  String get unchanged => _s('= Unchanged', '= अपरिवर्तित', '= Same');
  String get newInsight =>
      _s('★ New Insight', '★ नई अंतर्दृष्टि', '★ Nayi Insight');
  String get noSignificantChange => _s(
    '~ No Significant Change',
    '~ कोई बड़ा बदलाव नहीं',
    '~ Koi bada change nahi',
  );

  // ── Onboarding ────────────────────────────────────────────────────────────
  String get getStarted => _s('Get Started', 'शुरू करें', 'Shuru karein');
  String get next => _s('Next', 'अगला', 'Next');
  String get skip => _s('Skip', 'छोड़ें', 'Skip');
  String get onboarding1Title => _s(
    'Discover Your Palm\'s Secrets',
    'अपनी हथेली के रहस्य जानें',
    'Apne palm ke secrets jaanein',
  );
  String get onboarding1Desc => _s(
    'AI-powered palm reading reveals insights about your personality, relationships, and future tendencies.',
    'AI-संचालित हथेली पठन आपके व्यक्तित्व, रिश्तों और भविष्य की प्रवृत्तियों के बारे में जानकारी देता है।',
    'AI-powered palm reading aapki personality, relationships aur future tendencies ke baare mein insights deta hai.',
  );
  String get onboarding2Title =>
      _s('Instant Analysis', 'तत्काल विश्लेषण', 'Instant Analysis');
  String get onboarding2Desc => _s(
    'Simply scan your palm and receive a comprehensive reading in seconds.',
    'बस अपनी हथेली स्कैन करें और कुछ ही सेकंड में व्यापक पठन प्राप्त करें।',
    'Bas apna palm scan karein aur seconds mein comprehensive reading paayein.',
  );
  String get onboarding3Title =>
      _s('Premium Insights', 'प्रीमियम अंतर्दृष्टि', 'Premium Insights');
  String get onboarding3Desc => _s(
    'Unlock detailed reports, couple compatibility readings, and personalized predictions.',
    'विस्तृत रिपोर्ट, जोड़ी अनुकूलता पठन और व्यक्तिगत भविष्यवाणियां अनलॉक करें।',
    'Detailed reports, couple compatibility readings aur personalized predictions unlock karein.',
  );

  // ── Errors / States ───────────────────────────────────────────────────────
  String get somethingWentWrong =>
      _s('Something went wrong', 'कुछ गलत हो गया', 'Kuch galat ho gaya');
  String get tryAgainLater => _s(
    'Please try again later',
    'कृपया बाद में पुनः प्रयास करें',
    'Please baad mein dobara try karein',
  );
  String get noInternetConnection => _s(
    'No internet connection',
    'इंटरनेट कनेक्शन नहीं है',
    'Internet connection nahi hai',
  );
  String get loading => _s('Loading...', 'लोड हो रहा है...', 'Loading...');
  String get retry => _s('Retry', 'पुनः प्रयास', 'Retry');
  String get cancel => _s('Cancel', 'रद्द करें', 'Cancel');
  String get confirm => _s('Confirm', 'पुष्टि करें', 'Confirm');
  String get save => _s('Save', 'सहेजें', 'Save');
  String get close => _s('Close', 'बंद करें', 'Close');
  String get back => _s('Back', 'वापस', 'Back');
  String get done => _s('Done', 'हो गया', 'Done');
  String get ok => _s('OK', 'ठीक है', 'OK');
  String get goToHome => _s('Go to Home', 'होम पर जाएं', 'Home par jayein');
  String get pleaseRetry => _s(
    'Please try again.',
    'कृपया पुनः प्रयास करें।',
    'Please dobara try karein.',
  );
  String get troubleConnecting => _s(
    "We're having trouble connecting.",
    'हमें कनेक्ट करने में समस्या हो रही है।',
    'Connect karne mein problem aa rahi hai.',
  );
  String get internetRequired => _s(
    'Internet connection required for this feature.',
    'इस सुविधा के लिए इंटरनेट कनेक्शन आवश्यक है।',
    'Is feature ke liye internet connection chahiye.',
  );

  // ── Connectivity ──────────────────────────────────────────────────────────
  String get youAreOffline =>
      _s("You're offline", 'आप ऑफलाइन हैं', 'Aap offline hain');
  String get backOnline => _s(
    'Back online',
    'इंटरनेट कनेक्शन वापस आ गया है',
    'Internet connection wapas aa gaya hai',
  );
  String get offlineMessage => _s(
    'Some features require an internet connection.',
    'कुछ सुविधाओं के लिए इंटरनेट कनेक्शन आवश्यक है।',
    'Kuch features ke liye internet connection chahiye.',
  );

  // ── Notifications ─────────────────────────────────────────────────────────────
  String get notificationsTitle =>
      _s('Notifications', 'सूचनाएं', 'Notifications');
  String get noNotifications => _s(
    'No notifications yet',
    'अभी तक कोई सूचना नहीं',
    'Abhi tak koi notification nahi',
  );
  String get dailyPredictionNotif =>
      _s('Daily Prediction', 'दैनिक भविष्यवाणी', 'Daily Prediction');
  String get weeklyPredictionNotif =>
      _s('Weekly Prediction', 'साप्ताहिक भविष्यवाणी', 'Weekly Prediction');

  // ── Notification Permission ───────────────────────────────────────────────────
  String get notifPermissionTitle => _s(
    'Stay Connected with Your Palm Journey',
    'अपनी हथेली यात्रा से जुड़े रहें',
    'Apni palm journey se jude rahein',
  );
  String get notifPermissionDesc => _s(
    'Receive your daily prediction, reading updates and important account notifications.',
    'अपनी दैनिक भविष्यवाणी, पठन अपडेट और महत्वपूर्ण खाता सूचनाएं प्राप्त करें।',
    'Apni daily prediction, reading updates aur important account notifications paayein.',
  );
  String get notifPermissionAllow => _s(
    'Allow Notifications',
    'सूचनाएं अनुमति दें',
    'Notifications allow karein',
  );
  String get notifPermissionNotNow => _s('Not Now', 'अभी नहीं', 'Abhi nahi');

  // ── Notification Categories ───────────────────────────────────────────────────
  String get notifCategoryDailyPrediction =>
      _s('Daily Prediction', 'दैनिक भविष्यवाणी', 'Daily Prediction');
  String get notifCategoryDailyPredictionDesc => _s(
    'Your daily HastVeda insight is ready',
    'आपकी दैनिक HastVeda अंतर्दृष्टि तैयार है',
    'Aapki daily HastVeda insight ready hai',
  );
  String get notifCategoryReadingReady =>
      _s('Reading Ready', 'पठन तैयार है', 'Reading ready hai');
  String get notifCategoryReadingReadyDesc => _s(
    'Your palm reading is complete',
    'आपका हथेली पठन पूर्ण हो गया है',
    'Aapka palm reading complete ho gaya hai',
  );
  String get notifCategoryReportReady =>
      _s('Report Ready', 'रिपोर्ट तैयार है', 'Report ready hai');
  String get notifCategoryReportReadyDesc => _s(
    'Your detailed report is available',
    'आपकी विस्तृत रिपोर्ट उपलब्ध है',
    'Aapki detailed report available hai',
  );
  String get notifCategoryPremiumUpdates =>
      _s('Premium Updates', 'प्रीमियम अपडेट', 'Premium Updates');
  String get notifCategoryPremiumUpdatesDesc => _s(
    'Subscription and offer updates',
    'सदस्यता और ऑफर अपडेट',
    'Subscription aur offer updates',
  );
  String get notifCategoryImportantAccount => _s(
    'Important Account Notifications',
    'महत्वपूर्ण खाता सूचनाएं',
    'Important Account Notifications',
  );
  String get notifCategoryImportantAccountDesc => _s(
    'Security and account alerts',
    'सुरक्षा और खाता अलर्ट',
    'Security aur account alerts',
  );

  // ── FCM / Push notification body strings ─────────────────────────────────────
  String get notifDailyPredictionBody => _s(
    'Your HastVeda insight for today is ready.',
    'आपका आज का HastVeda रीडिंग तैयार है।',
    'Aapki aaj ki HastVeda insight ready hai.',
  );
  String get notifReadingReadyBody => _s(
    'Your HastVeda reading is ready.',
    'आपका HastVeda पठन तैयार है।',
    'Aapka HastVeda reading ready hai.',
  );
  String get notifReportReadyBody => _s(
    'Your HastVeda report is ready.',
    'आपकी HastVeda रिपोर्ट तैयार है।',
    'Aapki HastVeda report ready hai.',
  );
  String get notifCoupleReadingReadyBody => _s(
    'Your Couple Reading is ready.',
    'आपका जोड़ी पठन तैयार है।',
    'Aapka Couple Reading ready hai.',
  );

  // ── Notification Settings ─────────────────────────────────────────────────────
  String get notificationSettings =>
      _s('Notification Settings', 'सूचना सेटिंग्स', 'Notification Settings');
  String get notificationSettingsDesc => _s(
    'Control which notifications you receive from HastVeda.',
    'नियंत्रित करें कि आप HastVeda से कौन सी सूचनाएं प्राप्त करते हैं।',
    'Control karein ki aap HastVeda se kaun si notifications paate hain.',
  );
  String get fcmStatusDisabled => _s(
    'Push notifications require Firebase configuration.',
    'पुश सूचनाओं के लिए Firebase कॉन्फ़िगरेशन आवश्यक है।',
    'Push notifications ke liye Firebase configuration chahiye.',
  );

  // ── Palm Analysis Pipeline ───────────────────────────────────────────────
  String get palmNotClearlyVisible => _s(
    "We couldn't clearly read your palm.",
    'हम आपकी हथेली स्पष्ट रूप से नहीं पढ़ सके।',
    'Aapka palm clearly read nahi ho pa raha.',
  );
  String get palmQualityTip => _s(
    'Place your palm flat, keep your fingers naturally open and capture it in good lighting.',
    'अपनी हथेली सपाट रखें, उंगलियां स्वाभाविक रूप से खुली रखें और अच्छी रोशनी में कैप्चर करें।',
    'Apna palm flat rakhein, ungliyan naturally khuli rakhein aur achchi lighting mein capture karein.',
  );
  String get captureNewPhoto =>
      _s('Capture New Photo', 'नई फ़ोटो लें', 'Nayi photo lein');
  String get whichHandIsThis =>
      _s('Which hand is this?', 'कौन सा हाथ है?', 'Kaun sa haath hai?');
  String get leftHand => _s('Left Hand', 'बायां हाथ', 'Left Hand');
  String get rightHand => _s('Right Hand', 'दायां हाथ', 'Right Hand');
  String get handIdentificationRequired => _s(
    'Hand identification is required for accurate analysis',
    'सटीक विश्लेषण के लिए हाथ की पहचान आवश्यक है',
    'Accurate analysis ke liye haath ki pehchaan zaroori hai',
  );
  String get uploadingPalmImage => _s(
    'Uploading palm image...',
    'हथेली की छवि अपलोड हो रही है...',
    'Palm image upload ho rahi hai...',
  );
  String get checkingImageQuality => _s(
    'Checking image quality...',
    'छवि गुणवत्ता जांची जा रही है...',
    'Image quality check ho rahi hai...',
  );
  String get identifyingPalmFeatures => _s(
    'Identifying palm features...',
    'हथेली की रेखाएं पहचानी जा रही हैं...',
    'Palm features identify ho rahe hain...',
  );
  String get preparingYourReading => _s(
    'Preparing your reading...',
    'आपका पठन तैयार हो रहा है...',
    'Aapka reading prepare ho raha hai...',
  );
  String get yourReadingIsReady => _s(
    'Your reading is ready.',
    'आपका पठन तैयार है।',
    'Aapka reading ready hai.',
  );
  String get aiAnalyzed => _s('AI Analyzed', 'AI विश्लेषण', 'AI Analyzed');
  String get scanNewPalm =>
      _s('Scan New Palm', 'नई हथेली स्कैन करें', 'Nayi palm scan karein');
  String get todaysInsight =>
      _s("Today's Insight", 'आज की अंतर्दृष्टि', "Aaj ki Insight");
  String get palmAnalysisFailed => _s(
    'Palm analysis failed. Please try again.',
    'हथेली विश्लेषण विफल। कृपया पुनः प्रयास करें।',
    'Palm analysis fail hua. Please dobara try karein.',
  );
  String get analysisTimedOut => _s(
    'Analysis timed out. Please check your connection and try again.',
    'विश्लेषण का समय समाप्त हो गया। कृपया अपना कनेक्शन जांचें और पुनः प्रयास करें।',
    'Analysis timeout ho gaya. Please apna connection check karein aur dobara try karein.',
  );

  // ── Palm Lines Detail ─────────────────────────────────────────────────────
  String get interpretation =>
      _s('Interpretation', 'व्याख्या', 'Interpretation');
  String get characteristics =>
      _s('Characteristics', 'विशेषताएं', 'Characteristics');
  String get insights => _s('Insights', 'अंतर्दृष्टि', 'Insights');
  String get palmistryNote => _s(
    'Palmistry interpretation suggests...',
    'हस्तरेखा व्याख्या सुझाती है...',
    'Palmistry interpretation suggest karta hai...',
  );

  // ── Splash ────────────────────────────────────────────────────────────────
  String get welcomeBack =>
      _s('Welcome Back', 'वापसी पर स्वागत है', 'Wapas aaye, swagat hai');
  String get aiPowered => _s(
    'AI-Powered Palm Reading',
    'AI-संचालित हथेली पठन',
    'AI-Powered Palm Reading',
  );

  // Helper — 3-language selector
  String _s(String en, String hi, String hiLatn) {
    switch (languageCode) {
      case 'hi':
        return hi;
      case 'hi-Latn':
        return hiLatn;
      default:
        return en;
    }
  }
}
