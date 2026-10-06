import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hastveda/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    app.debugForceStartupFailure = false;
  });

  tearDown(() {
    app.debugForceStartupFailure = false;
    try {
      Supabase.instance.client.auth.stopAutoRefresh();
    } catch (_) {}
  });

  testWidgets('a timed-out startup step still opens onboarding', (tester) async {
    await _runBoot(tester, () async {
      _expectText(tester, 'Decode Your Cosmic Blueprint');
      expect(find.text("We're having trouble connecting."), findsNothing);
    });
  });

  testWidgets('a failed startup still opens onboarding', (tester) async {
    app.debugForceStartupFailure = true;
    await _runBoot(tester, () async {
      _expectText(tester, 'Decode Your Cosmic Blueprint');
      expect(find.text("We're having trouble connecting."), findsNothing);
    });
  });
}

void _expectText(WidgetTester tester, String text) {
  final texts = tester
      .widgetList<Text>(find.byType(Text, skipOffstage: false))
      .map((widget) => widget.data)
      .whereType<String>()
      .toList();
  expect(texts, contains(text), reason: 'Visible text: ${texts.join(' | ')}');
}

/// Pumps until [main] finishes, including the orientation timeout, then lets
/// the splash delay elapse before [check] reads the tree.
Future<void> _runBoot(
  WidgetTester tester,
  Future<void> Function() check,
) async {
  final errorWidget = ErrorWidget.builder;
  final onError = FlutterError.onError;
  final platformOnError = PlatformDispatcher.instance.onError;
  try {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    final boot = app.main();
    var pending = true;
    boot.whenComplete(() => pending = false);
    for (var i = 0; i < 40 && pending; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await boot;
    await tester.pump(const Duration(seconds: 4));
    await check();
    // Let bounded startup timers (connectivity, saved theme) finish.
    await tester.pump(const Duration(seconds: 5));
  } finally {
    try {
      Supabase.instance.client.auth.stopAutoRefresh();
    } catch (_) {}
    ErrorWidget.builder = errorWidget;
    FlutterError.onError = onError;
    PlatformDispatcher.instance.onError = platformOnError;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}
