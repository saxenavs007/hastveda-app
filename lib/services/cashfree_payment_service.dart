import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// CASHFREE PAYMENT MODELS
// ============================================================

class CashfreeOrderResult {
  final bool success;
  final String? orderId;
  final String? paymentSessionId;
  final double? finalAmount;
  final double? originalAmount;
  final double? discountAmount;
  final double? baseAmount;
  final double? gstRate;
  final double? gstAmount;
  final String? error;

  const CashfreeOrderResult({
    required this.success,
    this.orderId,
    this.paymentSessionId,
    this.finalAmount,
    this.originalAmount,
    this.discountAmount,
    this.baseAmount,
    this.gstRate,
    this.gstAmount,
    this.error,
  });
}

class CashfreeVerifyResult {
  final bool success;
  final String status;
  final bool premiumGranted;
  final bool alreadyPremium;
  final String? error;

  const CashfreeVerifyResult({
    required this.success,
    required this.status,
    this.premiumGranted = false,
    this.alreadyPremium = false,
    this.error,
  });
}

class CouponValidationResult {
  final bool valid;
  final String? error;
  final double? discountAmount;
  final double? finalAmount;
  final String? discountLabel;

  const CouponValidationResult({
    required this.valid,
    this.error,
    this.discountAmount,
    this.finalAmount,
    this.discountLabel,
  });
}

// ============================================================
// CASHFREE PAYMENT SERVICE
// ============================================================

/// Handles all Cashfree payment operations.
/// Secret credentials NEVER leave the server (Edge Functions).
/// This service only communicates with our Supabase Edge Functions.
class CashfreePaymentService {
  static CashfreePaymentService? _instance;
  static CashfreePaymentService get instance =>
      _instance ??= CashfreePaymentService._();
  CashfreePaymentService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Pricing constants (display only — server calculates final) ──
  static const double regularPrice = 299.0;
  static const double launchPrice = 199.0;
  static const double askQuestionPrice = 50.0;

  /// Create a Cashfree order via Edge Function.
  /// [productType] defaults to 'premium'. Pass 'ask_question' for ₹50 question orders.
  Future<CashfreeOrderResult> createOrder({
    String? couponCode,
    String productType = 'premium',
    double? amount,
  }) async {
    try {
      final body = <String, dynamic>{
        'product_type': productType,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode.trim().toUpperCase(),
        if (kIsWeb) 'return_url': Uri.base.removeFragment().toString(),
      };

      final response = await _client.functions.invoke(
        'create-cashfree-order',
        body: body,
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        return const CashfreeOrderResult(
          success: false,
          error: 'No response from payment server',
        );
      }

      if (data['error'] != null) {
        return CashfreeOrderResult(
          success: false,
          error: data['error'] as String,
        );
      }

      return CashfreeOrderResult(
        success: true,
        orderId: data['order_id'] as String?,
        paymentSessionId: data['payment_session_id'] as String?,
        finalAmount: (data['final_amount'] as num?)?.toDouble(),
        originalAmount: (data['original_amount'] as num?)?.toDouble(),
        discountAmount: (data['discount_amount'] as num?)?.toDouble(),
        baseAmount: (data['base_amount'] as num?)?.toDouble(),
        gstRate: (data['gst_rate'] as num?)?.toDouble(),
        gstAmount: (data['gst_amount'] as num?)?.toDouble(),
      );
    } catch (e) {
      debugPrint('createOrder error: $e');
      return CashfreeOrderResult(
        success: false,
        error: 'Failed to create order: ${e.toString()}',
      );
    }
  }

  /// Verify payment status server-side after SDK callback.
  /// This is the authoritative check — never trust client-side SDK result alone.
  Future<CashfreeVerifyResult> verifyPayment(String cashfreeOrderId) async {
    try {
      final response = await _client.functions.invoke(
        'verify-cashfree-payment',
        body: {'cashfree_order_id': cashfreeOrderId},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        return const CashfreeVerifyResult(
          success: false,
          status: 'error',
          error: 'No response from verification server',
        );
      }

      if (data['error'] != null) {
        return CashfreeVerifyResult(
          success: false,
          status: 'error',
          error: data['error'] as String,
        );
      }

      return CashfreeVerifyResult(
        success: data['success'] as bool? ?? false,
        status: data['status'] as String? ?? 'unknown',
        premiumGranted: data['premium_granted'] as bool? ?? false,
        alreadyPremium: data['already_premium'] as bool? ?? false,
        error: data['error'] as String?,
      );
    } catch (e) {
      debugPrint('verifyPayment error: $e');
      return CashfreeVerifyResult(
        success: false,
        status: 'error',
        error: 'Verification failed: ${e.toString()}',
      );
    }
  }

  /// Get user's payment history from Supabase.
  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final data = await _client
          .from('cashfree_orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(20);

      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      debugPrint('getPaymentHistory error: $e');
      return [];
    }
  }
}
