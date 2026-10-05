/// Browser speech-recognition flags for one spoken sentence.
class MicRecognition {
  /// Stop after the utterance. A continuous session restarts and types the
  /// first sentence again.
  static const bool continuous = false;

  /// Update the field while the person is still speaking.
  static const bool interimResults = true;
}
