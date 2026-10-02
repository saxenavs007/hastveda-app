import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';

import './pdf_export_service.dart';

// Web implementation for PDF download
// Uses dart:html to trigger a browser download
// share parameter is ignored on web (no share sheet)

// ignore: avoid_web_libraries_in_flutter

Future<void> downloadOrSharePdf(
  Uint8List bytes,
  String filename, {
  bool share = false,
}) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<RawHttpResponse> callFunctionRaw({
  required String url,
  required String token,
  required Map<String, dynamic> body,
}) async {
  final bodyStr = _encodeBody(body);

  final result = await html.HttpRequest.request(
    url,
    method: 'POST',
    requestHeaders: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    sendData: bodyStr,
    responseType: 'arraybuffer',
  );

  Uint8List bytes;
  try {
    final buffer = result.response;
    bytes = Uint8List.view(buffer as dynamic);
  } catch (_) {
    bytes = Uint8List(0);
  }

  return RawHttpResponse(statusCode: result.status ?? 500, bodyBytes: bytes);
}

String _encodeBody(Map<String, dynamic> body) {
  final parts = <String>[];
  body.forEach((k, v) {
    final key = '"$k"';
    final val = v is String ? '"$v"' : '$v';
    parts.add('$key:$val');
  });
  return '{${parts.join(',')}}';
}
