import 'package:flutter/foundation.dart';

import './qa_config.dart';
import './supabase_service.dart';

// ============================================================
// ENTITLEMENT TYPES
// ============================================================

/// Entitlement types matching the database enum.
class EntitlementTypes {
  static const String free = 'FREE';
  static const String premium = 'PREMIUM';
  static const String completeReading = 'COMPLETE_READING';
  static const String coupleReading = 'COUPLE_READING';
  static const String detailedReport = 'DETAILED_REPORT';
}

// ============================================================
// FEATURE KEYS — used with canUseFeature()
// ============================================================

/// FINAL FREE / PREMIUM STRUCTURE — the single source of truth.
///
/// Locked 2026-08-17. Every gate in the app resolves through
/// [PremiumFeatures.isFree] or [EntitlementService.canUseFeature].
/// Nothing may be gated on anything else — not a hardcoded `isLocked` bool,
/// not the AI-returned `is_premium_locked` flag on a palm_analysis row, and
/// not a second copy of a screen. If a surface needs a gate, give it a key
/// below and read the answer from here.
class PremiumFeatures {
  // ── 🟢 FREE ───────────────────────────────────────────────────────────────
  static const String basicScan = 'basic_scan';
  static const String overallAnalysis =
      'overall_analysis'; // Overall Palm Analysis
  static const String palmLines = 'palm_lines'; // Heart / Head / Life, basic
  static const String personality = 'personality';
  static const String loveRelationships = 'love_relationships';
  static const String basicStrengths = 'basic_strengths'; // strengths/character
  static const String todaysInsight = 'todays_insight';
  static const String palmProfile = 'palm_profile'; // basic palm profile

  // ── 🔒 PREMIUM ────────────────────────────────────────────────────────────
  static const String wealthFinances = 'wealth_finances';
  static const String careerBusiness = 'career_business';
  static const String futureTendencies = 'future_tendencies';
  static const String palmMarks = 'palm_marks';
  static const String detailedReport = 'detailed_report';
  static const String deepPredictions =
      'deep_predictions'; // weekly/monthly/yearly
  static const String detailedStrengths = 'detailed_strengths';
  static const String remediesGuidance = 'remedies_guidance';
  static const String advancedAnalysis = 'advanced_analysis';
  static const String askHastVeda = 'ask_hastveda';

  // Premium by default — advanced surfaces that the locked list does not name.
  // They stay behind the paywall until they are explicitly moved to [free].
  static const String sunLine = 'sun_line';
  static const String mercuryLine = 'mercury_line';
  static const String marriageIndicators = 'marriage_indicators';
  static const String mountAnalysis = 'mount_analysis';

  // ── One-time purchases (separate entitlements, not the Premium sub) ───────
  static const String completeReading = 'complete_reading';
  static const String coupleReading = 'couple_reading';

  /// The complete FREE tier. Anything absent from this set is Premium.
  static const Set<String> free = {
    basicScan,
    overallAnalysis,
    palmLines,
    personality,
    loveRelationships,
    basicStrengths,
    todaysInsight,
    palmProfile,
  };

  /// The complete PREMIUM tier — declared explicitly so the structure can be
  /// read off in one place and asserted in tests.
  static const Set<String> premium = {
    wealthFinances,
    careerBusiness,
    futureTendencies,
    palmMarks,
    detailedReport,
    deepPredictions,
    detailedStrengths,
    remediesGuidance,
    advancedAnalysis,
    askHastVeda,
    sunLine,
    mercuryLine,
    marriageIndicators,
    mountAnalysis,
  };

  /// Personalized Ask HastVeda questions included with Premium.
  static const int askHastVedaPremiumQuestions = 2;

  /// Maps a `palm_analysis` category key to its feature key, so the analysis
  /// screen never has to decide tiering for itself.
  static const Map<String, String> analysisCategoryFeature = {
    'personality': personality,
    'love_relationships': loveRelationships,
    'life_path': palmLines,
    'health': palmLines,
    'career': careerBusiness,
    'wealth': wealthFinances,
    'future_tendencies': futureTendencies,
  };

  /// True if the feature is free for everyone.
  static bool isFree(String feature) => free.contains(feature);

