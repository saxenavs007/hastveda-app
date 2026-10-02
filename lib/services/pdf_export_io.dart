import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import './pdf_export_service.dart';

// Mobile/IO implementation for PDF download and share

Future<void> downloadOrSharePdf(
  Uint8List bytes,
  String filename, {
  bool share = false,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);
    debugPrint('PDF saved to: ${file.path}');
    if (share) {
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], text: 'HastVeda Palm Reading Report');
    }
  } catch (e) {
    debugPrint('downloadOrSharePdf error: $e');
    rethrow;
  }
}

Future<RawHttpResponse> callFunctionRaw({
  required String url,
  required String token,
  required Map<String, dynamic> body,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 120);

  try {
    final uri = Uri.parse(url);
    final request = await client.postUrl(uri);
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/pdf, application/json');

    final bodyStr = jsonEncode(body);
    final bodyBytes = utf8.encode(bodyStr);
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);

    final response = await request.close().timeout(
      const Duration(seconds: 120),
    );
    final responseBytes = await _consolidateBytes(response);

    return RawHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: responseBytes,
    );
  } finally {
    client.close();
  }
}

Future<Uint8List> _consolidateBytes(HttpClientResponse response) async {
  final chunks = <List<int>>[];
  await for (final chunk in response) {
    chunks.add(chunk);
  }
  final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final result = Uint8List(totalLength);
  var offset = 0;
  for (final chunk in chunks) {
    result.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return result;
}
