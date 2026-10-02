import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../ai_client.dart';
import '../../../services/error_logger.dart';

const String _chatCompletionEndpoint = String.fromEnvironment(
  'AWS_LAMBDA_CHAT_COMPLETION_URL',
);

Future<Map<String, dynamic>> getChatCompletion(
  String provider,
  String model,
  List<Map<String, dynamic>> messages, {
  Map<String, dynamic> parameters = const {},
}) async {
  final payload = {
    'provider': provider,
    'model': model,
    'messages': messages,
    'stream': false,
    'parameters': parameters,
  };
  try {
    return await callLambdaFunction(_chatCompletionEndpoint, payload);
  } on HastVedaAiException {
    rethrow; // Already logged and categorized in ai_client.dart
  } catch (e) {
    // Catch any other unexpected errors
    await errorLogger.logGeminiError(
      operation: 'chat_completion/$provider/$model',
      error: e,
    );
    rethrow;
  }
}

Future<void> getStreamingChatCompletion(
  String provider,
  String model,
  List<Map<String, dynamic>> messages, {
  required void Function(Map<String, dynamic> chunk) onChunk,
  required void Function() onComplete,
  required void Function(Exception error) onError,
  Map<String, dynamic> parameters = const {},
}) async {
  final payload = {
    'provider': provider,
    'model': model,
    'messages': messages,
    'stream': true,
    'parameters': parameters,
  };

  try {
    final dio = Dio();
    final response = await dio.post<ResponseBody>(
      _chatCompletionEndpoint,
      data: payload,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.stream,
      ),
    );

    String buffer = '';
    await for (final chunk in response.data!.stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          try {
            final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            if (data['type'] == 'chunk' && data['chunk'] != null) {
              onChunk(data['chunk'] as Map<String, dynamic>);
            } else if (data['type'] == 'done') {
              onComplete();
            } else if (data['type'] == 'error') {
              final errMsg = data['error'] as String? ?? 'Streaming error';
              if (kDebugMode) debugPrint('Lambda streaming error: $errMsg');
              await errorLogger.logGeminiError(
                operation: 'streaming_chat_completion/$provider/$model',
                error: errMsg,
              );
              onError(Exception(errMsg));
            }
          } catch (_) {}
        }
      }
    }
  } catch (error) {
    if (kDebugMode) debugPrint('Streaming error: $error');
    final aiEx = error is HastVedaAiException
        ? error
        : HastVedaAiException(
            message: error.toString(),
            errorType: 'api_failure',
            userMessage: 'AI analysis failed. Please try again.',
          );
    await errorLogger.logGeminiError(
      operation: 'streaming_chat_completion/$provider/$model',
      error: error,
    );
    onError(aiEx);
  }
}
