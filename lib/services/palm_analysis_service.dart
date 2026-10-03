// HastVeda Palm Analysis Service
// Provider-independent abstraction for real Gemini-powered palm analysis.
// All AI calls go through Supabase Edge Functions — API key never reaches client.

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './app_strings.dart';
import './error_logger.dart';
import './palm_failure_logger.dart';
import './palm_failure_reason.dart';
import './supabase_service.dart';

// ── Palm Analysis Result Models ───────────────────────────────────────────────

class ImageQualityResult {
  final double score;
  final bool palmDetected;
  final List<String> issues;
  final bool suitableForAnalysis;

  const ImageQualityResult({
    required this.score,
    required this.palmDetected,
    required this.issues,
    required this.suitableForAnalysis,
  });

  factory ImageQualityResult.fromJson(Map<String, dynamic> json) {
    return ImageQualityResult(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      palmDetected: json['palm_detected'] as bool? ?? false,
      issues: (json['issues'] as List?)?.cast<String>() ?? [],
      suitableForAnalysis: json['suitable_for_analysis'] as bool? ?? false,
    );
  }
}

class PalmLineFeature {
  final bool visible;
  final double confidence;
  final String length;
  final String depth;
  final String continuity;
  final List<String> observations;

  const PalmLineFeature({
    required this.visible,
    required this.confidence,
    this.length = 'unknown',
    this.depth = 'unknown',
    this.continuity = 'unknown',
    this.observations = const [],
  });

  factory PalmLineFeature.fromJson(Map<String, dynamic> json) {
    return PalmLineFeature(
      visible: json['visible'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      length: json['length'] as String? ?? 'unknown',
      depth: json['depth'] as String? ?? 'unknown',
      continuity: json['continuity'] as String? ?? 'unknown',
      observations: (json['observations'] as List?)?.cast<String>() ?? [],
    );
  }
}

class AnalysisCategory {
  final String titleEn;
  final String titleHi;
  final String contentEn;
  final String contentHi;
  final int score;
  final bool isPremiumLocked;

  const AnalysisCategory({
    required this.titleEn,
    required this.titleHi,
    required this.contentEn,
    required this.contentHi,
    required this.score,
    this.isPremiumLocked = false,
  });

  factory AnalysisCategory.fromJson(Map<String, dynamic> json) {
    return AnalysisCategory(
      titleEn: json['title_en'] as String? ?? '',
      titleHi: json['title_hi'] as String? ?? '',
      contentEn: json['content_en'] as String? ?? '',
      contentHi: json['content_hi'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 75,
      isPremiumLocked: json['is_premium_locked'] as bool? ?? false,
    );
  }

  /// Returns the title in the requested language.
  /// For Hinglish (hi-Latn), content_hi holds the Hinglish text (set by the Edge Function).
  String title(String lang) {
    if (lang == 'hi' || lang == 'hi-Latn') {
      return titleHi.isNotEmpty ? titleHi : titleEn;
    }
    return titleEn;
  }

  /// Returns the content in the requested language.
  /// For Hinglish (hi-Latn), content_hi holds the Hinglish text (set by the Edge Function).
  String content(String lang) {
    if (lang == 'hi' || lang == 'hi-Latn') {
      return contentHi.isNotEmpty ? contentHi : contentEn;
    }
    return contentEn;
  }
}

class PalmAnalysisResult {
  final String analysisId;
  final String scanId;
  final String handSide;
  final ImageQualityResult imageQuality;
  final double overallConfidence;
  final int overallScore;
  final String summaryEn;
  final String summaryHi;
  final AnalysisCategory personality;
  final AnalysisCategory loveRelationships;
  final AnalysisCategory career;
  final AnalysisCategory wealth;
  final AnalysisCategory health;
  final AnalysisCategory lifePath;
  final AnalysisCategory futureTendencies;
  final List<String> keyTraitsEn;
  final List<String> keyTraitsHi;
  final String dailyInsightEn;
  final String dailyInsightHi;
  final String remediesEn;
  final String remediesHi;
  final String? confidenceNoteEn;
  final String? confidenceNoteHi;
  final bool isPremium;
  final bool cached;
  final int processingTimeMs;

