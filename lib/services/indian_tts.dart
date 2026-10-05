import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Picks an Indian English or Hindi voice so English is not read
/// with the device's default British or American accent.
class IndianTts {
  static final Map<String, Map<String, String>?> _voiceCache = {};

  static Future<void> apply(FlutterTts tts, {required bool hindi}) async {
    final locale = hindi ? 'hi-IN' : 'en-IN';
    await tts.setSpeechRate(0.48);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
    final voice = await _voiceFor(tts, locale);
    final language = (voice?['locale']?.isNotEmpty ?? false)
        ? voice!['locale']!
        : locale;
    try {
      await tts.setLanguage(language);
    } catch (e) {
      debugPrint('Indian TTS setLanguage failed for $language: $e');
    }
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
    Map<String, String>? best;
    var bestScore = 0;
    for (final raw in voices) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? '').toString().trim();
      final voiceLocale = (raw['locale'] ?? raw['lang'] ?? '').toString().trim();
      if (name.isEmpty && voiceLocale.isEmpty) continue;
      final score = _score(name, voiceLocale, wanted);
      if (score > bestScore) {
        bestScore = score;
        best = {'name': name, 'locale': voiceLocale.isEmpty ? wanted : voiceLocale};
      }
    }
    return best;
  }

  /// Higher is a closer Indian voice. British and US English score zero.
  static int _score(String name, String locale, String wanted) {
    final lang = _norm(locale);
    final lowered = name.toLowerCase();
    final language = wanted.split('-').first;
    if (lang == 'en-gb' || lang == 'en-us' || lang == 'en-au') {
      if (!lowered.contains('india')) return 0;
    }
    var score = 0;
    if (lang == wanted) score += 100;
    if (lang.startsWith('$language-in')) score += 80;
    if (lang.endsWith('-in') || lang.contains('-in-')) score += 40;
    if (lowered.contains('india') || lowered.contains('indian')) score += 50;
    if (language == 'hi' &&
        (lowered.contains('hindi') || lowered.contains('हिन्दी') || lang.startsWith('hi'))) {
      score += 30;
    }
    if (language == 'en' && lang.startsWith('hi')) score -= 25;
    return score;
  }

  static String _norm(String locale) =>
      locale.replaceAll('_', '-').toLowerCase();
}
