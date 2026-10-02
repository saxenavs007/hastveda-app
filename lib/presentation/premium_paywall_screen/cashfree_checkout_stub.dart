// Stub for web platform — Cashfree SDK not supported on web
Future<bool?> openCashfreeCheckout({
  required String orderId,
  required String paymentSessionId,
  required String environment,
  required Future<bool> Function(String orderId) onVerifyPayment,
  required void Function(String errorMessage) onError,
}) async {
  onError('Cashfree payments are only available in the Android app.');
  return null;
}