  // Raw feature data for display
  final Map<String, dynamic> palmFeatures;
  final Map<String, dynamic> mounts;
  final List<String> specialMarks;
  final Map<String, dynamic> palmShape;

  const PalmAnalysisResult({
    required this.analysisId,
    required this.scanId,
    required this.handSide,
    required this.imageQuality,
    required this.overallConfidence,
    required this.overallScore,
    required this.summaryEn,
    required this.summaryHi,
    required this.personality,
    required this.loveRelationships,
    required this.career,
    required this.wealth,
    required this.health,
    required this.lifePath,
    required this.futureTendencies,
    required this.keyTraitsEn,
    required this.keyTraitsHi,
    required this.dailyInsightEn,
    required this.dailyInsightHi,
    this.remediesEn = '',
    this.remediesHi = '',
    this.confidenceNoteEn,
    this.confidenceNoteHi,
    required this.isPremium,
    required this.cached,
    required this.processingTimeMs,
    this.palmFeatures = const {},
    this.mounts = const {},
    this.specialMarks = const [],
    this.palmShape = const {},
  });

  String summary(String lang) {
    if (lang == 'hi' || lang == 'hi-Latn') {
      return summaryHi.isNotEmpty ? summaryHi : summaryEn;
    }
    return summaryEn;
  }

  List<String> keyTraits(String lang) {
    if (lang == 'hi' || lang == 'hi-Latn') {
      return keyTraitsHi.isNotEmpty ? keyTraitsHi : keyTraitsEn;
    }
    return keyTraitsEn;
  }

  String dailyInsight(String lang) {
    if (lang == 'hi' || lang == 'hi-Latn') {
      return dailyInsightHi.isNotEmpty ? dailyInsightHi : dailyInsightEn;
    }
    return dailyInsightEn;
  }

  String? confidenceNote(String lang) {
    if (lang == 'hi' || lang == 'hi-Latn') {
      return confidenceNoteHi ?? confidenceNoteEn;
    }
    return confidenceNoteEn;
  }

