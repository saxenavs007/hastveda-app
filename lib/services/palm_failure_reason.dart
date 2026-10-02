// Palm analysis failure reasons.
//
// A failed scan used to surface as "Scan Failed" + one generic line, which told
// the user nothing about what to change. The Edge Function now returns a
// specific `reason` code for every failure; this file is the single place that
// turns that code into a headline, an explanation and concrete correction tips.
//
// Adding a code here is the ONLY change needed to give it a proper message —
// the scan screen renders whatever this returns.

/// Machine-readable failure reasons. Mirrors `FailureCode` in the
/// palm-analysis Edge Function and the `failure_code` column of
/// `palm_analysis_failures`.
enum PalmFailureReason {
  // ── Capture problems the user can fix ──────────────────────────────────
  noPalmDetected,
  partialPalm,
  tooBlurry,
  tooDark,
  tooBright,
  tooFar,
  tooClose,
  obstructed,
  wrongSide,
  lowQualityImage,

  // ── Service-side problems retrying may fix ─────────────────────────────
  aiServiceBusy,
  aiTimeout,
  aiResponseTruncated,
  stageAFailed,
  stageBFailed,
  persistFailed,

  // ── Client / account ───────────────────────────────────────────────────
  freeLimitReached,
  networkError,
  uploadFailed,
  unknown;

  /// Parses the wire code. Unrecognised values fall back to [unknown] so a new
  /// server-side code can never crash an older client.
  static PalmFailureReason fromCode(String? code) {
    switch (code?.toUpperCase().trim()) {
      case 'NO_PALM_DETECTED':
        return PalmFailureReason.noPalmDetected;
      case 'PARTIAL_PALM':
        return PalmFailureReason.partialPalm;
      case 'TOO_BLURRY':
        return PalmFailureReason.tooBlurry;
      case 'TOO_DARK':
        return PalmFailureReason.tooDark;
      case 'TOO_BRIGHT':
        return PalmFailureReason.tooBright;
      case 'TOO_FAR':
        return PalmFailureReason.tooFar;
      case 'TOO_CLOSE':
        return PalmFailureReason.tooClose;
      case 'OBSTRUCTED':
        return PalmFailureReason.obstructed;
      case 'WRONG_SIDE':
        return PalmFailureReason.wrongSide;
      case 'LOW_QUALITY_IMAGE':
        return PalmFailureReason.lowQualityImage;
      case 'AI_SERVICE_BUSY':
        return PalmFailureReason.aiServiceBusy;
      case 'AI_TIMEOUT':
        return PalmFailureReason.aiTimeout;
      case 'AI_RESPONSE_TRUNCATED':
        return PalmFailureReason.aiResponseTruncated;
      case 'STAGE_A_FAILED':
        return PalmFailureReason.stageAFailed;
      case 'STAGE_B_FAILED':
        return PalmFailureReason.stageBFailed;
      case 'PERSIST_FAILED':
        return PalmFailureReason.persistFailed;
      case 'FREE_LIMIT_REACHED':
        return PalmFailureReason.freeLimitReached;
      case 'NETWORK_ERROR':
        return PalmFailureReason.networkError;
      case 'UPLOAD_FAILED':
        return PalmFailureReason.uploadFailed;
      default:
        return PalmFailureReason.unknown;
    }
  }

