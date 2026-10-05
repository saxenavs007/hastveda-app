import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'mic_recognition.dart';

@JS('webkitSpeechRecognition')
extension type _WebkitSpeechRecognition._(web.SpeechRecognition _)
    implements web.SpeechRecognition {
  external factory _WebkitSpeechRecognition();
}

/// One-shot browser recognition. Each tap creates a fresh recognizer so the
/// previous result list cannot be typed again.
class WebMic {
  web.SpeechRecognition? _recognition;
  int _session = 0;
  void Function(String message)? _onError;
  void Function(String status)? _onStatus;
  void Function(String words, bool isFinal)? _onResult;

  bool get isSupported =>
      web.window.hasProperty('SpeechRecognition'.toJS).toDart ||
      web.window.hasProperty('webkitSpeechRecognition'.toJS).toDart;

  Future<bool> initialize({
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  }) async {
    _onError = onError;
    _onStatus = onStatus;
    return isSupported;
  }

  Future<bool> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onResult,
  }) async {
    final session = ++_session;
    _onResult = onResult;
    final previous = _recognition;
    final recognition = _create();
    if (recognition == null) return false;
    _recognition = recognition;
    previous?.abort();

    recognition.continuous = MicRecognition.continuous;
    recognition.interimResults = MicRecognition.interimResults;
    recognition.maxAlternatives = 1;
    recognition.lang = localeId.replaceAll('_', '-');
    recognition.onresult = ((web.SpeechRecognitionEvent event) {
      if (session != _session) return;
      _emitCurrent(event);
    }).toJS;
    recognition.onerror = ((web.SpeechRecognitionErrorEvent event) {
      if (session != _session) return;
      final code = event.error.toString().toLowerCase();
      if (code.contains('aborted') || code.contains('no-speech')) return;
      _onError?.call(code);
    }).toJS;
    recognition.onend = ((web.Event _) {
      if (session != _session) return;
      _onStatus?.call('done');
    }).toJS;

    try {
      recognition.start();
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    _recognition?.stop();
  }

  void _emitCurrent(web.SpeechRecognitionEvent event) {
    final results = event.results;
    final index = event.resultIndex;
    if (index < 0 || index >= results.length) return;
    final result = results.item(index);
    if (result.length == 0) return;
    final words = result.item(0).transcript;
    _onResult?.call(words, result.isFinal);
  }

  web.SpeechRecognition? _create() {
    try {
      if (web.window.hasProperty('webkitSpeechRecognition'.toJS).toDart) {
        return _WebkitSpeechRecognition();
      }
      if (web.window.hasProperty('SpeechRecognition'.toJS).toDart) {
        return web.SpeechRecognition();
      }
    } catch (_) {}
    return null;
  }
}