  factory PalmAnalysisResult.fromJson(
    Map<String, dynamic> json, {
    required String analysisId,
    required String scanId,
    bool cached = false,
  }) {
    // The Edge Function wraps data in a 'data' key
    final data = json['data'] as Map<String, dynamic>? ?? json;

    // ── Parse a category from Stage B direct fields (preferred) ──────────────
    // Edge Function now returns personality/love_relationships/etc. directly in data
    AnalysisCategory parseCategoryDirect(String key) {
      final raw = data[key];
      if (raw is Map<String, dynamic> && raw.containsKey('content_en')) {
        return AnalysisCategory.fromJson(raw);
      }
      // Fallback: try DB-stored analysis fields
      return _parseCategoryFromDb(data, key);
    }

    final palmFeaturesRaw =
        data['palm_features'] as Map<String, dynamic>? ?? {};
    final mountsRaw = data['mounts'] as Map<String, dynamic>? ?? {};
    final specialMarksRaw =
        (data['special_marks'] as List?)?.cast<String>() ?? [];
    final palmShapeRaw = data['palm_shape'] as Map<String, dynamic>? ?? {};

    // confidence_score is stored as 0-100 in DB, returned as 0-100 from Edge Function
    final rawConfidence =
        (data['confidence_score'] as num?)?.toDouble() ?? 75.0;
    // Normalize to 0-100 range for display
    final normalizedConfidence = rawConfidence > 1.0
        ? rawConfidence
        : rawConfidence * 100.0;

    return PalmAnalysisResult(
      analysisId: analysisId,
      scanId: scanId,
      handSide: data['hand_side'] as String? ?? 'right',
      imageQuality: data['image_quality'] != null
          ? ImageQualityResult.fromJson(
              data['image_quality'] as Map<String, dynamic>,
            )
          : const ImageQualityResult(
              score: 0.8,
              palmDetected: true,
              issues: [],
              suitableForAnalysis: true,
            ),
      overallConfidence: normalizedConfidence,
      overallScore: (data['overall_score'] as num?)?.toInt() ?? 75,
      summaryEn:
          data['summary_en'] as String? ?? data['summary'] as String? ?? '',
      summaryHi: data['summary_hi'] as String? ?? '',
      personality: parseCategoryDirect('personality'),
      loveRelationships: parseCategoryDirect('love_relationships'),
      career: parseCategoryDirect('career'),
      wealth: parseCategoryDirect('wealth'),
      health: parseCategoryDirect('health'),
      lifePath: parseCategoryDirect('life_path'),
      futureTendencies: _parseFutureTendencies(data),
      keyTraitsEn: (data['key_traits_en'] as List?)?.cast<String>() ?? [],
      keyTraitsHi: (data['key_traits_hi'] as List?)?.cast<String>() ?? [],
      dailyInsightEn: data['daily_insight_en'] as String? ?? '',
      dailyInsightHi: data['daily_insight_hi'] as String? ?? '',
      remediesEn: _remedyText(data, hindi: false),
      remediesHi: _remedyText(data, hindi: true),
      confidenceNoteEn: data['confidence_note_en'] as String?,
      confidenceNoteHi: data['confidence_note_hi'] as String?,
      isPremium: data['is_premium'] as bool? ?? false,
      cached: cached,
      processingTimeMs: (data['processing_time_ms'] as num?)?.toInt() ?? 0,
      palmFeatures: palmFeaturesRaw,
      mounts: mountsRaw,
      specialMarks: specialMarksRaw,
      palmShape: palmShapeRaw,
    );
  }
}

/// Remedies live on the Stage B object, or inside personality_analysis after save.
String _remedyText(Map<String, dynamic> data, {required bool hindi}) {
  final direct = data['remedies'];
  if (direct is Map) {
    final key = hindi ? 'content_hi' : 'content_en';
    final text = direct[key] as String? ?? '';
    if (text.isNotEmpty) return text;
  }
  final pa = data['personality_analysis'];
  if (pa is Map) {
    final key = hindi ? 'remedies_hi' : 'remedies_en';
    return pa[key] as String? ?? '';
  }
  return '';
}

/// Parse future_tendencies from either direct Stage B field or DB personality_analysis
AnalysisCategory _parseFutureTendencies(Map<String, dynamic> data) {
  // Try direct Stage B field first
  final direct = data['future_tendencies'];
  if (direct is Map<String, dynamic> && direct.containsKey('content_en')) {
    return AnalysisCategory.fromJson(direct);
  }
  // Fallback: extract from personality_analysis.future_tendencies_*
  final pa = data['personality_analysis'] as Map<String, dynamic>?;
  if (pa != null) {
    return AnalysisCategory(
      titleEn: 'Future Tendencies',
      titleHi: 'भविष्य की प्रवृत्तियां',
      contentEn: pa['future_tendencies_en'] as String? ?? '',
      contentHi: pa['future_tendencies_hi'] as String? ?? '',
      score: (pa['future_tendencies_score'] as num?)?.toInt() ?? 75,
      isPremiumLocked: pa['future_tendencies_locked'] as bool? ?? false,
    );
  }
  return const AnalysisCategory(
    titleEn: 'Future Tendencies',
    titleHi: 'भविष्य की प्रवृत्तियां',
    contentEn: '',
    contentHi: '',
    score: 75,
    isPremiumLocked: true,
  );
}

/// Parse a category from DB-stored analysis fields (fallback)
AnalysisCategory _parseCategoryFromDb(Map<String, dynamic> data, String key) {
  const dbKeyMap = {
    'personality': 'personality_analysis',
    'love_relationships': 'love_analysis',
    'career': 'career_analysis',
    'wealth': 'wealth_analysis',
    'health': 'health_analysis',
    'life_path': 'life_analysis',
  };
  final dbKey = dbKeyMap[key];
  if (dbKey != null) {
    final analysisData = data[dbKey] as Map<String, dynamic>?;
    if (analysisData != null) {
      return AnalysisCategory(
        titleEn: key.replaceAll('_', ' ').toUpperCase(),
        titleHi: '',
        contentEn: analysisData['interpretation_en'] as String? ?? '',
        contentHi: analysisData['interpretation_hi'] as String? ?? '',
        score: (analysisData['score'] as num?)?.toInt() ?? 75,
        isPremiumLocked: analysisData['is_premium_locked'] as bool? ?? false,
      );
    }
  }
  return const AnalysisCategory(
    titleEn: '',
    titleHi: '',
    contentEn: '',
    contentHi: '',
    score: 75,
  );
}

// ── Analysis Stage Enum ───────────────────────────────────────────────────────

enum PalmAnalysisStage {
  idle,
  uploadingImage,
  checkingQuality,
  extractingFeatures,
  generatingReading,
  complete,
  failed,
}

extension PalmAnalysisStageExt on PalmAnalysisStage {
  String labelEn() {
    switch (this) {
      case PalmAnalysisStage.uploadingImage:
        return 'Uploading palm image...';
      case PalmAnalysisStage.checkingQuality:
        return 'Checking image quality...';
      case PalmAnalysisStage.extractingFeatures:
        return 'Identifying palm features...';
      case PalmAnalysisStage.generatingReading:
        return 'Preparing your reading...';
      case PalmAnalysisStage.complete:
        return 'Your reading is ready.';
      default:
        return 'Processing...';
    }
  }

