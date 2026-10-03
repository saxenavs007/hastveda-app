import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Picks an Indian English or Hindi voice so English is not read
/// with the device's default British or American accent.
class IndianTts {
  static final Map<String, Map<String, String>?> _voiceCache = {};

  static Future<void> apply(FlutterTts tts, {required bool hindi}) async {
    final locale = hindi ? 'hi-IN' : 'en-IN';
    await tts.setLanguage(locale);
    await tts.setSpeechRate(0.48);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
    final voice = await _voiceFor(tts, locale);
    if (voice != null) {
      try {
        await tts.setVoice(voice);
      } catch (e) {
        debugPrint('Indian TTS setVoice failed for $locale: $e');
      }
    }
  }

  static Future<Map<String, String>?> _voiceFor(
    FlutterTts tts,
    String locale,
  ) async {
    if (_voiceCache.containsKey(locale)) return _voiceCache[locale];
    Map<String, String>? chosen;
    try {
      final voices = await tts.getVoices;
      chosen = _pick(voices, locale);
    } catch (e) {
      debugPrint('Indian TTS getVoices failed: $e');
    }
    if (chosen != null) _voiceCache[locale] = chosen;
    return chosen;
  }

  static Map<String, String>? _pick(dynamic voices, String locale) {
    if (voices is! List) return null;
    final wanted = _norm(locale);
    Map<String, String>? exact;
    for (final raw in voices) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? '').toString().trim();
      final voiceLocale = (raw['locale'] ?? raw['lang'] ?? '').toString().trim();
      if (name.isEmpty || voiceLocale.isEmpty) continue;
      if (_norm(voiceLocale) != wanted) continue;
      final entry = {'name': name, 'locale': voiceLocale};
      exact ??= entry;
      final lowered = name.toLowerCase();
      if (lowered.contains(wanted.replaceAll('-', '')) ||
          lowered.contains(wanted)) {
        return entry;
      }
    }
    return exact;
  }

  static String _norm(String locale) =>
      locale.replaceAll('_', '-').toLowerCase();
}
