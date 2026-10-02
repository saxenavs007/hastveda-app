import 'package:flutter/foundation.dart';

import './analytics_service.dart';

// HastVeda Error Logger
// Structured, production-safe error logging.
//
// SAFETY RULES (enforced here):
//   ✅ Logs: timestamp, category, operation, app version, platform, user ID
//   ❌ Never logs: API keys, passwords, tokens, palm images, report content, PII
//
// Errors are persisted to Supabase analytics_events (existing table) and
// forwarded to Mixpanel via the existing AnalyticsService.

// ── Error Categories ──────────────────────────────────────────────────────────
class ErrorCategory {
  static const String gemini = 'gemini_error';
  static const String supabase = 'supabase_error';
  static const String auth = 'auth_error';
  static const String network = 'network_error';
  static const String palmAnalysis = 'palm_analysis_error';
  static const String coupleReading = 'couple_reading_error';
  static const String detailedReport = 'detailed_report_error';
  static const String pdfExport = 'pdf_export_error';
  static const String readingComparison = 'reading_comparison_error';
  static const String readingHistory = 'reading_history_error';
  static const String appCrash = 'app_crash';
  static const String ui = 'ui_error';
  static const String unknown = 'unknown_error';
}

// ── Error Severity ────────────────────────────────────────────────────────────
class ErrorSeverity {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
  static const String critical = 'critical';
}

// ── Structured Error Entry ────────────────────────────────────────────────────
class AppError {
  final String category;
  final String operation;
  final String userMessage;
  final String? technicalDetail; // safe detail, no secrets
  final String severity;
  final DateTime timestamp;

  const AppError({
    required this.category,
    required this.operation,
    required this.userMessage,
    this.technicalDetail,
    this.severity = ErrorSeverity.medium,
    required this.timestamp,
  });

  Map<String, dynamic> toLogMap() => {
    'category': category,
    'operation': operation,
    'severity': severity,
    'timestamp': timestamp.toIso8601String(),
    // Only include a safe, truncated technical detail (no secrets)
    if (technicalDetail != null) 'detail': _sanitize(technicalDetail!),
  };

  /// Strips any potential secret patterns from technical details.
  static String _sanitize(String input) {
    // Remove anything that looks like a key/token/secret
    var sanitized = input
        .replaceAll(RegExp(r'[A-Za-z0-9_\-]{32,}'), '[REDACTED]')
        .replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [REDACTED]')
        .replaceAll(
          RegExp(r'key[=:]\s*\S+', caseSensitive: false),
          'key=[REDACTED]',
        )
        .replaceAll(
          RegExp(r'token[=:]\s*\S+', caseSensitive: false),
          'token=[REDACTED]',
        )
        .replaceAll(
          RegExp(r'password[=:]\s*\S+', caseSensitive: false),
          'password=[REDACTED]',
        )
        .replaceAll(
          RegExp(r'secret[=:]\s*\S+', caseSensitive: false),
          'secret=[REDACTED]',
        );
    // Truncate to 500 chars max
    if (sanitized.length > 500) {
      sanitized = '${sanitized.substring(0, 497)}...';
    }
    return sanitized;
  }
}

// ── Error Logger Service ──────────────────────────────────────────────────────
class ErrorLogger {
  ErrorLogger._();
  static final ErrorLogger instance = ErrorLogger._();

  static const String _appVersion = '1.0.0';

  /// Log a structured error. Safe for production.
  Future<void> log({
    required String category,
    required String operation,
    required String userMessage,
    Object? error,
    StackTrace? stackTrace,
    String severity = ErrorSeverity.medium,
    Map<String, dynamic>? extra,
  }) async {
    final timestamp = DateTime.now();

    // Build a safe technical detail (no secrets, no full stack traces in prod)
    String? technicalDetail;
    if (error != null) {
      final raw = error.toString();
      technicalDetail = AppError._sanitize(raw);
    }

    final entry = AppError(
      category: category,
      operation: operation,
      userMessage: userMessage,
      technicalDetail: technicalDetail,
      severity: severity,
      timestamp: timestamp,
    );

    // Debug logging (only in debug mode)
    if (kDebugMode) {
      debugPrint(
        '[ErrorLogger] [$severity] $category/$operation: $userMessage',
      );
      if (technicalDetail != null) debugPrint('  detail: $technicalDetail');
      if (stackTrace != null) {
        debugPrint(
          '  stack: ${stackTrace.toString().split('\n').take(5).join('\n')}',
        );
      }
    }

    // Track via analytics (Mixpanel + Supabase analytics_events)
    final logMap = entry.toLogMap();
    if (extra != null) {
      // Only include safe extra fields
      for (final k in extra.keys) {
        if (!_isSensitiveKey(k)) {
          logMap[k] = extra[k];
        }
      }
    }

    analytics.track(
      'app_error',
      properties: {
        ...logMap,
        'app_version': _appVersion,
        'platform': currentPlatform,
      },
    );
  }