  String labelHi() {
    switch (this) {
      case PalmAnalysisStage.uploadingImage:
        return 'हथेली की छवि अपलोड हो रही है...';
      case PalmAnalysisStage.checkingQuality:
        return 'छवि गुणवत्ता जांची जा रही है...';
      case PalmAnalysisStage.extractingFeatures:
        return 'हथेली की रेखाएं पहचानी जा रही हैं...';
      case PalmAnalysisStage.generatingReading:
        return 'आपका पठन तैयार हो रहा है...';
      case PalmAnalysisStage.complete:
        return 'आपका पठन तैयार है।';
      default:
        return 'प्रक्रिया हो रही है...';
    }
  }

  String labelHinglish() {
    switch (this) {
      case PalmAnalysisStage.uploadingImage:
        return 'Palm image upload ho rahi hai...';
      case PalmAnalysisStage.checkingQuality:
        return 'Image quality check ho rahi hai...';
      case PalmAnalysisStage.extractingFeatures:
        return 'Palm features identify ho rahe hain...';
      case PalmAnalysisStage.generatingReading:
        return 'Aapka reading prepare ho raha hai...';
      case PalmAnalysisStage.complete:
        return 'Aapka reading ready hai.';
      default:
        return 'Processing...';
    }
  }

  String label(String lang) {
    if (lang == 'hi') return labelHi();
    if (lang == 'hi-Latn') return labelHinglish();
    return labelEn();
  }
}

// ── Image Quality Error ───────────────────────────────────────────────────────

/// Raised when the account has used its monthly free scans. Carries the limit
/// so the message can state the actual number rather than a hardcoded one.
class FreeScanLimitException implements Exception {
  final int limit;
  final int used;
  final bool isPremium;

  const FreeScanLimitException({
    required this.limit,
    required this.used,
    this.isPremium = false,
  });
}

/// Raised when the image failed the quality gate.
///
/// Carries the specific [reason] the Edge Function resolved (no palm, blurry,
/// cut off, too dark …) so the screen can show a correction the user can act
/// on rather than a blanket "Scan Failed". The gate itself is unchanged — this
/// only explains a rejection that already happened.
class ImageQualityException implements Exception {
  final double qualityScore;
  final List<String> issues;
  final bool palmDetected;

  /// Specific cause. Falls back to a palm-detected-aware guess for responses
  /// from an Edge Function deployed before `reason` existed.
  final PalmFailureReason reason;

  /// The model's own short description, e.g. "palm is cut off at the bottom".
  final String? detail;