  /// Returns true if a feature requires Premium or a specific entitlement.
  static bool isPremiumFeature(String feature) => !free.contains(feature);

  /// Returns the required entitlement type for a feature
  static String requiredEntitlement(String feature) {
    switch (feature) {
      case completeReading:
        return EntitlementTypes.completeReading;
      case coupleReading:
        return EntitlementTypes.coupleReading;
      case detailedReport:
        return EntitlementTypes.detailedReport;
      default:
        return EntitlementTypes.premium;
    }
  }
}

// ============================================================
// PRODUCT IDs — Google Play Billing (disabled until Phase 3)
// ============================================================

class PremiumProducts {
  static const String premiumMonthly = 'hastveda_premium_monthly';
  static const String premiumYearly = 'hastveda_premium_yearly';
  static const String completeReading = 'hastveda_complete_reading';
  static const String coupleReading = 'hastveda_couple_reading';
  static const String detailedReport = 'hastveda_detailed_report';

  /// Google Play Billing is disabled until Phase 3
  static const bool googlePlayBillingEnabled = false;
}

// ============================================================
// FREE TIER LIMITS
// ============================================================

class FreeTierLimits {
  final int scansPerMonth;
  final int predictionsVisible;
  final int historyDays;

  const FreeTierLimits({
    this.scansPerMonth = 2,
    this.predictionsVisible = 3,
    this.historyDays = 7,
  });

  factory FreeTierLimits.fromJson(Map<String, dynamic> json) {
    return FreeTierLimits(
      scansPerMonth: (json['scans_per_month'] as num?)?.toInt() ?? 2,
      predictionsVisible: (json['predictions_visible'] as num?)?.toInt() ?? 3,
      historyDays: (json['history_days'] as num?)?.toInt() ?? 7,
    );
  }
}

// ============================================================
// ENTITLEMENT SERVICE
// ============================================================

/// Centralized entitlement service for HastVeda.
/// All premium access decisions must go through this service.
/// The backend (Supabase) is the single source of truth.
/// The Android client NEVER grants itself Premium.
class EntitlementService {
  static EntitlementService? _instance;
  static EntitlementService get instance =>
      _instance ??= EntitlementService._();
  EntitlementService._();

  final SupabaseService _supabase = SupabaseService.instance;

  // In-memory cache to avoid repeated DB calls in the same session
  List<Entitlement>? _cachedEntitlements;
  DateTime? _cacheTime;
  EntitlementSummary? _cachedSummary;
  FreeTierLimits? _cachedLimits;

  /// Bumped on every fetch and on [invalidateCache]. An in-flight read that
  /// started before a payment refresh must not write FREE back over PREMIUM.
  int _fetchGeneration = 0;

  static const Duration _cacheDuration = Duration(minutes: 5);

  bool get _isCacheValid =>
      _cachedEntitlements != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheDuration;

  /// Invalidate the local cache (call after purchase or sign-in).
  void invalidateCache() {
    _cachedEntitlements = null;
    _cacheTime = null;
    _cachedSummary = null;
    _fetchGeneration++;
  }

  /// Load all active entitlements for the current user.
  ///
  /// [forceRefresh] always hits Postgres. A newer fetch or [invalidateCache]
  /// wins if this call is still in flight, so a pre-payment read cannot
  /// overwrite the post-payment PREMIUM row.
  Future<List<Entitlement>> getEntitlements({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid) {
      return _cachedEntitlements!;
    }
    final generation = ++_fetchGeneration;
    try {
      final entitlements = await _supabase.getUserEntitlements();
      if (generation != _fetchGeneration) {
        return _cachedEntitlements ?? entitlements;
      }
      _cachedEntitlements = entitlements;
      _cacheTime = DateTime.now();
      _cachedSummary = null; // invalidate summary cache
      return entitlements;
    } catch (e) {
      debugPrint('getEntitlements error: $e');
      // Do not cache a failed read as "no entitlements" — that pinned FREE
      // for the cache TTL and only a logout/login cleared it.
      if (generation != _fetchGeneration && _cachedEntitlements != null) {
        return _cachedEntitlements!;
      }
      rethrow;
    }
  }

