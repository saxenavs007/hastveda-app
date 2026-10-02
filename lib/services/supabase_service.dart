import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import './error_logger.dart';

// ============================================================
// MODELS
// ============================================================

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? phone;
  final DateTime? dateOfBirth;
  final String? gender;
  final String languagePreference;
  final String tier;
  final bool isActive;
  final bool onboardingCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.languagePreference = 'en',
    this.tier = 'free',
    this.isActive = true,
    this.onboardingCompleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPremium => tier == 'premium';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'] as String)
          : null,
      gender: json['gender'] as String?,
      languagePreference: json['language_preference'] as String? ?? 'en',
      tier: json['tier'] as String? ?? 'free',
      isActive: json['is_active'] as bool? ?? true,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'phone': phone,
    'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
    'gender': gender,
    'language_preference': languagePreference,
    'tier': tier,
    'is_active': isActive,
    'onboarding_completed': onboardingCompleted,
  };
}

class PalmScan {
  final String id;
  final String userId;
  final String handType;
  final String? imagePath;
  final String imageBucket;
  final String status;
  final double? qualityScore;
  final Map<String, dynamic> scanMetadata;
  final DateTime createdAt;

  const PalmScan({
    required this.id,
    required this.userId,
    required this.handType,
    this.imagePath,
    this.imageBucket = 'palm-images',
    required this.status,
    this.qualityScore,
    this.scanMetadata = const {},
    required this.createdAt,
  });

