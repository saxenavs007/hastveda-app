import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/error_logger.dart';

final Dio _dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 30),
  ),
);

Future<Map<String, dynamic>> callLambdaFunction(
  String endpoint,
  Map<String, dynamic> payload,
) async {
  try {
    final response = await _dio.post<Map<String, dynamic>>(
      endpoint,
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return response.data ?? {};
  } on DioException catch (error) {
    // Categorize the error type for structured logging
    final errorType = _classifyDioError(error);

    if (error.response?.data != null && error.response?.data is Map) {
      final data = error.response?.data as Map<String, dynamic>;
      if (data['error'] != null) {
        final errMsg = data['error'] as String;
        if (kDebugMode) {
          debugPrint('Lambda Function Error: $errMsg');
        }
        // Log to error logger with category
        errorLogger.logGeminiError(
          operation: 'lambda_call',
          error: errMsg,
          errorType: errorType,
        );
        throw HastVedaAiException(
          message: errMsg,
          errorType: errorType,
          userMessage: _userMessageForType(errorType),
        );
      }
    }

    // Network/timeout errors
    errorLogger.logGeminiError(
      operation: 'lambda_call',
      error: error,
      errorType: errorType,
    );

    throw HastVedaAiException(
      message: error.message ?? 'Network error',
      errorType: errorType,
      userMessage: _userMessageForType(errorType),
    );
  }
}

// ── HastVeda AI Exception ─────────────────────────────────────────────────────
/// Structured exception for AI/Gemini failures.
/// Never exposes API keys or internal details.
class HastVedaAiException implements Exception {
  final String message;
  final String errorType;
  final String userMessage;

  const HastVedaAiException({
    required this.message,
    required this.errorType,
    required this.userMessage,
  });

  @override
  String toString() => 'HastVedaAiException($errorType): $userMessage';
}

// ── Error classification helpers ──────────────────────────────────────────────
String _classifyDioError(DioException error) {
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout) {
    return 'timeout';
  }
  if (error.type == DioExceptionType.connectionError) {
    return 'network';
  }
  final statusCode = error.response?.statusCode;
  if (statusCode == 429) return 'quota';
  if (statusCode == 401 || statusCode == 403) return 'auth_failure';
  if (statusCode != null && statusCode >= 500) return 'server_error';
  return 'api_failure';
}

String _userMessageForType(String type) {
  switch (type) {
    case 'timeout':
      return 'The analysis took too long. Please check your connection and try again.';
    case 'quota':
      return 'The AI service is temporarily busy. Please try again in a few minutes.';
    case 'network':
      return 'No internet connection. Please connect and try again.';
    case 'auth_failure':
      return 'AI service is temporarily unavailable. Please try again later.';
    case 'server_error':
      return 'The AI service is temporarily unavailable. Please try again later.';
    default:
      return 'AI analysis failed. Please try again.';
  }
}
