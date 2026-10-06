import 'package:flutter/foundation.dart';

/// Browser narration started from the tap that opens a reading.
/// The detail screen listens so the speaker control stays in sync
/// after that gesture has ended.
class ReadingNarration extends ChangeNotifier {
  ReadingNarration._();
  static final ReadingNarration instance = ReadingNarration._();

  bool speaking = false;

  void setSpeaking(bool value) {
    if (speaking == value) return;
    speaking = value;
    notifyListeners();
  }
}
