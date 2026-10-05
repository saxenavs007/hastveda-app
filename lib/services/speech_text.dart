/// Splits a reading into short utterances the Web Speech API can finish.
class SpeechText {
  static const int maxChunkLength = 160;

  static List<String> chunks(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const [];

    final pieces = normalized.split(RegExp(r'(?<=[.!?।])\s+|\n+'));
    final chunks = <String>[];
    for (final piece in pieces) {
      final part = piece.trim();
      if (part.isEmpty) continue;
      chunks.addAll(_wrap(part));
    }
    return chunks;
  }

  static List<String> _wrap(String part) {
    if (part.length <= maxChunkLength) return [part];

    final pieces = part.split(RegExp(r'(?<=[,;:])\s+'));
    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) chunks.add(value);
      buffer.clear();
    }

    for (final piece in pieces) {
      final clause = piece.trim();
      if (clause.isEmpty) continue;
      if (clause.length > maxChunkLength) {
        flush();
        chunks.addAll(_hardWrap(clause));
        continue;
      }
      if (buffer.length + clause.length + 1 > maxChunkLength) flush();
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(clause);
    }
    flush();
    return chunks;
  }

  static List<String> _hardWrap(String part) {
    final chunks = <String>[];
    var start = 0;
    while (start < part.length) {
      var end = start + maxChunkLength;
      if (end >= part.length) {
        chunks.add(part.substring(start).trim());
        break;
      }
      final space = part.lastIndexOf(' ', end);
      if (space > start + 40) end = space;
      final slice = part.substring(start, end).trim();
      if (slice.isNotEmpty) chunks.add(slice);
      start = end;
      while (start < part.length && part[start] == ' ') {
        start++;
      }
    }
    return chunks;
  }
}
