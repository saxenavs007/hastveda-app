import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';

/// Opens Cashfree WebCheckout on mobile (Android/iOS).
/// Returns true if payment was verified successfully, false/null otherwise.
///
/// IMPORTANT: Uses a Completer to properly await the SDK callback.
/// The Cashfree SDK's doPayment() returns immediately (fire-and-forget);
/// the actual result arrives asynchronously via the registered callbacks.
/// Without a Completer, the function returns null before the callback fires,
/// causing the paywall to skip the cache-invalidation and success-dialog path.
Future<bool?> openCashfreeCheckout({
  required String orderId,
  required String paymentSessionId,
  required String environment,
  required Future<bool> Function(String orderId) onVerifyPayment,
  required void Function(String errorMessage) onError,
}) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    onError(
      'Cashfree checkout on this device could not start the mobile payment SDK. Use the HastVeda Android or iOS app to pay.',
    );
    return null;
  }

  final cfEnvironment = environment == 'production'
      ? CFEnvironment.PRODUCTION
      : CFEnvironment.SANDBOX;

  // Completer bridges the SDK's fire-and-forget callback model to a proper
  // async/await flow. The function suspends here and resumes only when one
  // of the two SDK callbacks (success or error) completes the Completer.
  final completer = Completer<bool?>();

  try {
    final session = CFSessionBuilder()
        .setEnvironment(cfEnvironment)
        .setOrderId(orderId)
        .setPaymentSessionId(paymentSessionId)
        .build();

    final cfWebCheckout = CFWebCheckoutPaymentBuilder()
        .setSession(session)
        .build();

    final cfPaymentGatewayService = CFPaymentGatewayService();

    cfPaymentGatewayService.setCallback(
      (callbackOrderId) async {
        // Success callback — called when user returns from checkout.
        // Perform server-side verification before resolving.
        if (completer.isCompleted) return;
        try {
          final verified = await onVerifyPayment(callbackOrderId);
          completer.complete(verified);
        } catch (e) {
          onError('Payment verification failed. Please contact support.');
          completer.complete(false);
        }
      },
      (errorResponse, callbackOrderId) {
        // Error callback — called on payment failure or cancellation.
        if (completer.isCompleted) return;
        final message =
            errorResponse.getMessage() ?? 'Payment was not completed';
        onError(message);
        completer.complete(false);
      },
    );

    await cfPaymentGatewayService.doPayment(cfWebCheckout);

    // Wait for the callback to fire and complete the Completer.
    // Add a safety timeout so the UI is never stuck indefinitely.
    return await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        onError('Payment timed out. Please check your payment status.');
        return null;
      },
    );
  } on CFException catch (e) {
    if (!completer.isCompleted) completer.complete(null);
    onError(e.message ?? 'Payment failed. Please try again.');
    return null;
  } catch (e) {
    if (!completer.isCompleted) completer.complete(null);
    onError('Payment failed. Please try again.');
    return null;
  }
}
