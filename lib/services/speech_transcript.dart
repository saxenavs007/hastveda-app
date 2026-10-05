/// One microphone session. Interim text replaces itself, and a finished
/// utterance is kept once so a recognition restart cannot type it again.
class SpeechTranscript {
  String committed = '';
  String interim = '';

  void reset() {
    committed = '';
    interim = '';
  }

  void clearInterim() {
    interim = '';
  }

  /// The full utterance for this session, or null when [words] is a repeat.
  String? apply(String words, {required bool isFinal}) {
    final incoming = words.trim();
    if (incoming.isEmpty) return null;

    if (!isFinal && _same(incoming, interim)) return null;

    final merged = _merge(committed, incoming);
    if (isFinal) {
      interim = '';
      if (_same(merged, committed)) return null;
      committed = merged;
      return committed;
    }

    interim = incoming;
    if (_same(merged, committed)) return null;
    return merged;
  }

  static String _merge(String committed, String incoming) {
    if (committed.isEmpty) return incoming;
    final kept = _norm(committed);
    final words = _norm(incoming);
    if (words.isEmpty ||
        words == kept ||
        kept.startsWith(words) ||
        kept.endsWith(words)) {
      return committed;
    }
    if (words.startsWith(kept)) {
      final rest = words.substring(kept.length).trim();
      if (rest.isEmpty || _isReplay(kept, rest)) return committed;
      return incoming;
    }
    if (_isReplay(kept, words)) return committed;
    return '$committed $incoming'.trim();
  }

  static bool _isReplay(String committed, String incoming) {
    if (incoming.isEmpty || committed.startsWith(incoming)) return true;
    final incomingWords = incoming.split(' ');
    final committedWords = committed.split(' ');
    if (incomingWords.length > committedWords.length) return false;
    return committedWords.take(incomingWords.length).join(' ') == incoming;
  }

  static bool _same(String left, String right) => _norm(left) == _norm(right);

  static String _norm(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[.!?।,;:]+$'), '')
      .trim();
}