  /// The wire code, for logging back to `palm_analysis_failures`.
  String get code {
    switch (this) {
      case PalmFailureReason.noPalmDetected:
        return 'NO_PALM_DETECTED';
      case PalmFailureReason.partialPalm:
        return 'PARTIAL_PALM';
      case PalmFailureReason.tooBlurry:
        return 'TOO_BLURRY';
      case PalmFailureReason.tooDark:
        return 'TOO_DARK';
      case PalmFailureReason.tooBright:
        return 'TOO_BRIGHT';
      case PalmFailureReason.tooFar:
        return 'TOO_FAR';
      case PalmFailureReason.tooClose:
        return 'TOO_CLOSE';
      case PalmFailureReason.obstructed:
        return 'OBSTRUCTED';
      case PalmFailureReason.wrongSide:
        return 'WRONG_SIDE';
      case PalmFailureReason.lowQualityImage:
        return 'LOW_QUALITY_IMAGE';
      case PalmFailureReason.aiServiceBusy:
        return 'AI_SERVICE_BUSY';
      case PalmFailureReason.aiTimeout:
        return 'AI_TIMEOUT';
      case PalmFailureReason.aiResponseTruncated:
        return 'AI_RESPONSE_TRUNCATED';
      case PalmFailureReason.stageAFailed:
        return 'STAGE_A_FAILED';
      case PalmFailureReason.stageBFailed:
        return 'STAGE_B_FAILED';
      case PalmFailureReason.persistFailed:
        return 'PERSIST_FAILED';
      case PalmFailureReason.freeLimitReached:
        return 'FREE_LIMIT_REACHED';
      case PalmFailureReason.networkError:
        return 'NETWORK_ERROR';
      case PalmFailureReason.uploadFailed:
        return 'UPLOAD_FAILED';
      case PalmFailureReason.unknown:
        return 'UNKNOWN';
    }
  }

  /// True when the user changing something about the photo can fix this.
  /// Drives whether correction tips are shown.
  bool get isCaptureProblem {
    switch (this) {
      case PalmFailureReason.noPalmDetected:
      case PalmFailureReason.partialPalm:
      case PalmFailureReason.tooBlurry:
      case PalmFailureReason.tooDark:
      case PalmFailureReason.tooBright:
      case PalmFailureReason.tooFar:
      case PalmFailureReason.tooClose:
      case PalmFailureReason.obstructed:
      case PalmFailureReason.wrongSide:
      case PalmFailureReason.lowQualityImage:
        return true;
      default:
        return false;
    }
  }
}

/// Everything the error screen needs to render one failure.
class PalmFailureCopy {
  /// Headline — replaces the old blanket "Scan Failed".
  final String title;

  /// One sentence naming what went wrong and what to do about it.
  final String message;

  /// Short, concrete corrections. Empty for non-capture failures.
  final List<String> tips;

  const PalmFailureCopy({
    required this.title,
    required this.message,
    this.tips = const [],
  });
}

/// Picks one of three translations by language code.
String _t(String lang, String en, String hi, String hinglish) {
  if (lang == 'hi') return hi;
  if (lang == 'hi-Latn') return hinglish;
  return en;
}

List<String> _tList(
  String lang,
  List<String> en,
  List<String> hi,
  List<String> hinglish,
) {
  if (lang == 'hi') return hi;
  if (lang == 'hi-Latn') return hinglish;
  return en;
}