  const ImageQualityException({
    required this.qualityScore,
    required this.issues,
    required this.palmDetected,
    this.reason = PalmFailureReason.lowQualityImage,
    this.detail,
  });

  /// Builds from a 422 payload, tolerating older responses without `reason`.
  factory ImageQualityException.fromPayload(Map payload) {
    final palmDetected = payload['palm_detected'] as bool? ?? false;
    final issues = (payload['issues'] as List?)?.cast<String>() ?? const [];
    final wire = payload['reason'] as String?;

    // Pre-`reason` deployments: infer the only thing that was knowable.
    final resolved = wire != null
        ? PalmFailureReason.fromCode(wire)
        : (palmDetected
              ? PalmFailureReason.lowQualityImage
              : PalmFailureReason.noPalmDetected);

    return ImageQualityException(
      qualityScore: (payload['quality_score'] as num?)?.toDouble() ?? 0.0,
      issues: issues,
      palmDetected: palmDetected,
      reason: resolved,
      detail:
          payload['reason_detail'] as String? ??
          (issues.isNotEmpty ? issues.first : null),
    );
  }

  PalmFailureCopy copy(String lang) =>
      palmFailureCopy(reason, lang: lang, detail: detail);

  String message(String lang) {
    final c = copy(lang);
    return '${c.title}\n\n${c.message}';
  }

  @override
  String toString() =>
      'ImageQualityException(${reason.code}, score: $qualityScore, '
      'palmDetected: $palmDetected, issues: $issues)';
}

/// Resolves the specific failure reason behind any thrown analysis error, so
/// the scan screen can render one consistent, reason-aware error view.
PalmFailureReason palmFailureReasonOf(Object e) {
  if (e is ImageQualityException) return e.reason;
  if (e is FreeScanLimitException) return PalmFailureReason.freeLimitReached;
  if (e is TimeoutException) return PalmFailureReason.aiTimeout;
  if (e is SocketException) return PalmFailureReason.networkError;

  final code = palmAnalysisErrorCode(e);
  if (code != null) {
    final reason = PalmFailureReason.fromCode(code);
    if (reason != PalmFailureReason.unknown) return reason;
  }

  final text = e.toString().toLowerCase();
  if (text.contains('timeout') || text.contains('timed out')) {
    return PalmFailureReason.aiTimeout;
  }
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection closed') ||
      text.contains('no internet')) {
    return PalmFailureReason.networkError;
  }
  if (text.contains('failed to upload') || text.contains('upload palm image')) {
    return PalmFailureReason.uploadFailed;
  }
  return PalmFailureReason.unknown;
}

// ── Error description ─────────────────────────────────────────────────────────

/// The machine-readable `code` an edge function returned, if this error came
/// from one. Lets callers branch on the cause instead of matching on prose.
String? palmAnalysisErrorCode(Object e) {
  if (e is FunctionException) {
    final details = e.details;
    if (details is Map && details['code'] is String) {
      return details['code'] as String;
    }
  }
  return null;
}

/// Turns a thrown analysis error into a message worth showing the user.
///
/// The screen used to replace every failure with a single generic line, which
/// hid causes the user can actually act on — a bad photo, an overloaded model,
/// a dropped connection. Every branch here returns translated, plain-language
/// copy: raw exception text and server diagnostics are deliberately never
/// returned, since this string is shown to non-technical users. The technical
/// detail still reaches the console and the error logger for debugging.
String describePalmAnalysisError(
  Object e, {
  required AppStrings strings,
  required bool isHindi,
}) {
  if (e is ImageQualityException) {
    return e.message(isHindi ? 'hi' : 'en');
  }
  if (e is FreeScanLimitException) {
    return strings.freeScanLimitReached(e.limit);
  }

  switch (palmAnalysisErrorCode(e)) {
    case 'FREE_LIMIT_REACHED':
      return strings.freeScanLimitReached(2);
    case 'AUTH_REQUIRED':
    case 'INVALID_TOKEN':
      return strings.accountRequiredForScan;
    case 'AI_SERVICE_BUSY':
      return strings.aiServiceBusy;
    case 'AI_TIMEOUT':
      return strings.analysisTimedOut;
    // A truncated or malformed model response — the reading never completed.
    case 'AI_RESPONSE_TRUNCATED':
    case 'STAGE_A_FAILED':
    case 'STAGE_B_FAILED':
      return strings.analysisIncomplete;
    case 'IMAGE_DOWNLOAD_FAILED':
    case 'NO_IMAGE':
      return strings.imageUploadProblem;
  }

  // status 0 means the request never reached the function at all.
  if (e is FunctionsFetchException) return strings.noInternetConnection;

  final text = e.toString();
  if (text.contains('TimeoutException') || text.contains('timed out')) {
    return strings.analysisTimedOut;
  }
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return strings.noInternetConnection;
  }

