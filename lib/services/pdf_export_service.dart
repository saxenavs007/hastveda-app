// HastVeda PDF Export Service
// Calls the pdf-export Edge Function, receives PDF bytes,
// and downloads/shares the file on the current platform.
//
// Web: triggers browser download via dart:html anchor click
// Mobile: saves to temp directory, optionally shares via Android share sheet

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './error_logger.dart';
// ignore: uri_does_not_exist
import 'pdf_export_stub.dart'
    if (dart.library.html) 'pdf_export_web.dart'
    if (dart.library.io) 'pdf_export_io.dart';

// ── Raw HTTP response wrapper ─────────────────────────────────────────────────
class RawHttpResponse {
  final int statusCode;
  final Uint8List bodyBytes;
  const RawHttpResponse({required this.statusCode, required this.bodyBytes});
}

// ── Result type ───────────────────────────────────────────────────────────────
class PdfExportResult {
  final bool success;
  final bool entitlementRequired;
  final String? filename;
  final String? errorMessage;

  const PdfExportResult._({
    required this.success,
    required this.entitlementRequired,
    this.filename,
    this.errorMessage,
  });

  factory PdfExportResult.success(String filename) => PdfExportResult._(
    success: true,
    entitlementRequired: false,
    filename: filename,
  );

  factory PdfExportResult.failure(String message) => PdfExportResult._(
    success: false,
    entitlementRequired: false,
    errorMessage: message,
  );

  factory PdfExportResult.entitlementRequired(String message) =>
      PdfExportResult._(
        success: false,
        entitlementRequired: true,
        errorMessage: message,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────
class PdfExportService {
  static PdfExportService? _instance;
  static PdfExportService get instance => _instance ??= PdfExportService._();
  PdfExportService._();

  /// Export a Detailed Report PDF (download).
  Future<PdfExportResult> exportDetailedReport({
    required String reportId,
    required String locale,
  }) async {
    return _export(
      body: {
        'report_type': 'detailed_report',
        'report_id': reportId,
        'locale': locale,
      },
      filename: 'hastveda-palm-report-${_dateStamp()}.pdf',
      share: false,
    );
  }

  /// Share a Detailed Report PDF via Android share sheet.
  Future<PdfExportResult> shareDetailedReport({
    required String reportId,
    required String locale,
  }) async {
    return _export(
      body: {
        'report_type': 'detailed_report',
        'report_id': reportId,
        'locale': locale,
      },
      filename: 'hastveda-palm-report-${_dateStamp()}.pdf',
      share: true,
    );
  }

  /// Export a Couple Reading PDF.
  Future<PdfExportResult> exportCoupleReading({
    required String coupleReadingId,
    required String locale,
  }) async {
    return _export(
      body: {
        'report_type': 'couple_reading',
        'couple_reading_id': coupleReadingId,
        'locale': locale,
      },
      filename: 'hastveda-couple-reading-${_dateStamp()}.pdf',
      share: false,
    );
  }

  Future<PdfExportResult> _export({
    required Map<String, dynamic> body,
    required String filename,
    bool share = false,
  }) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        await errorLogger.logAuthError(
          operation: 'pdf_export_authenticate',
          error: 'No active session',
        );
        return PdfExportResult.failure('Not authenticated. Please sign in.');
      }

      final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
      final functionUrl = '$supabaseUrl/functions/v1/pdf-export';

      final response = await callFunctionRaw(
        url: functionUrl,
        token: session.accessToken,
        body: body,
      );

      if (response.statusCode == 403) {
        String errorMsg = 'Premium subscription required.';
        bool isEntitlement = false;
        try {
          final errorJson =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          final code = errorJson['code'] as String? ?? '';
          errorMsg = errorJson['error'] as String? ?? errorMsg;
          isEntitlement = code == 'ENTITLEMENT_REQUIRED';
        } catch (_) {}
        if (isEntitlement) return PdfExportResult.entitlementRequired(errorMsg);
        await errorLogger.log(
          category: ErrorCategory.pdfExport,
          operation: 'pdf_export_forbidden',
          userMessage: errorMsg,
          severity: ErrorSeverity.medium,
        );
        return PdfExportResult.failure(errorMsg);
      }

      if (response.statusCode != 200) {
        String errorMsg = 'PDF generation failed (${response.statusCode}).';
        try {
          final errorJson =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          errorMsg = errorJson['error'] as String? ?? errorMsg;
        } catch (_) {}
        await errorLogger.log(
          category: ErrorCategory.pdfExport,
          operation: 'pdf_export_http_error',
          userMessage: 'PDF generation failed.',
          error: 'HTTP ${response.statusCode}',
          severity: ErrorSeverity.medium,
        );
        return PdfExportResult.failure(errorMsg);
      }

      final pdfBytes = response.bodyBytes;
      if (pdfBytes.isEmpty) {
        await errorLogger.log(
          category: ErrorCategory.pdfExport,
          operation: 'pdf_export_empty_response',
          userMessage: 'Received empty PDF from server.',
          severity: ErrorSeverity.medium,
        );
        return PdfExportResult.failure('Received empty PDF from server.');
      }

      await downloadOrSharePdf(pdfBytes, filename, share: share);
      return PdfExportResult.success(filename);
    } on TimeoutException {
      await errorLogger.log(
        category: ErrorCategory.pdfExport,
        operation: 'pdf_export_timeout',
        userMessage: 'PDF generation timed out.',
        severity: ErrorSeverity.medium,
      );
      return PdfExportResult.failure(
        'PDF generation timed out. Please try again.',
      );
    } catch (e) {
      debugPrint('PdfExportService error: $e');
      await errorLogger.log(
        category: ErrorCategory.pdfExport,
        operation: 'pdf_export_unexpected',
        userMessage: 'Could not generate PDF. Please try again.',
        error: e,
        severity: ErrorSeverity.medium,
      );
      return PdfExportResult.failure(
        'Could not generate PDF. Please try again.',
      );
    }
  }

  String _dateStamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
