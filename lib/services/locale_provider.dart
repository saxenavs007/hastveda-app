import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './analytics_service.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _key = 'hastveda_locale';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  String get languageCode =>
      _locale.languageCode == 'hi' && _locale.scriptCode == 'Latn'
      ? 'hi-Latn'
      : _locale.languageCode;

  bool get isHindi =>
      _locale.languageCode == 'hi' && _locale.scriptCode != 'Latn';
  bool get isHinglish =>
      _locale.languageCode == 'hi' && _locale.scriptCode == 'Latn';
  bool get isEnglish => _locale.languageCode == 'en';

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    late final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('Locale load skipped: $e');
      return;
    }
    final code = prefs.getString(_key) ?? 'en';
    _locale = _localeFromCode(code);
    notifyListeners();
  }

  static Locale _localeFromCode(String code) {
    switch (code) {
      case 'hi':
        return const Locale('hi');
      case 'hi-Latn':
        return const Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn');
      default:
        return const Locale('en');
    }
  }

  Future<void> setLocale(String code) async {
    _locale = _localeFromCode(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // Persist using the canonical code string
    final persistCode = code == 'hi-Latn' ? 'hi-Latn' : _locale.languageCode;
    await prefs.setString(_key, persistCode);
    analytics.track(
      HastVedaEvents.languageChanged,
      properties: {'language': code},
    );
  }
}