  return strings.unableToCompleteScan;
}

// ── Palm Analysis Service ─────────────────────────────────────────────────────

class PalmAnalysisService {
  static PalmAnalysisService? _instance;
  static PalmAnalysisService get instance =>
      _instance ??= PalmAnalysisService._();
  PalmAnalysisService._();

  final SupabaseService _supabase = SupabaseService.instance;

  static const String _edgeFunctionName = 'palm-analysis';
  static const Duration _analysisTimeout = Duration(seconds: 120);

  // ── Upload palm image ─────────────────────────────────────────────────────

  Future<String?> uploadPalmImage({
    required String scanId,
    required Uint8List imageBytes,
    String fileName = 'palm.jpg',
  }) async {
    return await _supabase.uploadPalmImage(
      scanId: scanId,
      imageBytes: imageBytes,
      fileName: fileName,
    );
  }

  Future<String?> uploadPalmImageFile({
    required String scanId,
    required File imageFile,
  }) async {
    return await _supabase.uploadPalmImageFile(
      scanId: scanId,
      imageFile: imageFile,
      fileName: 'palm_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
  }

  // ── Create scan record ────────────────────────────────────────────────────

  Future<PalmScan?> createScanRecord({required String handType}) async {
    return await _supabase.createPalmScan(handType: handType);
  }

  // ── Run full analysis pipeline ────────────────────────────────────────────

  Future<PalmAnalysisResult> analyzePalm({
    required String scanId,
    required String imagePath,
    required String handSide,
    required String language,
    bool forceReanalysis = false,
    void Function(PalmAnalysisStage stage)? onStageChange,
  }) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) {
      await errorLogger.logAuthError(
        operation: 'palm_analysis_authenticate',
        error: 'No active session',
      );
      throw Exception('User not authenticated');
    }

    onStageChange?.call(PalmAnalysisStage.checkingQuality);

