import 'dart:typed_data';

import './pdf_export_service.dart';

// Stub implementation — should never be used at runtime.
// Replaced by pdf_export_web.dart or pdf_export_io.dart via conditional imports.

Future<void> downloadOrSharePdf(
  Uint8List bytes,
  String filename, {
  bool share = false,
}) async {
  throw UnsupportedError('PDF download not supported on this platform.');
}

Future<RawHttpResponse> callFunctionRaw({
  required String url,
  required String token,
  required Map<String, dynamic> body,
}) async {
  throw UnsupportedError('HTTP not supported on this platform.');
}
