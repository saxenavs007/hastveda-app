/// Native and desktop builds do not use the browser speech API.
class WebSpeech {
  static void stop() {}

  static bool speak({
    required String text,
    required bool hindi,
    required void Function() onDone,
    required void Function(String message) onError,
  }) {
    onError('Speech is not available in this browser.');
    return false;
  }
}
