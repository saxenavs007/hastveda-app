import 'package:flutter_test/flutter_test.dart';
import 'package:hastveda/services/mic_recognition.dart';
import 'package:hastveda/services/speech_text.dart';
import 'package:hastveda/services/speech_transcript.dart';

void main() {
  test('a reading is spoken as separate sentences', () {
    const reading = 'Your heart line is active today. '
        'A career shift is forming this week. '
        'Money opens after you ask.';

    final chunks = SpeechText.chunks(reading);

    expect(chunks, hasLength(3));
    expect(chunks.first, 'Your heart line is active today.');
    expect(chunks.last, 'Money opens after you ask.');
    expect(chunks.join(' '), reading);
  });

  test('a sentence longer than the speech buffer is split', () {
    final sentence = '${'word ' * 80}end.';
    final chunks = SpeechText.chunks(sentence);

    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.length <= SpeechText.maxChunkLength), isTrue);
  });

  test('the first spoken sentence is not typed again', () {
    final transcript = SpeechTranscript();

    expect(
      transcript.apply('Your heart line is active', isFinal: false),
      'Your heart line is active',
    );
    expect(
      transcript.apply('Your heart line is active today.', isFinal: true),
      'Your heart line is active today.',
    );
    expect(
      transcript.apply('Your heart line is active today.', isFinal: true),
      isNull,
    );
    expect(
      transcript.apply('Your heart line is active today.', isFinal: false),
      isNull,
    );
    expect(transcript.committed, 'Your heart line is active today.');
  });

  test('a later sentence is appended once', () {
    final transcript = SpeechTranscript();
    transcript.apply('Your heart line is active today.', isFinal: true);

    expect(
      transcript.apply('A career shift is forming.', isFinal: true),
      'Your heart line is active today. A career shift is forming.',
    );
    expect(
      transcript.apply('A career shift is forming.', isFinal: true),
      isNull,
    );
  });

  test('a finished sentence is cleared before the next listen', () {
    final transcript = SpeechTranscript();
    transcript.apply('Your heart line is active today.', isFinal: true);
    transcript.reset();

    expect(
      transcript.apply('Your heart line is active today.', isFinal: true),
      'Your heart line is active today.',
    );
  });

  test('the microphone listens once and still shows interim words', () {
    expect(MicRecognition.continuous, isFalse);
    expect(MicRecognition.interimResults, isTrue);
  });
}