/// Builds the user-facing copy for a failure.
///
/// [detail] is the model's own short description of the problem (e.g. "palm is
/// cut off at the bottom"). It is appended only when it adds information the
/// fixed copy does not already carry.
PalmFailureCopy palmFailureCopy(
  PalmFailureReason reason, {
  String lang = 'en',
  String? detail,
}) {
  switch (reason) {
    case PalmFailureReason.noPalmDetected:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Palm not clearly detected',
          'हथेली स्पष्ट नहीं दिखी',
          'Palm clearly detect nahi hui',
        ),
        message: _t(
          lang,
          'Please place your entire palm inside the frame, keep your hand steady and use good lighting.',
          'कृपया अपनी पूरी हथेली फ्रेम के अंदर रखें, हाथ स्थिर रखें और अच्छी रोशनी में स्कैन करें।',
          'Apni poori palm frame ke andar rakhein, haath steady rakhein aur acchi lighting use karein.',
        ),
        tips: _tList(
          lang,
          [
            'Hold your palm flat and facing the camera',
            'Keep fingers slightly apart, not clenched',
            'Fill the frame with your palm',
          ],
          [
            'हथेली सपाट रखें और कैमरे की ओर रखें',
            'उंगलियां थोड़ी खुली रखें, मुट्ठी न बनाएं',
            'फ्रेम में हथेली पूरी तरह भरें',
          ],
          [
            'Palm flat rakhein aur camera ki taraf rakhein',
            'Fingers thodi open rakhein, mutthi mat banayein',
            'Frame mein palm poori tarah bharein',
          ],
        ),
      );

    case PalmFailureReason.partialPalm:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Palm is cut off',
          'हथेली पूरी नहीं आई',
          'Palm poori frame mein nahi aayi',
        ),
        message: _t(
          lang,
          'Part of your palm is outside the frame. Move your hand back slightly so the whole palm — wrist to fingertips — is visible.',
          'आपकी हथेली का कुछ हिस्सा फ्रेम से बाहर है। हाथ थोड़ा पीछे करें ताकि कलाई से उंगलियों तक पूरी हथेली दिखे।',
          'Aapki palm ka kuch hissa frame se bahar hai. Haath thoda peeche karein taaki wrist se fingertips tak poori palm dikhe.',
        ),
        tips: _tList(
          lang,
          [
            'Move your hand a little further from the camera',
            'Centre your palm inside the guide outline',
            'Make sure the base of the palm is included',
          ],
          [
            'हाथ को कैमरे से थोड़ा दूर करें',
            'हथेली को गाइड के बीच में रखें',
            'हथेली का निचला हिस्सा भी शामिल करें',
          ],
          [
            'Haath ko camera se thoda door karein',
            'Palm ko guide ke beech mein rakhein',
            'Palm ka nichla hissa bhi include karein',
          ],
        ),
      );

    case PalmFailureReason.tooBlurry:
      return PalmFailureCopy(
        title: _t(lang, 'Image is blurry', 'छवि धुंधली है', 'Image blurry hai'),
        message: _t(
          lang,
          'The palm lines are not sharp enough to read. Hold your hand still for a moment before scanning and let the camera focus.',
          'हथेली की रेखाएं पढ़ने लायक स्पष्ट नहीं हैं। स्कैन से पहले हाथ को कुछ पल स्थिर रखें और कैमरे को फोकस होने दें।',
          'Palm ki lines padhne layak sharp nahi hain. Scan se pehle haath ko kuch pal steady rakhein aur camera ko focus hone dein.',
        ),
        tips: _tList(
          lang,
          [
            'Rest your elbow on a table to stay steady',
            'Wait a second for the camera to focus',
            'Avoid moving your hand while scanning',
          ],
          [
            'कोहनी को मेज़ पर टिकाएं ताकि हाथ स्थिर रहे',
            'कैमरे को फोकस होने के लिए एक क्षण दें',
            'स्कैन के दौरान हाथ न हिलाएं',
          ],
          [
            'Elbow ko table par tikayein taaki haath steady rahe',
            'Camera ko focus hone ke liye ek second dein',
            'Scan ke time haath mat hilayein',
          ],
        ),
      );

    case PalmFailureReason.tooDark:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Lighting is too dim',
          'रोशनी बहुत कम है',
          'Lighting bahut kam hai',
        ),
        message: _t(
          lang,
          'The palm lines are lost in shadow. Move to a brighter spot or face a window, and keep your hand out of your own shadow.',
          'हथेली की रेखाएं छाया में छिप गई हैं। अधिक रोशनी वाली जगह पर जाएं या खिड़की की ओर मुंह करें, और हाथ को अपनी छाया से दूर रखें।',
          'Palm ki lines shadow mein chhup gayi hain. Zyada roshni wali jagah par jayein ya window ki taraf face karein, aur haath ko apni shadow se door rakhein.',
        ),
        tips: _tList(
          lang,
          [
            'Face a window or a bright light',
            'Do not let your phone cast a shadow on your palm',
            'Avoid scanning in a dark room at night',
          ],
          [
            'खिड़की या तेज़ रोशनी की ओर मुंह करें',
            'फोन की छाया हथेली पर न पड़ने दें',
            'रात में अंधेरे कमरे में स्कैन न करें',
          ],
          [
            'Window ya bright light ki taraf face karein',
            'Phone ki shadow palm par mat padne dein',
            'Raat mein dark room mein scan mat karein',
          ],
        ),
      );

    case PalmFailureReason.tooBright:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Too much glare',
          'बहुत ज़्यादा चमक',
          'Bahut zyada glare hai',
        ),
        message: _t(
          lang,
          'Bright light is washing out the palm lines. Move out of direct light or turn off the flash, then scan again.',
          'तेज़ रोशनी से हथेली की रेखाएं धुल गई हैं। सीधी रोशनी से हटें या फ्लैश बंद करें, फिर दोबारा स्कैन करें।',
          'Tez roshni se palm ki lines wash out ho gayi hain. Direct light se hatein ya flash band karein, phir dobara scan karein.',
        ),
        tips: _tList(
          lang,
          [
            'Step out of direct sunlight',
            'Turn off the camera flash',
            'Avoid a light source directly behind the phone',
          ],
          [
            'सीधी धूप से हटें',
            'कैमरा फ्लैश बंद करें',
            'फोन के ठीक पीछे रोशनी न रखें',
          ],
          [
            'Direct sunlight se hatein',
            'Camera flash band karein',
            'Phone ke theek peeche light source mat rakhein',
          ],
        ),
      );

    case PalmFailureReason.tooFar:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Palm is too far away',
          'हथेली बहुत दूर है',
          'Palm bahut door hai',
        ),
        message: _t(
          lang,
          'Your palm is too small in the frame to read the fine lines. Bring your hand closer until it fills the guide.',
          'फ्रेम में हथेली इतनी छोटी है कि बारीक रेखाएं नहीं पढ़ी जा सकतीं। हाथ को पास लाएं ताकि वह गाइड में भर जाए।',
          'Frame mein palm itni choti hai ki fine lines nahi padhi ja sakti. Haath ko paas layein taaki wo guide mein bhar jaye.',
        ),
        tips: _tList(
          lang,
          [
            'Bring your palm closer to the camera',
            'Fill the guide outline with your palm',
            'Keep the palm parallel to the phone',
          ],
          [
            'हथेली को कैमरे के पास लाएं',
            'गाइड को हथेली से पूरा भरें',
            'हथेली को फोन के समानांतर रखें',
          ],
          [
            'Palm ko camera ke paas layein',
            'Guide outline ko palm se poora bharein',
            'Palm ko phone ke parallel rakhein',
          ],
        ),
      );

    case PalmFailureReason.tooClose:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Palm is too close',
          'हथेली बहुत पास है',
          'Palm bahut paas hai',
        ),
        message: _t(
          lang,
          'Your hand is so close that the camera cannot focus. Move it back a few centimetres until the whole palm is sharp.',
          'हाथ इतना पास है कि कैमरा फोकस नहीं कर पा रहा। इसे कुछ सेंटीमीटर पीछे करें जब तक पूरी हथेली स्पष्ट न दिखे।',
          'Haath itna paas hai ki camera focus nahi kar pa raha. Ise kuch centimetre peeche karein jab tak poori palm sharp na dikhe.',
        ),
        tips: _tList(
          lang,
          [
            'Move your hand back a little',
            'Keep about 20–30 cm between palm and phone',
            'Wait for the image to look sharp before scanning',
          ],
          [
            'हाथ को थोड़ा पीछे करें',
            'हथेली और फोन के बीच लगभग 20–30 सेमी रखें',
            'स्कैन से पहले छवि स्पष्ट होने का इंतज़ार करें',
          ],
          [
            'Haath ko thoda peeche karein',
            'Palm aur phone ke beech lagbhag 20–30 cm rakhein',
            'Scan se pehle image sharp hone ka wait karein',
          ],
        ),
      );

    case PalmFailureReason.obstructed:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Palm lines are covered',
          'हथेली की रेखाएं ढकी हैं',
          'Palm ki lines covered hain',
        ),
        message: _t(
          lang,
          'Something is covering the palm lines. Remove gloves, rings or anything on the palm, clean your hand and try again.',
          'कोई चीज़ हथेली की रेखाओं को ढक रही है। दस्ताने, अंगूठी या हथेली पर लगी कोई चीज़ हटाएं, हाथ साफ़ करें और पुनः प्रयास करें।',
          'Koi cheez palm ki lines ko cover kar rahi hai. Gloves, rings ya palm par lagi koi cheez hatayein, haath saaf karein aur dobara try karein.',
        ),
        tips: _tList(
          lang,
          [
            'Remove gloves or anything worn on the palm',
            'Wipe your hand clean and dry',
            'Heavy henna or writing can hide the lines',
          ],
          [
            'दस्ताने या हथेली पर पहनी कोई चीज़ हटाएं',
            'हाथ को साफ़ और सूखा करें',
            'गहरी मेहंदी या लिखावट रेखाएं छिपा सकती है',
          ],
          [
            'Gloves ya palm par pehni koi cheez hatayein',
            'Haath ko saaf aur dry karein',
            'Dark mehndi ya writing lines chhupa sakti hai',
          ],
        ),
      );

    case PalmFailureReason.wrongSide:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Show your palm, not the back',
          'हथेली दिखाएं, हाथ का पिछला भाग नहीं',
          'Palm dikhayein, haath ka peecha nahi',
        ),
        message: _t(
          lang,
          'The back of your hand is facing the camera. Turn your hand over so the lined side of the palm faces the lens.',
          'हाथ का पिछला भाग कैमरे की ओर है। हाथ पलटें ताकि रेखाओं वाला भाग कैमरे की ओर हो।',
          'Haath ka peecha camera ki taraf hai. Haath palat dein taaki lines wala side camera ki taraf ho.',
        ),
        tips: _tList(
          lang,
          [
            'Turn your hand so the palm faces the camera',
            'Fingers pointing up, palm flat',
          ],
          ['हाथ पलटें ताकि हथेली कैमरे की ओर हो', 'उंगलियां ऊपर, हथेली सपाट'],
          [
            'Haath palat dein taaki palm camera ki taraf ho',
            'Fingers upar, palm flat',
          ],
        ),
      );

    case PalmFailureReason.lowQualityImage:
      return PalmFailureCopy(
        title: _t(
          lang,
          "Palm couldn't be read clearly",
          'हथेली स्पष्ट रूप से नहीं पढ़ी जा सकी',
          'Palm clearly padhi nahi ja saki',
        ),
        message: _t(
          lang,
          'The image was not clear enough for an accurate reading. Use good lighting, hold your hand steady and keep the whole palm in frame.',
          'सटीक विश्लेषण के लिए छवि पर्याप्त स्पष्ट नहीं थी। अच्छी रोशनी में, हाथ स्थिर रखकर और पूरी हथेली फ्रेम में रखकर पुनः प्रयास करें।',
          'Accurate reading ke liye image kaafi clear nahi thi. Acchi lighting mein, haath steady rakh kar aur poori palm frame mein rakh kar dobara try karein.',
        ),
        tips: _tList(
          lang,
          [
            'Use bright, even lighting',
            'Hold your hand still and let the camera focus',
            'Keep the entire palm inside the frame',
          ],
          [
            'तेज़ और समान रोशनी का उपयोग करें',
            'हाथ स्थिर रखें और कैमरे को फोकस होने दें',
            'पूरी हथेली फ्रेम के अंदर रखें',
          ],
          [
            'Bright aur even lighting use karein',
            'Haath steady rakhein aur camera ko focus hone dein',
            'Poori palm frame ke andar rakhein',
          ],
        ),
      );

    // ── Service-side: nothing for the user to correct ──────────────────────
    case PalmFailureReason.aiServiceBusy:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Service is busy',
          'सेवा व्यस्त है',
          'Service busy hai',
        ),
        message: _t(
          lang,
          'Our reading service is under heavy load right now. Your photo was fine — please try again in a moment.',
          'हमारी सेवा अभी अत्यधिक व्यस्त है। आपकी तस्वीर ठीक थी — कृपया कुछ देर बाद पुनः प्रयास करें।',
          'Hamari reading service abhi heavy load par hai. Aapki photo theek thi — thodi der baad dobara try karein.',
        ),
      );

    case PalmFailureReason.aiTimeout:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Reading took too long',
          'विश्लेषण में बहुत समय लगा',
          'Reading mein bahut time lag gaya',
        ),
        message: _t(
          lang,
          'The analysis timed out before it finished. Your photo was fine — please try again.',
          'विश्लेषण पूरा होने से पहले समय समाप्त हो गया। आपकी तस्वीर ठीक थी — कृपया पुनः प्रयास करें।',
          'Analysis complete hone se pehle time out ho gaya. Aapki photo theek thi — dobara try karein.',
        ),
      );

    case PalmFailureReason.aiResponseTruncated:
    case PalmFailureReason.stageAFailed:
    case PalmFailureReason.stageBFailed:
      return PalmFailureCopy(
        title: _t(
          lang,
          "Reading couldn't be completed",
          'विश्लेषण पूरा नहीं हो सका',
          'Reading complete nahi ho saki',
        ),
        message: _t(
          lang,
          'Something went wrong while generating your reading. Your photo was fine — please try again.',
          'आपका विश्लेषण बनाते समय कुछ गड़बड़ हुई। आपकी तस्वीर ठीक थी — कृपया पुनः प्रयास करें।',
          'Aapki reading banate waqt kuch gadbad hui. Aapki photo theek thi — dobara try karein.',
        ),
      );

    case PalmFailureReason.persistFailed:
      return PalmFailureCopy(
        title: _t(
          lang,
          "Reading couldn't be saved",
          'विश्लेषण सहेजा नहीं जा सका',
          'Reading save nahi ho saki',
        ),
        message: _t(
          lang,
          'Your reading was generated but could not be saved. Please try again.',
          'आपका विश्लेषण बन गया था लेकिन सहेजा नहीं जा सका। कृपया पुनः प्रयास करें।',
          'Aapki reading ban gayi thi lekin save nahi ho saki. Dobara try karein.',
        ),
      );

    case PalmFailureReason.networkError:
      return PalmFailureCopy(
        title: _t(
          lang,
          'No internet connection',
          'इंटरनेट कनेक्शन नहीं है',
          'Internet connection nahi hai',
        ),
        message: _t(
          lang,
          'Your palm reading needs an internet connection. Check your network and try again.',
          'हस्तरेखा विश्लेषण के लिए इंटरनेट कनेक्शन आवश्यक है। कृपया नेटवर्क जांचें और पुनः प्रयास करें।',
          'Palm reading ke liye internet connection chahiye. Network check karke dobara try karein.',
        ),
      );

    case PalmFailureReason.uploadFailed:
      return PalmFailureCopy(
        title: _t(
          lang,
          "Photo couldn't be uploaded",
          'तस्वीर अपलोड नहीं हो सकी',
          'Photo upload nahi ho saki',
        ),
        message: _t(
          lang,
          'The palm photo could not be uploaded. Check your connection and try again.',
          'हथेली की तस्वीर अपलोड नहीं हो सकी। कृपया कनेक्शन जांचें और पुनः प्रयास करें।',
          'Palm ki photo upload nahi ho saki. Connection check karke dobara try karein.',
        ),
      );

    case PalmFailureReason.freeLimitReached:
      return PalmFailureCopy(
        title: _t(
          lang,
          'Monthly Limit Reached',
          'मासिक सीमा पूरी',
          'Monthly limit poori ho gayi',
        ),
        message: _t(
          lang,
          'You have used all your free scans for this month. Upgrade to Premium for unlimited readings.',
          'इस महीने के आपके सभी मुफ़्त स्कैन उपयोग हो चुके हैं। असीमित विश्लेषण के लिए प्रीमियम लें।',
          'Is month ke aapke saare free scans use ho chuke hain. Unlimited readings ke liye Premium lein.',
        ),
      );

    case PalmFailureReason.unknown:
      return PalmFailureCopy(
        title: _t(
          lang,
          "Scan couldn't be completed",
          'स्कैन पूरा नहीं हो सका',
          'Scan complete nahi ho saka',
        ),
        message: _t(
          lang,
          detail?.trim().isNotEmpty == true
              ? detail!.trim()
              : 'Something went wrong. Please try scanning again.',
          'कुछ गड़बड़ हो गई। कृपया पुनः स्कैन करें।',
          'Kuch gadbad ho gayi. Dobara scan karein.',
        ),
      );
  }
}
