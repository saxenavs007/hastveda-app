import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'speech_text.dart';

/// Speaks from the browser's speech engine. [speak] must be called directly
/// from a tap so Safari and Chrome on iOS still allow audio.
class WebSpeech {
  static int _generation = 0;
  static int _session = 0;
  static Timer? _keepAlive;
  static Timer? _voiceWait;
  static JSFunction? _voicesListener;
  static final List<web.SpeechSynthesisUtterance> _utterances = [];

  static void stop() {
    _generation++;
    _session++;
    _keepAlive?.cancel();
    _keepAlive = null;
    _voiceWait?.cancel();
    _voiceWait = null;
    _utterances.clear();
    _detachVoicesListener();
    web.window.speechSynthesis.cancel();
  }

  static bool speak({
    required String text,
    required bool hindi,
    required void Function() onDone,
    required void Function(String message) onError,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      onError('Nothing to read aloud.');
      return false;
    }

    try {
      final synth = web.window.speechSynthesis;
      final generation = ++_generation;
      _keepAlive?.cancel();
      if (synth.paused) synth.resume();

      final chunks = SpeechText.chunks(trimmed);
      if (chunks.isEmpty) {
        onError('Nothing to read aloud.');
        return false;
      }

      var settled = false;

      void settleDone() {
        if (settled || generation != _generation) return;
        settled = true;
        _detachVoicesListener();
        _keepAlive?.cancel();
        onDone();
      }

      void settleError(String message) {
        if (settled || generation != _generation) return;
        settled = true;
        _detachVoicesListener();
        _keepAlive?.cancel();
        synth.cancel();
        onError(message);
      }

      final lang = hindi ? 'hi-IN' : 'en-IN';
      final voice = _voiceFor(synth, hindi);
      _enqueue(
        synth,
        chunks,
        lang: lang,
        voice: voice,
        generation: generation,
        onDone: settleDone,
        onError: () => settleError('Speech could not play in this browser.'),
      );

      // Chrome leaves getVoices() empty until voiceschanged. The speak()
      // above keeps the tap's audio unlock; this restarts on the Indian
      // voice once the list arrives.
      if (voice == null) {
        _waitForIndianVoice(
          synth,
          hindi: hindi,
          generation: generation,
          chunks: chunks,
          lang: lang,
          onDone: settleDone,
          onError: () => settleError('Speech could not play in this browser.'),
        );
      }
      synth.resume();

      // Chrome stops a long queue unless resume() is called while it speaks.
      // pause() drops every utterance after the current one, so it is not used.
      _keepAlive = Timer.periodic(const Duration(seconds: 8), (_) {
        if (generation != _generation) {
          _keepAlive?.cancel();
          return;
        }
        if (synth.paused || synth.speaking || synth.pending) synth.resume();
      });
      return true;
    } catch (_) {
      onError('Speech could not play in this browser.');
      return false;
    }
  }

  static void _enqueue(
    web.SpeechSynthesis synth,
    List<String> chunks, {
    required String lang,
    required web.SpeechSynthesisVoice? voice,
    required int generation,
    required void Function() onDone,
    required void Function() onError,
  }) {
    final session = ++_session;
    _utterances.clear();
    var index = 0;

    void speakNext() {
      if (session != _session || generation != _generation) return;
      if (index >= chunks.length) {
        _utterances.clear();
        onDone();
        return;
      }
      final utterance = web.SpeechSynthesisUtterance(chunks[index])
        ..lang = lang
        ..rate = 0.92
        ..volume = 1;
      if (voice != null) utterance.voice = voice;
      // The browser drops later utterances if these objects are collected,
      // and if they are all queued before the first one ends.
      _utterances.add(utterance);
      utterance.onend = ((web.Event _) {
        if (session != _session || generation != _generation) return;
        index++;
        speakNext();
      }).toJS;
      utterance.onerror = ((web.SpeechSynthesisErrorEvent event) {
        if (session != _session || generation != _generation) return;
        final code = event.error.toString().toLowerCase();
        if (code.contains('canceled') || code.contains('interrupted')) return;
        onError();
      }).toJS;
      synth.speak(utterance);
      if (synth.paused) synth.resume();
    }

    speakNext();
  }

  static void _waitForIndianVoice(
    web.SpeechSynthesis synth, {
    required bool hindi,
    required int generation,
    required List<String> chunks,
    required String lang,
    required void Function() onDone,
    required void Function() onError,
  }) {
    var restarted = false;
    void tryRestart() {
      if (restarted || generation != _generation) return;
      final voice = _voiceFor(synth, hindi);
      if (voice == null) return;
      restarted = true;
      _voiceWait?.cancel();
      _voiceWait = null;
      _detachVoicesListener();
      // Drop the gesture-unlock utterance before its end callback can
      // finish the reading, then speak again with the Indian voice.
      _session++;
      synth.cancel();
      _enqueue(
        synth,
        chunks,
        lang: lang,
        voice: voice,
        generation: generation,
        onDone: onDone,
        onError: onError,
      );
    }

    _detachVoicesListener();
    _voicesListener = ((web.Event _) => tryRestart()).toJS;
    synth.addEventListener('voiceschanged', _voicesListener);
    _voiceWait?.cancel();
    _voiceWait = Timer(const Duration(milliseconds: 250), tryRestart);
  }

  static void _detachVoicesListener() {
    final listener = _voicesListener;
    if (listener == null) return;
    web.window.speechSynthesis.removeEventListener('voiceschanged', listener);
    _voicesListener = null;
  }

  /// Prefers en-IN or hi-IN. A voice named for India also qualifies.
  /// en-GB and en-US are never selected.
  static web.SpeechSynthesisVoice? _voiceFor(
    web.SpeechSynthesis synth,
    bool hindi,
  ) {
    try {
      web.SpeechSynthesisVoice? best;
      var bestScore = 0;
      for (final voice in synth.getVoices().toDart) {
        final score = _voiceScore(voice.name, voice.lang, hindi);
        if (score > bestScore) {
          bestScore = score;
          best = voice;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  static int _voiceScore(String name, String lang, bool hindi) {
    final locale = lang.toLowerCase().replaceAll('_', '-');
    final lowered = name.toLowerCase();
    if ((locale == 'en-gb' || locale == 'en-us' || locale == 'en-au') &&
        !lowered.contains('india')) {
      return 0;
    }
    final wanted = hindi ? 'hi' : 'en';
    var score = 0;
    if (locale == '$wanted-in') score += 100;
    if (locale.startsWith('$wanted-in')) score += 80;
    if (locale.endsWith('-in') || locale.contains('-in-')) score += 40;
    if (lowered.contains('india') || lowered.contains('indian')) score += 50;
    if (hindi &&
        (lowered.contains('hindi') ||
            lowered.contains('हिन्दी') ||
            locale.startsWith('hi'))) {
      score += 30;
    }
    if (!hindi && locale.startsWith('hi')) score -= 25;
    return score;
  }

}
