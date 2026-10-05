/// Mobile and desktop builds use the speech_to_text plugin.
class WebMic {
  bool get isSupported => false;

  Future<bool> initialize({
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  }) async {
    return false;
  }

  Future<bool> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onResult,
  }) async {
    return false;
  }

  Future<void> stop() async {}
}