  /// Log a Flutter framework error (from ErrorWidget.builder or FlutterError.onError).
  Future<void> logFlutterError(FlutterErrorDetails details) async {
    final message = details.exceptionAsString();
    // Never log full stack traces to analytics — only a safe summary
    final safeSummary = AppError._sanitize(message);

    await log(
      category: ErrorCategory.appCrash,
      operation: 'flutter_framework_error',
      userMessage: 'An unexpected error occurred.',
      error: safeSummary,
      severity: ErrorSeverity.critical,
    );
  }

  /// Log a Gemini/AI error with categorized type.
  Future<void> logGeminiError({
    required String operation,
    required Object error,
    String?
    errorType, // 'timeout', 'quota', 'malformed', 'network', 'api_failure'
  }) async {
    final type = errorType ?? _classifyGeminiError(error.toString());
    await log(
      category: ErrorCategory.gemini,
      operation: operation,
      userMessage: _geminiUserMessage(type),
      error: error,
      severity: type == 'quota' ? ErrorSeverity.high : ErrorSeverity.medium,
      extra: {'error_type': type},
    );
  }

  /// Log a Supabase error.
  Future<void> logSupabaseError({
    required String operation,
    required Object error,
  }) async {
    await log(
      category: ErrorCategory.supabase,
      operation: operation,
      userMessage: 'A database error occurred. Please try again.',
      error: error,
      severity: ErrorSeverity.medium,
    );
  }

  /// Log a network/connectivity error.
  Future<void> logNetworkError({
    required String operation,
    Object? error,
  }) async {
    await log(
      category: ErrorCategory.network,
      operation: operation,
      userMessage:
          'No internet connection. Please check your network and try again.',
      error: error,
      severity: ErrorSeverity.low,
    );
  }

  /// Log an auth error.
  Future<void> logAuthError({
    required String operation,
    required Object error,
  }) async {
    await log(
      category: ErrorCategory.auth,
      operation: operation,
      userMessage: 'Authentication failed. Please sign in again.',
      error: error,
      severity: ErrorSeverity.high,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool _isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('key') ||
        lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('password') ||
        lower.contains('auth') ||
        lower.contains('image') ||
        lower.contains('photo') ||
        lower.contains('palm') ||
        lower.contains('report') ||
        lower.contains('content');
  }

  String _classifyGeminiError(String errorStr) {
    final lower = errorStr.toLowerCase();
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'timeout';
    }
    if (lower.contains('quota') ||
        lower.contains('rate') ||
        lower.contains('429')) {
      return 'quota';
    }
    if (lower.contains('malformed') ||
        lower.contains('parse') ||
        lower.contains('json')) {
      return 'malformed';
    }
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket')) {
      return 'network';
    }
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized')) {
      return 'auth_failure';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503')) {
      return 'server_error';
    }
    return 'api_failure';
  }

  String _geminiUserMessage(String type) {
    switch (type) {
      case 'timeout':
        return 'The analysis took too long. Please check your connection and try again.';
      case 'quota':
        return 'The AI service is temporarily busy. Please try again in a few minutes.';
      case 'malformed':
        return 'Received an unexpected response. Please try again.';
      case 'network':
        return 'No internet connection. Please connect and try again.';
      case 'auth_failure':
        return 'AI service authentication failed. Please try again later.';
      case 'server_error':
        return 'The AI service is temporarily unavailable. Please try again later.';
      default:
        return 'AI analysis failed. Please try again.';
    }
  }
}

// ── Global singleton accessor ─────────────────────────────────────────────────
final errorLogger = ErrorLogger.instance;