  /// Check if the user has a specific entitlement.
  Future<bool> hasEntitlement(
    String entitlementType, {
    bool forceRefresh = false,
  }) async {
    try {
      final entitlements = await getEntitlements(forceRefresh: forceRefresh);
      return entitlements.any(
        (e) => e.entitlementType == entitlementType && e.isValid,
      );
    } catch (e) {
      debugPrint('hasEntitlement error: $e');
      return false;
    }
  }

  /// Check if user is a premium subscriber.
  Future<bool> isPremiumUser({bool forceRefresh = false}) =>
      hasEntitlement(EntitlementTypes.premium, forceRefresh: forceRefresh);

  /// Check if user can use a specific feature.
  /// This is the primary feature gate check throughout the app.
  Future<bool> canUseFeature(
    String feature, {
    bool forceRefresh = false,
  }) async {
    // Free features are always accessible
    if (!PremiumFeatures.isPremiumFeature(feature)) return true;

    // Check premium first (covers all premium features)
    final hasPremium = await isPremiumUser(forceRefresh: forceRefresh);
    if (hasPremium) return true;

    // Check specific one-time entitlements
    final requiredEntitlement = PremiumFeatures.requiredEntitlement(feature);
    if (requiredEntitlement != EntitlementTypes.premium) {
      return hasEntitlement(requiredEntitlement, forceRefresh: forceRefresh);
    }

    return false;
  }

  /// Check if user can access a complete reading.
  Future<bool> canAccessCompleteReading({bool forceRefresh = false}) =>
      canUseFeature(
        PremiumFeatures.completeReading,
        forceRefresh: forceRefresh,
      );

  /// Check if user can access couple reading.
  Future<bool> canAccessCoupleReading({bool forceRefresh = false}) =>
      canUseFeature(PremiumFeatures.coupleReading, forceRefresh: forceRefresh);

  /// Check if user can access detailed reports.
  Future<bool> canAccessDetailedReport({bool forceRefresh = false}) =>
      canUseFeature(PremiumFeatures.detailedReport, forceRefresh: forceRefresh);

  /// Get a summary of what the user can access.
  Future<EntitlementSummary> getEntitlementSummary({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedSummary != null && _isCacheValid) {
      return _cachedSummary!;
    }

    final entitlements = await getEntitlements(forceRefresh: forceRefresh);
    final hasPremium = entitlements.any(
      (e) => e.entitlementType == EntitlementTypes.premium && e.isValid,
    );

    final summary = EntitlementSummary(
      hasFree: true,
      hasPremium: hasPremium,
      hasCompleteReading:
          hasPremium ||
          entitlements.any(
            (e) =>
                e.entitlementType == EntitlementTypes.completeReading &&
                e.isValid,
          ),
      hasCoupleReading:
          hasPremium ||
          entitlements.any(
            (e) =>
                e.entitlementType == EntitlementTypes.coupleReading &&
                e.isValid,
          ),
      hasDetailedReport:
          hasPremium ||
          entitlements.any(
            (e) =>
                e.entitlementType == EntitlementTypes.detailedReport &&
                e.isValid,
          ),
      premiumExpiresAt: entitlements
          .where(
            (e) => e.entitlementType == EntitlementTypes.premium && e.isValid,
          )
          .map((e) => e.expiresAt)
          .firstOrNull,
      activeEntitlements: entitlements.where((e) => e.isValid).toList(),
    );

    // A superseded in-flight read must not publish a FREE summary over the
    // entitlements list a newer fetch just cached.
    if (identical(entitlements, _cachedEntitlements)) {
      _cachedSummary = summary;
    }
    return summary;
  }

  /// Get free tier limits from app settings.
  Future<FreeTierLimits> getFreeTierLimits() async {
    if (_cachedLimits != null) return _cachedLimits!;
    try {
      final settings = await _supabase.getAppSettings('free_tier_limits');
      if (settings != null) {
        _cachedLimits = FreeTierLimits.fromJson(settings);
        return _cachedLimits!;
      }
    } catch (e) {
      debugPrint('getFreeTierLimits error: $e');
    }
    return const FreeTierLimits();
  }