  factory PalmScan.fromJson(Map<String, dynamic> json) {
    return PalmScan(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      handType: json['hand_type'] as String? ?? 'right',
      imagePath: json['image_path'] as String?,
      imageBucket: json['image_bucket'] as String? ?? 'palm-images',
      status: json['status'] as String? ?? 'pending',
      qualityScore: (json['quality_score'] as num?)?.toDouble(),
      scanMetadata: (json['scan_metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class PalmAnalysis {
  final String id;
  final String scanId;
  final String userId;
  final String status;
  final String? aiModel;
  final Map<String, dynamic> lifeAnalysis;
  final Map<String, dynamic> loveAnalysis;
  final Map<String, dynamic> careerAnalysis;
  final Map<String, dynamic> healthAnalysis;
  final Map<String, dynamic> wealthAnalysis;
  final Map<String, dynamic> personalityAnalysis;
  final String? summary;
  final double? confidenceScore;
  final DateTime createdAt;

  const PalmAnalysis({
    required this.id,
    required this.scanId,
    required this.userId,
    required this.status,
    this.aiModel,
    this.lifeAnalysis = const {},
    this.loveAnalysis = const {},
    this.careerAnalysis = const {},
    this.healthAnalysis = const {},
    this.wealthAnalysis = const {},
    this.personalityAnalysis = const {},
    this.summary,
    this.confidenceScore,
    required this.createdAt,
  });

  factory PalmAnalysis.fromJson(Map<String, dynamic> json) {
    return PalmAnalysis(
      id: json['id'] as String,
      scanId: json['scan_id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String? ?? 'pending',
      aiModel: json['ai_model'] as String?,
      lifeAnalysis: (json['life_analysis'] as Map<String, dynamic>?) ?? {},
      loveAnalysis: (json['love_analysis'] as Map<String, dynamic>?) ?? {},
      careerAnalysis: (json['career_analysis'] as Map<String, dynamic>?) ?? {},
      healthAnalysis: (json['health_analysis'] as Map<String, dynamic>?) ?? {},
      wealthAnalysis: (json['wealth_analysis'] as Map<String, dynamic>?) ?? {},
      personalityAnalysis:
          (json['personality_analysis'] as Map<String, dynamic>?) ?? {},
      summary: json['summary'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class Prediction {
  final String id;
  final String userId;
  final String? analysisId;
  final String predictionType;
  final String timePeriod;
  final String title;
  final String content;
  final String? shortSummary;
  final String? category;
  final bool isPremium;
  final bool isFeatured;
  final DateTime createdAt;

  const Prediction({
    required this.id,
    required this.userId,
    this.analysisId,
    required this.predictionType,
    required this.timePeriod,
    required this.title,
    required this.content,
    this.shortSummary,
    this.category,
    this.isPremium = false,
    this.isFeatured = false,
    required this.createdAt,
  });

  factory Prediction.fromJson(Map<String, dynamic> json) {
    return Prediction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      analysisId: json['analysis_id'] as String?,
      predictionType: json['prediction_type'] as String,
      timePeriod: json['time_period'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      shortSummary: json['short_summary'] as String?,
      category: json['category'] as String?,
      isPremium: json['is_premium'] as bool? ?? false,
      isFeatured: json['is_featured'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class Entitlement {
  final String id;
  final String userId;
  final String entitlementType;
  final bool isActive;
  final DateTime grantedAt;
  final DateTime? expiresAt;

  const Entitlement({
    required this.id,
    required this.userId,
    required this.entitlementType,
    required this.isActive,
    required this.grantedAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isValid => isActive && !isExpired;

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    return Entitlement(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      entitlementType: json['entitlement_type'] as String,
      isActive: json['is_active'] as bool? ?? false,
      grantedAt: DateTime.parse(json['granted_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }
}

class Purchase {
  final String id;
  final String userId;
  final String productId;
  final String purchaseType;
  final String status;
  final String? purchaseToken;
  final String? orderId;
  final DateTime? purchaseTime;
  final DateTime createdAt;

  const Purchase({
    required this.id,
    required this.userId,
    required this.productId,
    required this.purchaseType,
    required this.status,
    this.purchaseToken,
    this.orderId,
    this.purchaseTime,
    required this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      purchaseType: json['purchase_type'] as String? ?? 'one_time',
      status: json['status'] as String? ?? 'pending',
      purchaseToken: json['purchase_token'] as String?,
      orderId: json['order_id'] as String?,
      purchaseTime: json['purchase_time'] != null
          ? DateTime.tryParse(json['purchase_time'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ReadingHistory {
  final String id;
  final String userId;
  final String? scanId;
  final String? analysisId;
  final String readingType;
  final String title;
  final String? summary;
  final bool isComplete;
  final bool isPremium;
  final DateTime viewedAt;

  const ReadingHistory({
    required this.id,
    required this.userId,
    this.scanId,
    this.analysisId,
    required this.readingType,
    required this.title,
    this.summary,
    this.isComplete = false,
    this.isPremium = false,
    required this.viewedAt,
  });

  factory ReadingHistory.fromJson(Map<String, dynamic> json) {
    return ReadingHistory(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      scanId: json['scan_id'] as String?,
      analysisId: json['analysis_id'] as String?,
      readingType: json['reading_type'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String?,
      isComplete: json['is_complete'] as bool? ?? false,
      isPremium: json['is_premium'] as bool? ?? false,
      viewedAt: DateTime.parse(json['viewed_at'] as String),
    );
  }
}

// ============================================================
// PRODUCT CATALOG (Google Play Billing-ready)
// ============================================================

class ProductInfo {
  final String productId;
  final String type;
  final String displayPrice;
  final String entitlement;
  final int? durationDays;

  const ProductInfo({
    required this.productId,
    required this.type,
    required this.displayPrice,
    required this.entitlement,
    this.durationDays,
  });

  static const List<ProductInfo> catalog = [
    ProductInfo(
      productId: 'hastveda_premium_monthly',
      type: 'subscription',
      displayPrice: '₹199',
      entitlement: 'PREMIUM',
      durationDays: 30,
    ),
    ProductInfo(
      productId: 'hastveda_premium_yearly',
      type: 'subscription',
      displayPrice: '₹199',
      entitlement: 'PREMIUM',
      durationDays: 365,
    ),
    ProductInfo(
      productId: 'hastveda_complete_reading',
      type: 'one_time',
      displayPrice: '₹199',
      entitlement: 'COMPLETE_READING',
    ),
    ProductInfo(
      productId: 'hastveda_couple_reading',
      type: 'one_time',
      displayPrice: '₹199',
      entitlement: 'COUPLE_READING',
    ),
    ProductInfo(
      productId: 'hastveda_detailed_report',
      type: 'one_time',
      displayPrice: '₹199',
      entitlement: 'DETAILED_REPORT',
    ),
  ];
}

// ============================================================
// SUPABASE SERVICE
// ============================================================

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  static Future<void> initialize() async {
    final url = SupabaseConfig.url;
    final anonKey = SupabaseConfig.anonKey;

    if (url.isEmpty || anonKey.isEmpty) {
      throw Exception(
        'SUPABASE_URL and SUPABASE_ANON_KEY are not configured. '
        'Ensure env.json contains valid values and the APK is built '
        'with --dart-define flags injected by the Rocket build pipeline.',
      );
    }
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;
  String? get currentUserId => client.auth.currentUser?.id;
  bool get isAuthenticated => currentUser != null;

  // ============================================================
  // AUTH
  // ============================================================

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      return await client.auth.signUp(
        email: email,
        password: password,
        data: fullName != null ? {'full_name': fullName} : null,
      );
    } on AuthException catch (e) {
      await errorLogger.logAuthError(operation: 'sign_up', error: e.message);
      rethrow;
    } catch (e) {
      await errorLogger.logAuthError(operation: 'sign_up', error: e);
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      await errorLogger.logAuthError(operation: 'sign_in', error: e.message);
      rethrow;
    } catch (e) {
      await errorLogger.logAuthError(operation: 'sign_in', error: e);
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      await errorLogger.logAuthError(operation: 'sign_out', error: e);
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await client.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      await errorLogger.logAuthError(
        operation: 'reset_password',
        error: e.message,
      );
      rethrow;
    }
  }

  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // ============================================================
  // USER PROFILE
  // ============================================================

  Future<UserProfile?> getUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return data != null ? UserProfile.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('getUserProfile error: ${e.message}');
      await errorLogger.logSupabaseError(
        operation: 'get_user_profile',
        error: e.message,
      );
      return null;
    }
  }

  Future<UserProfile?> updateUserProfile(Map<String, dynamic> updates) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('user_profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .maybeSingle();
      return data != null ? UserProfile.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('updateUserProfile error: ${e.message}');
      return null;
    }
  }

  Future<void> completeOnboarding() async {
    await updateUserProfile({'onboarding_completed': true});
  }

  // ============================================================
  // ENTITLEMENTS
  // ============================================================

  Future<List<Entitlement>> getUserEntitlements() async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final data = await client
          .from('entitlements')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true);
      return (data as List)
          .map((e) => Entitlement.fromJson(e as Map<String, dynamic>))
          .where((e) => e.isValid)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('getUserEntitlements error: ${e.message}');
      // Propagate so callers do not treat a failed SELECT as "no Premium".
      rethrow;
    }
  }

  Future<bool> hasEntitlement(String entitlementType) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final data = await client
          .from('entitlements')
          .select('id, expires_at')
          .eq('user_id', userId)
          .eq('entitlement_type', entitlementType)
          .eq('is_active', true)
          .maybeSingle();
      if (data == null) return false;
      final expiresAt = data['expires_at'] as String?;
      if (expiresAt == null) return true;
      return DateTime.parse(expiresAt).isAfter(DateTime.now());
    } on PostgrestException catch (e) {
      debugPrint('hasEntitlement error: ${e.message}');
      return false;
    }
  }

  Future<bool> isPremiumUser() async => hasEntitlement('PREMIUM');

  // ============================================================
  // PURCHASES (Google Play Billing-ready)
  // ============================================================

  /// Record a pending purchase before Google Play verification.
  /// Call this when user initiates a purchase.
  Future<Purchase?> recordPurchasePending({
    required String productId,
    required String purchaseType,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('purchases')
          .insert({
            'user_id': userId,
            'product_id': productId,
            'purchase_type': purchaseType,
            'status': 'pending',
          })
          .select()
          .maybeSingle();
      return data != null ? Purchase.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('recordPurchasePending error: ${e.message}');
      return null;
    }
  }

  /// Update purchase with Google Play token after purchase completes.
  /// Actual verification must happen server-side via Edge Function.
  Future<Purchase?> updatePurchaseToken({
    required String purchaseId,
    required String purchaseToken,
    required String orderId,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('purchases')
          .update({
            'purchase_token': purchaseToken,
            'order_id': orderId,
            'status': 'pending',
            'purchase_time': DateTime.now().toIso8601String(),
          })
          .eq('id', purchaseId)
          .eq('user_id', userId)
          .select()
          .maybeSingle();
      return data != null ? Purchase.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('updatePurchaseToken error: ${e.message}');
      return null;
    }
  }

  Future<List<Purchase>> getUserPurchases() async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final data = await client
          .from('purchases')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => Purchase.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('getUserPurchases error: ${e.message}');
      return [];
    }
  }

  // ============================================================
  // PALM SCANS
  // ============================================================

  Future<PalmScan?> createPalmScan({
    required String handType,
    Map<String, dynamic> deviceInfo = const {},
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('palm_scans')
          .insert({
            'user_id': userId,
            'hand_type': handType,
            'status': 'pending',
            'device_info': deviceInfo,
          })
          .select()
          .maybeSingle();
      return data != null ? PalmScan.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint(
        'createPalmScan error — code: ${e.code} | message: ${e.message} | details: ${e.details} | hint: ${e.hint}',
      );
      return null;
    }
  }

  Future<PalmScan?> updateScanStatus(
    String scanId,
    String status, {
    String? imagePath,
    double? qualityScore,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final updates = <String, dynamic>{'status': status};
      if (imagePath != null) updates['image_path'] = imagePath;
      if (qualityScore != null) updates['quality_score'] = qualityScore;

      final data = await client
          .from('palm_scans')
          .update(updates)
          .eq('id', scanId)
          .eq('user_id', userId)
          .select()
          .maybeSingle();
      return data != null ? PalmScan.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('updateScanStatus error: ${e.message}');
      return null;
    }
  }

  Future<List<PalmScan>> getUserScans({int limit = 20}) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final data = await client
          .from('palm_scans')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((e) => PalmScan.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('getUserScans error: ${e.message}');
      return [];
    }
  }

  // ============================================================
  // PALM IMAGE STORAGE (private bucket)
  // ============================================================

  /// Upload palm image to private bucket.
  /// Path format: {userId}/{scanId}/{filename}
  Future<String?> uploadPalmImage({
    required String scanId,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final path = '$userId/$scanId/$fileName';
      await client.storage
          .from('palm-images')
          .uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      return path;
    } catch (e) {
      debugPrint('uploadPalmImage error: $e');
      return null;
    }
  }

  /// Upload palm image from file (mobile)
  Future<String?> uploadPalmImageFile({
    required String scanId,
    required File imageFile,
    required String fileName,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final path = '$userId/$scanId/$fileName';
      await client.storage
          .from('palm-images')
          .upload(
            path,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );
      return path;
    } catch (e) {
      debugPrint('uploadPalmImageFile error: $e');
      return null;
    }
  }

  /// Get signed URL for private palm image (valid 1 hour)
  Future<String?> getPalmImageSignedUrl(
    String imagePath, {
    int expiresInSeconds = 3600,
  }) async {
    try {
      final url = await client.storage
          .from('palm-images')
          .createSignedUrl(imagePath, expiresInSeconds);
      return url;
    } catch (e) {
      debugPrint('getPalmImageSignedUrl error: $e');
      return null;
    }
  }

  Future<void> deletePalmImage(String imagePath) async {
    try {
      await client.storage.from('palm-images').remove([imagePath]);
    } catch (e) {
      debugPrint('deletePalmImage error: $e');
    }
  }

  // ============================================================
  // PALM ANALYSIS
  // ============================================================

  Future<PalmAnalysis?> createPalmAnalysis({
    required String scanId,
    String? featuresId,
    String aiModel = 'gemini-1.5-pro',
    String aiProvider = 'google',
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('palm_analysis')
          .insert({
            'scan_id': scanId,
            'user_id': userId,
            'features_id': featuresId,
            'status': 'pending',
            'ai_model': aiModel,
            'ai_provider': aiProvider,
          })
          .select()
          .maybeSingle();
      return data != null ? PalmAnalysis.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('createPalmAnalysis error: ${e.message}');
      return null;
    }
  }

  Future<PalmAnalysis?> updatePalmAnalysis(
    String analysisId,
    Map<String, dynamic> updates,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('palm_analysis')
          .update(updates)
          .eq('id', analysisId)
          .eq('user_id', userId)
          .select()
          .maybeSingle();
      return data != null ? PalmAnalysis.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('updatePalmAnalysis error: ${e.message}');
      return null;
    }
  }

  Future<PalmAnalysis?> getLatestAnalysis() async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('palm_analysis')
          .select()
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return data != null ? PalmAnalysis.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('getLatestAnalysis error: ${e.message}');
      return null;
    }
  }

  // ============================================================
  // PREDICTIONS
  // ============================================================

  Future<List<Prediction>> getUserPredictions({
    String? timePeriod,
    String? predictionType,
    int limit = 20,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      var query = client.from('predictions').select().eq('user_id', userId);

      if (timePeriod != null) {
        query = query.eq('time_period', timePeriod);
      }
      if (predictionType != null) {
        query = query.eq('prediction_type', predictionType);
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List)
          .map((e) => Prediction.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('getUserPredictions error: ${e.message}');
      return [];
    }
  }

  Future<Prediction?> createPrediction({
    required String predictionType,
    required String timePeriod,
    required String title,
    required String content,
    String? analysisId,
    String? shortSummary,
    String? category,
    bool isPremium = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('predictions')
          .insert({
            'user_id': userId,
            'analysis_id': analysisId,
            'prediction_type': predictionType,
            'time_period': timePeriod,
            'title': title,
            'content': content,
            'short_summary': shortSummary,
            'category': category,
            'is_premium': isPremium,
          })
          .select()
          .maybeSingle();
      return data != null ? Prediction.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('createPrediction error: ${e.message}');
      return null;
    }
  }

  // ============================================================
  // READING HISTORY
  // ============================================================

  Future<List<ReadingHistory>> getReadingHistory({int limit = 20}) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final data = await client
          .from('reading_history')
          .select()
          .eq('user_id', userId)
          .order('viewed_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((e) => ReadingHistory.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('getReadingHistory error: ${e.message}');
      return [];
    }
  }

  Future<ReadingHistory?> addReadingHistory({
    required String readingType,
    required String title,
    String? scanId,
    String? analysisId,
    String? summary,
    bool isPremium = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final data = await client
          .from('reading_history')
          .insert({
            'user_id': userId,
            'scan_id': scanId,
            'analysis_id': analysisId,
            'reading_type': readingType,
            'title': title,
            'summary': summary,
            'is_premium': isPremium,
          })
          .select()
          .maybeSingle();
      return data != null ? ReadingHistory.fromJson(data) : null;
    } on PostgrestException catch (e) {
      debugPrint('addReadingHistory error: ${e.message}');
      return null;
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  Future<List<Map<String, dynamic>>> getNotifications({int limit = 30}) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final data = await client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('sent_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (e) {
      debugPrint('getNotifications error: ${e.message}');
      return [];
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      debugPrint('markNotificationRead error: ${e.message}');
    }
  }

  Future<int> getUnreadNotificationCount() async {
    final userId = currentUserId;
    if (userId == null) return 0;
    try {
      final response = await client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false)
          .count(CountOption.exact);
      return response.count ?? 0;
    } on PostgrestException catch (e) {
      debugPrint('getUnreadNotificationCount error: ${e.message}');
      return 0;
    }
  }

  // ============================================================
  // ANALYTICS
  // ============================================================

  Future<void> trackEvent({
    required String eventName,
    String? eventCategory,
    Map<String, dynamic> properties = const {},
    String? sessionId,
  }) async {
    try {
      await client.from('analytics_events').insert({
        'user_id': currentUserId,
        'event_name': eventName,
        'event_category': eventCategory,
        'properties': properties,
        'session_id': sessionId,
        'platform': kIsWeb ? 'web' : 'android',
      });
    } on PostgrestException catch (e) {
      debugPrint('trackEvent error: ${e.message}');
    }
  }

  // ============================================================
  // APP SETTINGS
  // ============================================================

  Future<Map<String, dynamic>?> getAppSetting(String key) async {
    try {
      final data = await client
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .eq('is_public', true)
          .maybeSingle();
      return data?['value'] as Map<String, dynamic>?;
    } on PostgrestException catch (e) {
      debugPrint('getAppSetting error: ${e.message}');
      return null;
    }
  }

  Future<Map<String, dynamic>> getGooglePlayProducts() async {
    final setting = await getAppSetting('google_play_products');
    return setting ?? {};
  }

  Future<Map<String, dynamic>> getFeatureFlags() async {
    final setting = await getAppSetting('feature_flags');
    return setting ??
        {'google_play_billing_enabled': false, 'ai_analysis_enabled': true};
  }

  /// Alias for getAppSetting — used by EntitlementService
  Future<Map<String, dynamic>?> getAppSettings(String key) =>
      getAppSetting(key);

  /// Count how many palm scans the user has done this calendar month
  Future<int> getMonthlyScansCount() async {
    final userId = currentUserId;
    if (userId == null) return 0;
    try {
      final startOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      ).toIso8601String();
      final response = await client
          .from('palm_scans')
          .select('id')
          .eq('user_id', userId)
          .gte('created_at', startOfMonth)
          .count(CountOption.exact);
      return response.count ?? 0;
    } on PostgrestException catch (e) {
      debugPrint('getMonthlyScansCount error: ${e.message}');
      return 0;
    }
  }
}
