// Browser checkout via Cashfree JS SDK v3. Used when dart.library.io is absent.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _sdkUrl = 'https://sdk.cashfree.com/js/v3/cashfree.js';

extension type _CashfreeClient(JSObject _) implements JSObject {
  external JSPromise<JSObject?> checkout(JSObject options);
}

extension type _CheckoutResult(JSObject _) implements JSObject {
  external JSObject? get error;
  external JSBoolean? get redirect;
}

extension type _CheckoutError(JSObject _) implements JSObject {
  external String? get message;
}

bool get _cashfreeReady =>
    globalContext.getProperty<JSAny?>('Cashfree'.toJS) != null;

/// Opens Cashfree hosted checkout in a modal on the current page.
/// Returns true when the server verifies the payment.
Future<bool?> openCashfreeCheckout({
  required String orderId,
  required String paymentSessionId,
  required String environment,
  required Future<bool> Function(String orderId) onVerifyPayment,
  required void Function(String errorMessage) onError,
}) async {
  if (paymentSessionId.trim().isEmpty) {
    onError('Unable to start payment. Please try again.');
    return false;
  }

  try {
    await _ensureCashfreeSdk();
    final factory = globalContext.getProperty<JSFunction?>('Cashfree'.toJS);
    if (factory == null) {
      onError(
        'Cashfree checkout could not load. Check your connection and try again.',
      );
      return false;
    }

    final mode = environment == 'production' ? 'production' : 'sandbox';
    final created = factory.callAsFunction(null, {'mode': mode}.jsify());
    if (created == null || created.isUndefinedOrNull) {
      onError('Cashfree checkout could not start. Please try again.');
      return false;
    }

    final raw = await _CashfreeClient(created as JSObject)
        .checkout(
          {
            'paymentSessionId': paymentSessionId,
            'redirectTarget': '_modal',
          }.jsify()! as JSObject,
        )
        .toDart;

    if (raw != null && _CheckoutResult(raw).redirect?.toDart == true) {
      // Hosted checkout took over the page; verification happens on return.
      return null;
    }

    final verified = await onVerifyPayment(orderId);
    if (verified) return true;

    final message = raw == null ? null : _CheckoutResult(raw).error;
    final text = message == null ? null : _CheckoutError(message).message;
    final closed = text?.toLowerCase().contains('close') ?? false;
    if (text != null && text.trim().isNotEmpty && !closed) {
      onError(text);
    }
    return false;
  } catch (_) {
    onError('Payment could not be completed. Please try again.');
    return false;
  }
}

Future<void> _ensureCashfreeSdk() async {
  if (_cashfreeReady) return;

  final existing = web.document.querySelector(
    'script[data-cashfree-sdk="v3"]',
  );
  final web.HTMLScriptElement element;
  if (existing != null && existing.isA<web.HTMLScriptElement>()) {
    element = existing as web.HTMLScriptElement;
  } else {
    element = web.document.createElement('script') as web.HTMLScriptElement
      ..src = _sdkUrl
      ..async = true;
    element.setAttribute('data-cashfree-sdk', 'v3');
    web.document.head?.appendChild(element);
  }

  if (_cashfreeReady) return;

  final load = Completer<void>();
  element.addEventListener(
    'load',
    ((web.Event _) {
      if (!load.isCompleted) load.complete();
    }).toJS,
  );
  element.addEventListener(
    'error',
    ((web.Event _) {
      if (!load.isCompleted) {
        load.completeError(StateError('Cashfree script failed to load'));
      }
    }).toJS,
  );

  if (_cashfreeReady) return;
  await load.future.timeout(const Duration(seconds: 20));
  if (!_cashfreeReady) {
    throw StateError('Cashfree SDK missing after load');
  }
}