  /// Check if user has reached a free tier limit.
  Future<FreeTierLimitResult> checkFreeTierLimit(String limitType) async {
    final hasPremium = await isPremiumUser();
    if (hasPremium) {
      return FreeTierLimitResult(allowed: true, isPremium: true);
    }

    final limits = await getFreeTierLimits();

    switch (limitType) {
      case 'scans_per_month':
        // QA/testing bypass — see lib/services/qa_config.dart for how to
        // switch back to the production 2-scans-per-month limit.
        if (QaConfig.bypassFreeScanQuota) {
          debugPrint(
            '[EntitlementService] scans_per_month check bypassed by QaConfig.bypassFreeScanQuota',
          );
          return FreeTierLimitResult(
            allowed: true,
            limit: limits.scansPerMonth,
            limitType: limitType,
          );
        }
        final count = await _supabase.getMonthlyScansCount();
        return FreeTierLimitResult(
          allowed: count < limits.scansPerMonth,
          current: count,
          limit: limits.scansPerMonth,
          limitType: limitType,
        );
      case 'predictions_visible':
        return FreeTierLimitResult(
          allowed: true,
          limit: limits.predictionsVisible,
          limitType: limitType,
        );
      case 'history_days':
        return FreeTierLimitResult(
          allowed: true,
          limit: limits.historyDays,
          limitType: limitType,
        );
      default:
        return FreeTierLimitResult(allowed: true);
    }
  }

  // ============================================================
  // PURCHASE FLOW (Google Play Billing-ready)
  // ============================================================

  /// Initiate a purchase record before Google Play Billing.
  /// Returns the purchase ID to track the transaction.
  /// NOTE: Actual payment processing is NOT implemented here.
  /// This is the architecture hook for Google Play Billing Phase 3.
  Future<String?> initiatePurchase({
    required String productId,
    required String purchaseType,
  }) async {
    if (!PremiumProducts.googlePlayBillingEnabled) {
      debugPrint('Google Play Billing is disabled. Phase 3 pending.');
      return null;
    }
    try {
      final purchase = await _supabase.recordPurchasePending(
        productId: productId,
        purchaseType: purchaseType,
      );
      return purchase?.id;
    } catch (e) {
      debugPrint('initiatePurchase error: $e');
      return null;
    }
  }

  /// Called after Google Play returns a purchase token.
  /// The actual entitlement grant happens server-side after verification.
  /// This method only records the token — it does NOT grant access.
  Future<bool> submitPurchaseToken({
    required String purchaseId,
    required String purchaseToken,
    required String orderId,
  }) async {
    try {
      final purchase = await _supabase.updatePurchaseToken(
        purchaseId: purchaseId,
        purchaseToken: purchaseToken,
        orderId: orderId,
      );
      if (purchase != null) {
        invalidateCache();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('submitPurchaseToken error: $e');
      return false;
    }
  }

  /// Restore purchases — refresh entitlements from server.
  Future<EntitlementSummary> restorePurchases() async {
    invalidateCache();
    return getEntitlementSummary(forceRefresh: true);
  }
}

// ============================================================
// RESULT MODELS
// ============================================================

/// Summary of what a user can access.
class EntitlementSummary {
  final bool hasFree;
  final bool hasPremium;
  final bool hasCompleteReading;
  final bool hasCoupleReading;
  final bool hasDetailedReport;
  final DateTime? premiumExpiresAt;
  final List<Entitlement> activeEntitlements;

  const EntitlementSummary({
    required this.hasFree,
    required this.hasPremium,
    required this.hasCompleteReading,
    required this.hasCoupleReading,
    required this.hasDetailedReport,
    this.premiumExpiresAt,
    this.activeEntitlements = const [],
  });

  bool get isPremiumActive => hasPremium;

  String get tierLabel => hasPremium ? 'Premium' : 'Free';

  String get tierLabelHi => hasPremium ? 'प्रीमियम' : 'निःशुल्क';
}

/// Result of a free tier limit check.
class FreeTierLimitResult {
  final bool allowed;
  final bool isPremium;
  final int? current;
  final int? limit;
  final String? limitType;

  const FreeTierLimitResult({
    required this.allowed,
    this.isPremium = false,
    this.current,
    this.limit,
    this.limitType,
  });

  bool get hasReachedLimit => !allowed && !isPremium;
}