    try {
      final response = await client.functions
          .invoke(
            _edgeFunctionName,
            body: {
              'scan_id': scanId,
              'image_path': imagePath,
              'hand_side': handSide,
              'language': language,
              'force_reanalysis': forceReanalysis,
              // Recorded on server-side failure rows so a capture problem
              // specific to one device or build is visible in the log.
              'client_meta': PalmFailureLogger.clientMeta(),
            },
          )
          .timeout(_analysisTimeout);

      final responseData = response.data;
      if (responseData == null) {
        await errorLogger.logGeminiError(
          operation: 'palm_analysis_response',
          error: 'Empty response from analysis service',
          errorType: 'malformed',
        );
        throw Exception('Empty response from analysis service');
      }

      Map<String, dynamic> data;
      if (responseData is String) {
        try {
          data = jsonDecode(responseData) as Map<String, dynamic>;
        } catch (e) {
          await errorLogger.logGeminiError(
            operation: 'palm_analysis_parse',
            error: e,
            errorType: 'malformed',
          );
          throw Exception('Unexpected response format from analysis service');
        }
      } else if (responseData is Map<String, dynamic>) {
        data = responseData;
      } else {
        await errorLogger.logGeminiError(
          operation: 'palm_analysis_parse',
          error: 'Unexpected response type: ${responseData.runtimeType}',
          errorType: 'malformed',
        );
        throw Exception('Unexpected response format');
      }

      // Check for image quality error
      if (data['code'] == 'LOW_QUALITY_IMAGE' ||
          data['error'] == 'image_quality_insufficient') {
        throw ImageQualityException.fromPayload(data);
      }

      // Check for other errors
      if (data['error'] != null && data['success'] != true) {
        final errMsg = data['error'] as String? ?? 'Analysis failed';
        await errorLogger.logGeminiError(
          operation: 'palm_analysis_result',
          error: errMsg,
        );
        throw Exception(errMsg);
      }

      if (data['success'] != true) {
        await errorLogger.logGeminiError(
          operation: 'palm_analysis_result',
          error: 'Analysis did not complete successfully',
          errorType: 'api_failure',
        );
        throw Exception('Analysis did not complete successfully');
      }

      onStageChange?.call(PalmAnalysisStage.complete);

      return PalmAnalysisResult.fromJson(
        data,
        analysisId: data['analysis_id'] as String? ?? '',
        scanId: scanId,
        cached: data['cached'] as bool? ?? false,
      );
    } on ImageQualityException {
      rethrow;
    } on FreeScanLimitException {
      rethrow;
    } on FunctionException catch (e) {
      // invoke() throws on any non-2xx, so a 422 quality rejection never reaches
      // the LOW_QUALITY_IMAGE branch above. Rebuild the typed exception here so
      // the user still gets the specific "reposition your palm" guidance instead
      // of a generic failure.
      final details = e.details;
      // The monthly free-scan quota returns 403, which also lands here. Rebuild
      // it as a typed exception so the UI can show the real limit and offer the
      // upgrade path instead of a generic failure.
      if (details is Map &&
          (details['code'] == 'FREE_LIMIT_REACHED' ||
              details['code'] == 'SCAN_LIMIT_REACHED')) {
        throw FreeScanLimitException(
          limit: (details['limit'] as num?)?.toInt() ?? 2,
          used: (details['used'] as num?)?.toInt() ?? 0,
          isPremium: details['is_premium'] == true ||
              details['code'] == 'SCAN_LIMIT_REACHED',
        );
      }
      if (details is Map &&
          (details['code'] == 'LOW_QUALITY_IMAGE' ||
              details['error'] == 'image_quality_insufficient')) {
        throw ImageQualityException.fromPayload(details);
      }
      await errorLogger.log(
        category: ErrorCategory.palmAnalysis,
        operation: 'palm_analysis_edge_function',
        userMessage: 'Palm analysis failed. Please try again.',
        error: e,
        severity: ErrorSeverity.high,
      );
      rethrow;
    } on TimeoutException {
      await errorLogger.logGeminiError(
        operation: 'palm_analysis_timeout',
        error: 'Analysis timed out after ${_analysisTimeout.inSeconds}s',
        errorType: 'timeout',
      );
      throw Exception(
        'Analysis timed out. Please check your connection and try again.',
      );
    } catch (e) {
      if (e is ImageQualityException) rethrow;
      debugPrint('PalmAnalysisService.analyzePalm error: $e');
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        await errorLogger.logGeminiError(
          operation: 'palm_analysis_timeout',
          error: e,
          errorType: 'timeout',
        );
        throw Exception(
          'Analysis timed out. Please check your connection and try again.',
        );
      }
      // Log other unexpected errors
      await errorLogger.log(
        category: ErrorCategory.palmAnalysis,
        operation: 'palm_analysis_unexpected',
        userMessage: 'Palm analysis failed. Please try again.',
        error: e,
        severity: ErrorSeverity.high,
      );
      rethrow;
    }
  }

  // ── Get existing analysis ─────────────────────────────────────────────────

  Future<PalmAnalysis?> getLatestAnalysis() async {
    return await _supabase.getLatestAnalysis();
  }

  // ── Get analysis by ID ────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getAnalysisById(String analysisId) async {
    try {
      final data = await Supabase.instance.client
          .from('palm_analysis')
          .select()
          .eq('id', analysisId)
          .eq('user_id', _supabase.currentUserId ?? '')
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('getAnalysisById error: $e');
      return null;
    }
  }
}
