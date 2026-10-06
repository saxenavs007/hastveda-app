import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'hastveda_theme_mode';

  ThemeMode _themeMode = ThemeMode.dark;
  Brightness _systemBrightness = Brightness.dark;

  ThemeMode get themeMode => _themeMode;

  /// Returns true if the effective theme is dark (respects system default).
  bool get isDark {
    if (_themeMode == ThemeMode.system) {
      return _systemBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeProvider() {
    _loadTheme();
  }

  /// Called by MaterialApp to keep system brightness in sync.
  void updateSystemBrightness(Brightness brightness) {
    if (_systemBrightness != brightness) {
      _systemBrightness = brightness;
      if (_themeMode == ThemeMode.system) {
        notifyListeners();
      }
    }
  }

  Future<void> _loadTheme() async {
    late final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('Theme load skipped: $e');
      return;
    }
    final saved = prefs.getString(_key);
    if (saved == 'light') {
      _themeMode = ThemeMode.light;
    } else if (saved == 'system') {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    String val;
    switch (mode) {
      case ThemeMode.light:
        val = 'light';
        break;
      case ThemeMode.system:
        val = 'system';
        break;
      default:
        val = 'dark';
    }
    await prefs.setString(_key, val);
  }

  Future<void> toggleTheme() async {
    await setTheme(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
