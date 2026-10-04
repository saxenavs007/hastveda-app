// Ask HastVeda Screen
// Premium: 2 questions included.
// Everyone else: one question for ₹59 (₹50 + 18% GST) via Cashfree.
//
// FIX 5: question_usage row is created BEFORE Cashfree checkout opens,
// with payment_order_id pre-linked. This ensures webhook recovery works
// even if the app closes during/after payment.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/indian_tts.dart';
import '../../services/cashfree_payment_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cashfree_platform_sheet.dart';
import '../../widgets/premium_lock_widget.dart';
import '../review_screen/review_screen.dart';

// Conditional import for Cashfree SDK
import '../premium_paywall_screen/cashfree_checkout_stub.dart'
    if (dart.library.io) '../premium_paywall_screen/cashfree_checkout_mobile.dart';

class AskHastVedaScreen extends StatefulWidget {
  final String locale;
  final String? initialQuestion;
  final bool startPayment;
  const AskHastVedaScreen({
    super.key,
    this.locale = 'en',
    this.initialQuestion,
    this.startPayment = false,
  });

  @override
  State<AskHastVedaScreen> createState() => _AskHastVedaScreenState();
}

class _AskHastVedaScreenState extends State<AskHastVedaScreen> {
  bool _isCheckingAccess = true;
  bool _hasAccess = false;
  bool _isPremiumUser = false;
  bool _appliedLivePremium = false;
  bool _isLoading = false;
  bool _isSubmitting = false;

  // Question usage state
  int _freeQuestionsUsed = 0;
  int _paidQuestionBalance = 0;
  int _totalQuestionsUsed = 0;
  List<Map<String, dynamic>> _questionHistory = [];

  // IDs of questions currently being polled for their AI answer.
  // Used to render a live "Generating answer…" indicator on the pending card
  // instead of leaving a stale "Pending" chip until the user leaves and returns.
  final Set<String> _pollingQuestionIds = <String>{};

  final TextEditingController _questionController = TextEditingController();
  static const int _freeQuotaPerPremium = 2;
  static const double _additionalQuestionPrice = 50.0;

  // ── Speech-to-Text ────────────────────────────────────────
  final SpeechToText _speechToText = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  static const int _maxQuestionChars = 500;
  static const Duration _speechDebounce = Duration(milliseconds: 300);
  Timer? _speechDebounceTimer;
  String? _pendingTranscript;
  String _textBeforeSpeech = '';
  String _lastRecognizedWords = '';
  bool _stoppingSpeech = false;

  // ── Text-to-Speech ────────────────────────────────────────
  final FlutterTts _flutterTts = FlutterTts();
  String? _speakingAnswerId;
  bool _isSpeaking = false;

  bool get _isHindi => widget.locale == 'hi';
  bool get _hasFreeQuestionsLeft => _freeQuestionsUsed < _freeQuotaPerPremium;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialQuestion?.trim();
    if (seed != null && seed.isNotEmpty) {
      _questionController.text = seed;
    }
    analytics.track(
      HastVedaEvents.readingViewed,
      properties: {'screen': 'ask_hastveda'},
    );
    _checkAccessAndLoad();
    _initSpeech();
    _initTts();
    if (widget.startPayment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _purchaseAndSubmitQuestion();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.watch<EntitlementNotifier>().isPremium;
    if (premium && !_isPremiumUser && !_isCheckingAccess) {
      _isPremiumUser = true;
    }
    if (!premium || _hasAccess) return;
    _hasAccess = true;
    _isCheckingAccess = false;
    if (_appliedLivePremium) return;
    _appliedLivePremium = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadQuestionHistory();
      _handleRecoveryRecords();
    });
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speechToText.initialize(
        onError: (error) {
          debugPrint('STT error: ${error.errorMsg}');
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (status) {
          debugPrint('STT status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('initSpeech error: $e');
      _speechAvailable = false;
    }
  }

  Future<void> _initTts() async {
    try {
      await IndianTts.apply(_flutterTts, hindi: _isHindi);

      _flutterTts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _speakingAnswerId = null;
          });
        }
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('TTS error: $msg');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _speakingAnswerId = null;
          });
        }
      });
    } catch (e) {
      debugPrint('initTts error: $e');
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      _showSnack(
        _isHindi
            ? 'माइक्रोफ़ोन उपलब्ध नहीं है'
            : 'Microphone not available on this device',
      );
      return;
    }

    if (_isListening) {
      await _stopListening();
      return;
    }

    if (_questionController.text.characters.length >= _maxQuestionChars) {
      _showSnack(
        _isHindi
            ? 'प्रश्न 500 अक्षरों तक सीमित है'
            : 'Questions are limited to 500 characters',
      );
      return;
    }

    try {
      _speechDebounceTimer?.cancel();
      _pendingTranscript = null;
      _textBeforeSpeech = _questionController.text;
      _lastRecognizedWords = '';
      setState(() => _isListening = true);
      await _speechToText.listen(
        onResult: _onSpeechResult,
        localeId: _isHindi ? 'hi_IN' : 'en_IN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      );
    } catch (e) {
      debugPrint('startListening error: $e');
      if (mounted) {
        setState(() => _isListening = false);
        _showSnack(
          _isHindi
              ? 'माइक्रोफ़ोन शुरू नहीं हो सका'
              : 'Could not start microphone. Please check permissions.',
        );
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty || !mounted) return;
    if (words == _lastRecognizedWords || words == _pendingTranscript) return;

    _pendingTranscript = words;
    if (result.finalResult) {
      _speechDebounceTimer?.cancel();
      _applyPendingTranscript();
      return;
    }

    _speechDebounceTimer?.cancel();
    _speechDebounceTimer = Timer(_speechDebounce, _applyPendingTranscript);
  }

  void _applyPendingTranscript() {
    final words = _pendingTranscript?.trim();
    _pendingTranscript = null;
    if (words == null || words.isEmpty || !mounted) return;
    if (words == _lastRecognizedWords) return;

    final utterance = _composeUtterance(words);
    if (utterance.isEmpty || utterance == _lastRecognizedWords) return;

    final next = _textWithinLimit(_textBeforeSpeech, utterance);
    if (next == null) {
      _lastRecognizedWords = utterance;
      if (!_stoppingSpeech) unawaited(_stopListening());
      return;
    }
    if (next == _questionController.text) {
      _lastRecognizedWords = utterance;
      return;
    }

    _lastRecognizedWords = utterance;
    setState(() {
      _questionController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });

    if (next.characters.length >= _maxQuestionChars && !_stoppingSpeech) {
      unawaited(_stopListening());
    }
  }

  /// Keeps a growing recognition as one utterance, and appends a segment
  /// only when it is not a repeat of the previous interim result.
  String _composeUtterance(String words) {
    final previous = _lastRecognizedWords;
    if (previous.isEmpty) return words;
    if (words == previous || previous.startsWith(words)) return previous;
    if (words.startsWith(previous)) return words;
    return '$previous $words'.trim();
  }

  /// Returns the field text after appending [utterance], or null when there
  /// is no room left under the 500-character cap.
  String? _textWithinLimit(String existing, String utterance) {
    final existingChars = existing.characters;
    if (existingChars.length >= _maxQuestionChars) return null;

    final needsSpace =
        existing.isNotEmpty &&
        !existing.endsWith(' ') &&
        !existing.endsWith('\n');
    final prefix = needsSpace ? '$existing ' : existing;
    final room = _maxQuestionChars - prefix.characters.length;
    if (room <= 0) return null;

    final utteranceChars = utterance.characters;
    final clipped = utteranceChars.length <= room
        ? utterance
        : utteranceChars.take(room).string;
    if (clipped.isEmpty) return null;
    return '$prefix$clipped';
  }

  Future<void> _stopListening() async {
    if (_stoppingSpeech) return;
    _stoppingSpeech = true;
    _speechDebounceTimer?.cancel();
    _applyPendingTranscript();
    try {
      await _speechToText.stop();
    } catch (e) {
      debugPrint('stopListening error: $e');
    }
    _stoppingSpeech = false;
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _speakAnswer(String answerId, String answerText) async {
    try {
      if (_isSpeaking && _speakingAnswerId == answerId) {
        // Stop speaking
        await _flutterTts.stop();
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _speakingAnswerId = null;
          });
        }
        return;
      }

      // Stop any current speech
      if (_isSpeaking) {
        await _flutterTts.stop();
      }

      if (mounted) {
        setState(() {
          _isSpeaking = true;
          _speakingAnswerId = answerId;
        });
      }

      await IndianTts.apply(_flutterTts, hindi: _isHindi);
      final result = await _flutterTts.speak(answerText);
      if (result != 1) {
        // TTS failed
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _speakingAnswerId = null;
          });
        }
      }
    } catch (e) {
      debugPrint('speakAnswer error: $e');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _speakingAnswerId = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _speechDebounceTimer?.cancel();
    _questionController.dispose();
    _speechToText.stop();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _checkAccessAndLoad() async {
    setState(() => _isCheckingAccess = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (!mounted) return;
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _isPremiumUser = premium;
        _hasAccess = user != null;
        _isCheckingAccess = false;
      });
      if (user != null) {
        await _loadQuestionHistory();
        await _handleRecoveryRecords();
      }
    } catch (_) {
      if (!mounted) return;
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _isPremiumUser = premium;
        _isCheckingAccess = false;
        _hasAccess = Supabase.instance.client.auth.currentUser != null;
      });
    }
  }

  /// Handles webhook recovery records: questions where payment was received
  /// but the app closed before the question text was saved.
  /// These have status = 'payment_received_pending_question'.
  Future<void> _handleRecoveryRecords() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final recoveryRecords = await SupabaseService.instance.client
          .from('question_usage')
          .select()
          .eq('user_id', userId)
          .eq('status', 'payment_received_pending_question')
          .limit(5);

      final records = List<Map<String, dynamic>>.from(recoveryRecords as List);
      if (records.isEmpty) return;

      // Show recovery dialog for each record
      for (final record in records) {
        if (!mounted) return;
        await _showRecoveryDialog(record);
      }
    } catch (e) {
      debugPrint('handleRecoveryRecords error: $e');
    }
  }

  Future<void> _showRecoveryDialog(Map<String, dynamic> record) async {
    final orderId = record['payment_order_id'] as String?;
    if (orderId == null || !mounted) return;

    final questionController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          _isHindi ? '₹50 भुगतान प्राप्त हुआ' : '₹50 Payment Received',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isHindi
                  ? 'आपका ₹50 भुगतान सफल रहा लेकिन ऐप बंद हो गया। कृपया अपना प्रश्न दोबारा दर्ज करें।'
                  : 'Your ₹50 payment was successful but the app closed. Please re-enter your question.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: questionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: _isHindi
                    ? 'अपना प्रश्न लिखें'
                    : 'Enter your question',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isHindi ? 'बाद में' : 'Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isHindi ? 'सबमिट करें' : 'Submit'),
          ),
        ],
      ),
    );

    if (confirmed == true && questionController.text.trim().isNotEmpty) {
      try {
        // Update the recovery record with the question text
        await SupabaseService.instance.client
            .from('question_usage')
            .update({
              'question_text': questionController.text.trim(),
              'status': 'pending',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', record['id'] as String);

        // Trigger answering via Edge Function
        await _triggerAnswerFunction(record['id'] as String);
        await _loadQuestionHistory();
        // Live-update the "Pending" chip to "Answered" for the recovered row.
        unawaited(_pollUntilAnswered(record['id'] as String));
      } catch (e) {
        debugPrint('Recovery dialog submit error: $e');
      }
    }
    questionController.dispose();
  }

  Future<void> _loadQuestionHistory() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final monthStart = _istMonthStartIso();
      final results = await Future.wait([
        SupabaseService.instance.client
            .from('question_usage')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(20),
        SupabaseService.instance.client
            .from('question_usage')
            .select('id')
            .eq('user_id', userId)
            .eq('is_free', true)
            .gte('created_at', monthStart),
        SupabaseService.instance.client
            .from('user_profiles')
            .select('paid_question_balance')
            .eq('id', userId)
            .maybeSingle(),
      ]);

      final questions = List<Map<String, dynamic>>.from(results[0] as List);
      final freeUsed = (results[1] as List).length;
      final profile = results[2] as Map<String, dynamic>?;
      final paidBalance =
          (profile?['paid_question_balance'] as num?)?.toInt() ?? 0;

      if (mounted) {
        setState(() {
          _questionHistory = questions
              .where(
                (q) =>
                    (q['question_text'] as String? ?? '').isNotEmpty ||
                    q['status'] == 'payment_received_pending_question',
              )
              .toList();
          _freeQuestionsUsed = freeUsed;
          _paidQuestionBalance = paidBalance;
          _totalQuestionsUsed = questions.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('loadQuestionHistory error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _istMonthStartIso() {
    final shifted = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final monthStartUtc = DateTime.utc(shifted.year, shifted.month, 1);
    return monthStartUtc
        .subtract(const Duration(hours: 5, minutes: 30))
        .toIso8601String();
  }

  /// Calls the answer-hastveda-question Edge Function to process a question.
  Future<void> _triggerAnswerFunction(String questionUsageId) async {
    try {
      final response = await SupabaseService.instance.client.functions.invoke(
        'answer-hastveda-question',
        body: {'question_usage_id': questionUsageId},
      );
      debugPrint('answer-hastveda-question response: ${response.data}');
    } catch (e) {
      debugPrint('triggerAnswerFunction error: $e');
      // Non-fatal — question is saved, will be answered when function retries
    }
  }

  /// Polls a single question_usage row until the Edge Function writes the AI
  /// answer (status = 'answered') or a terminal failure state, or until the
  /// timeout elapses. Updates the matching row inside `_questionHistory` in
  /// place so the "Pending" chip flips to "Answered" without requiring the
  /// user to leave the screen and return.
  ///
  /// Fire-and-forget: callers should NOT await this — it runs in the
  /// background alongside the fire-and-forget `_triggerAnswerFunction` call.
  Future<void> _pollUntilAnswered(String questionUsageId) async {
    if (!mounted) return;

    const pollInterval = Duration(seconds: 1);
    const maxAttempts = 20; // ~20 s total; Lambda typically responds in 2-5 s
    const terminalStatuses = <String>{
      'answered',
      'failed',
      'failed_empty_question',
      'rejected_free_quota_exceeded',
      'rejected_no_premium',
    };

    setState(() => _pollingQuestionIds.add(questionUsageId));

    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        await Future.delayed(pollInterval);
        if (!mounted) return;

        try {
          final row = await SupabaseService.instance.client
              .from('question_usage')
              .select('id, status, answer_text, answered_at, updated_at')
              .eq('id', questionUsageId)
              .maybeSingle();

          if (row == null) continue;
          final rowStatus = row['status'] as String? ?? 'pending';

          if (mounted) {
            setState(() {
              final idx = _questionHistory.indexWhere(
                (q) => q['id'] == questionUsageId,
              );
              if (idx != -1) {
                final updated = Map<String, dynamic>.from(
                  _questionHistory[idx],
                );
                updated['status'] = rowStatus;
                if (row['answer_text'] != null) {
                  updated['answer_text'] = row['answer_text'];
                }
                if (row['answered_at'] != null) {
                  updated['answered_at'] = row['answered_at'];
                }
                _questionHistory[idx] = updated;
              }
            });
          }

          if (terminalStatuses.contains(rowStatus)) return;
        } catch (e) {
          // Transient network / RLS error — keep polling until timeout.
          debugPrint('pollUntilAnswered attempt $attempt error: $e');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _pollingQuestionIds.remove(questionUsageId));
      }
    }
  }

  Future<void> _submitFreeQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    if (ConnectivityService.instance.isOffline) {
      _showSnack(_isHindi ? 'इंटरनेट आवश्यक है' : 'Internet required');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _showSnack('Please sign in to ask a question');
        return;
      }

      // Insert question record (free)
      // Server-side trigger will reject if user already has 2 free questions
      final insertResult = await SupabaseService.instance.client
          .from('question_usage')
          .insert({
            'user_id': userId,
            'question_text': question,
            'is_free': true,
            'is_paid': false,
            'status': 'pending',
          })
          .select('id')
          .maybeSingle();

      if (insertResult == null) {
        _showSnack(
          _isHindi ? 'प्रश्न सबमिट नहीं हुआ' : 'Failed to submit question',
        );
        return;
      }

      final questionId = insertResult['id'] as String;
      _questionController.clear();

      // Trigger AI answering
      _triggerAnswerFunction(questionId);

      _showSnack(
        _isHindi
            ? 'प्रश्न सबमिट किया गया! उत्तर जल्द आएगा।'
            : 'Question submitted! Answer coming soon.',
        isSuccess: true,
      );
      await _loadQuestionHistory();
      // Live-update the "Pending" chip to "Answered" without needing a
      // screen re-entry. Fire-and-forget: runs alongside the Edge Function.
      unawaited(_pollUntilAnswered(questionId));

      // Trigger review prompt after successful question submission
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            showReviewDialogIfAppropriate(
              context: context,
              featureContext: ReviewFeatureContext.askHastveda,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('submitFreeQuestion error: $e');
      final errorMsg = e.toString();
      if (errorMsg.contains('Free question quota exceeded') ||
          errorMsg.contains('P0001')) {
        _showSnack(
          _isHindi
              ? 'मुफ़्त प्रश्न समाप्त। ₹50 में पूछें।'
              : 'Free questions exhausted. Ask for ₹50.',
        );
        // Refresh to show updated count
        await _loadQuestionHistory();
      } else if (errorMsg.contains('Premium subscription required') ||
          errorMsg.contains('P0002')) {
        _showSnack(
          _isHindi
              ? 'प्रीमियम सदस्यता आवश्यक है'
              : 'Premium subscription required',
        );
      } else {
        _showSnack(
          _isHindi ? 'प्रश्न सबमिट नहीं हुआ' : 'Failed to submit question',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _purchaseAndSubmitQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      _showSnack(
        _isHindi ? 'पहले प्रश्न लिखें' : 'Please enter your question first',
      );
      return;
    }

    if (ConnectivityService.instance.isOffline) {
      _showSnack(_isHindi ? 'इंटरनेट आवश्यक है' : 'Internet required');
      return;
    }

    if (!cashfreeCheckoutSupported) {
      await showCashfreePlatformSheet(context, isHindi: _isHindi);
      return;
    }

    setState(() => _isSubmitting = true);
    String? questionUsageId;
    String? orderId;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _showSnack('Please sign in');
        return;
      }

      // STEP 1: Create Cashfree order FIRST (get order ID)
      final orderResult = await CashfreePaymentService.instance.createOrder(
        productType: 'ask_question',
      );

      if (!orderResult.success || orderResult.orderId == null) {
        _showSnack(orderResult.error ?? 'Failed to create payment order');
        return;
      }

      orderId = orderResult.orderId!;

      // Guard: payment_session_id must be non-null and non-empty before
      // passing to the Cashfree SDK — a null/empty token causes the SDK
      // to throw "Token is not present" with no useful context.
      final sessionId = orderResult.paymentSessionId;
      if (sessionId == null || sessionId.trim().isEmpty) {
        _showSnack(
          _isHindi
              ? 'भुगतान शुरू नहीं हो सका। कृपया पुनः प्रयास करें।'
              : 'Unable to start payment. Please try again.',
        );
        return;
      }

      // STEP 2: Create question_usage row with payment_order_id BEFORE checkout
      // This is the key to FIX 5: the row exists before payment, so webhook
      // can find and update it even if the app closes during payment.
      final insertResult = await SupabaseService.instance.client
          .from('question_usage')
          .insert({
            'user_id': userId,
            'question_text': question,
            'is_free': false,
            'is_paid': false, // Will be set to true after payment confirmation
            'payment_order_id': orderId,
            'status': 'awaiting_payment',
          })
          .select('id')
          .maybeSingle();

      if (insertResult == null) {
        _showSnack(
          _isHindi ? 'प्रश्न सेव नहीं हुआ' : 'Failed to save question',
        );
        return;
      }

      questionUsageId = insertResult['id'] as String;

      // STEP 3: Open Cashfree checkout
      final checkoutResult = await openCashfreeCheckout(
        orderId: orderId,
        paymentSessionId: sessionId,
        environment: const String.fromEnvironment(
          'CASHFREE_ENV',
          defaultValue: 'production',
        ),
        onVerifyPayment: (oid) async {
          final verifyResult = await CashfreePaymentService.instance
              .verifyPayment(oid);
          return verifyResult.success;
        },
        onError: (msg) {
          if (mounted) _showSnack(msg);
        },
      );

      if (checkoutResult == true) {
        // STEP 4: Payment succeeded — mark question as paid
        await SupabaseService.instance.client
            .from('question_usage')
            .update({
              'is_paid': true,
              'status': 'pending',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', questionUsageId);

        _questionController.clear();
        _showSnack(
          _isHindi
              ? 'भुगतान सफल। 1 प्रश्न क्रेडिट अनलॉक हुआ और आपका प्रश्न भेज दिया गया।'
              : 'Payment successful. 1 question credit unlocked and your question was sent.',
          isSuccess: true,
        );

        // STEP 5: Trigger AI answering
        _triggerAnswerFunction(questionUsageId);

        await _loadQuestionHistory();
        // Live-update the "Pending" chip to "Answered" without needing a
        // screen re-entry.
        unawaited(_pollUntilAnswered(questionUsageId));
      } else {
        // Payment cancelled/failed — update question status
        await SupabaseService.instance.client
            .from('question_usage')
            .update({
              'status': 'payment_cancelled',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', questionUsageId);
        await _loadQuestionHistory();
      }
    } catch (e) {
      debugPrint('purchaseAndSubmitQuestion error: $e');
      // If we created the question row but payment failed, mark it cancelled
      if (questionUsageId != null) {
        try {
          await SupabaseService.instance.client
              .from('question_usage')
              .update({
                'status': 'payment_cancelled',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', questionUsageId);
        } catch (_) {}
      }
      _showSnack(
        _isHindi ? 'भुगतान विफल' : 'Payment failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess
            ? Colors.green.shade700
            : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        title: Text(
          _isHindi ? '🔮  HastVeda से पूछें' : '🔮  Ask HastVeda',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textPri,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri),
          onPressed: popOrHome,
        ),
      ),
      body: _isCheckingAccess
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : !_hasAccess
          ? _buildLockedState(context, isDark)
          : _buildContent(context, isDark),
    );
  }

  Widget _buildLockedState(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Text('🔮', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            _isHindi ? 'HastVeda से पूछें' : 'Ask HastVeda',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isHindi
                ? 'अपनी हथेली के बारे में व्यक्तिगत प्रश्न पूछें। प्रीमियम के साथ 2 प्रश्न मुफ़्त।'
                : 'Ask personalized questions about your palm reading. 2 questions included free with Premium.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.textSecondaryLight,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          PremiumLockWidget(
            feature: PremiumFeatures.askHastVeda,
            locale: widget.locale,
            child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                '${AppRoutes.premiumPaywall}?locale=${widget.locale}',
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                _isHindi ? 'प्रीमियम अनलॉक करें' : 'Unlock Premium',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final surfaceEl = isDark
        ? AppTheme.surfaceElevated
        : AppTheme.surfaceElevatedLight;
    final textPri = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textSec = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final border = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final primaryColor = isDark ? AppTheme.gold : AppTheme.confetti;

    final freeLeft = _freeQuotaPerPremium - _freeQuestionsUsed;
    final hasFreeLeft = _isPremiumUser && freeLeft > 0;

    return SingleChildScrollView(
      child: Column(
      children: [
        // Usage summary bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: surfaceEl,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(Icons.psychology_rounded, color: primaryColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasFreeLeft
                          ? (_isHindi
                                ? 'इस महीने $freeLeft मुफ़्त प्रश्न शेष'
                                : '$freeLeft of 2 free questions left this month')
                          : _isPremiumUser
                          ? (_isHindi
                                ? 'इस महीने के मुफ़्त प्रश्न समाप्त — ₹59 प्रति प्रश्न, कोई सीमा नहीं'
                                : 'Monthly free questions used — ₹59 each, no limit')
                          : (_isHindi
                                ? '₹59 प्रति प्रश्न (₹50 + GST) · जितने चाहें'
                                : '₹59 per question (₹50 + GST) · no limit'),
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: hasFreeLeft ? primaryColor : Colors.orange,
                      ),
                    ),
                    Text(
                      _isHindi
                          ? 'भुगतान क्रेडिट तैयार: $_paidQuestionBalance · कुल $_totalQuestionsUsed'
                          : 'Paid credits ready: $_paidQuestionBalance · asked $_totalQuestionsUsed',
                      style: GoogleFonts.outfit(fontSize: 11, color: textSec),
                    ),
                  ],
                ),
              ),
              if (_isPremiumUser)
                Row(
                children: List.generate(_freeQuotaPerPremium, (i) {
                  final used = i < _freeQuestionsUsed;
                  return Container(
                    margin: const EdgeInsets.only(left: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: used ? Colors.grey.withAlpha(80) : primaryColor,
                      border: Border.all(
                        color: used ? Colors.grey : primaryColor,
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),

        // Question input
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _isHindi ? 'अपना प्रश्न लिखें' : 'Ask your question',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                  const Spacer(),
                  // Microphone button
                  if (_speechAvailable)
                    _buildMicButton(primaryColor),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isListening ? primaryColor : border,
                    width: _isListening ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _questionController,
                      maxLines: 4,
                      maxLength: 500,
                      style: GoogleFonts.outfit(fontSize: 14, color: textPri),
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? (_isHindi ? 'सुन रहा हूँ...' : 'Listening...')
                            : (_isHindi
                                  ? 'उदाहरण: मेरी करियर रेखा क्या कहती है?'
                                  : 'e.g. What does my career line say about my future?'),
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 13,
                          color: _isListening
                              ? primaryColor
                              : (isDark
                                    ? AppTheme.textMuted
                                    : AppTheme.textMutedLight),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                        counterStyle: GoogleFonts.outfit(
                          fontSize: 11,
                          color: isDark
                              ? AppTheme.textMuted
                              : AppTheme.textMutedLight,
                        ),
                      ),
                    ),
                    if (_isListening)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: Row(
                          children: [
                            _buildListeningIndicator(primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              _isHindi ? 'बोलें...' : 'Speak now...',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _stopListening,
                              child: Text(
                                _isHindi ? 'रोकें' : 'Stop',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _isSubmitting
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : hasFreeLeft
                    ? ElevatedButton.icon(
                        onPressed: _submitFreeQuestion,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _isHindi ? 'मुफ़्त में पूछें' : 'Ask Free',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _purchaseAndSubmitQuestion,
                        icon: const Icon(
                          Icons.currency_rupee_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _isHindi
                              ? '₹59 में पूछें (₹50 + GST)'
                              : 'Ask for ₹59 (₹50 + GST)',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
              ),
              if (!hasFreeLeft) ...[
                const SizedBox(height: 8),
                Text(
                  _isHindi
                      ? '* ₹50 + 18% GST = ₹59 प्रति प्रश्न'
                      : '* ₹50 + 18% GST = ₹59 per question',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark
                        ? AppTheme.textMuted
                        : AppTheme.textMutedLight,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Question history
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          )
        else if (_questionHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  _isHindi ? 'पिछले प्रश्न' : 'Previous Questions',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPri,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _questionHistory.length,
              itemBuilder: (context, index) {
                final q = _questionHistory[index];
                final isFree = q['is_free'] == true;
                final status = q['status'] as String? ?? 'pending';
                final hasAnswer =
                    (q['answer_text'] as String?)?.isNotEmpty == true;
                final createdAt = q['created_at'] != null
                    ? DateTime.tryParse(q['created_at'] as String)
                    : null;
                final isRecovery =
                    status == 'payment_received_pending_question';
                final isCancelled = status == 'payment_cancelled';
                final isFailed = status == 'failed';

                // Skip cancelled/recovery records in history display
                if (isCancelled) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surfaceEl,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isFree
                                  ? Colors.green.withAlpha(30)
                                  : Colors.orange.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isFree
                                    ? Colors.green.withAlpha(80)
                                    : Colors.orange.withAlpha(80),
                              ),
                            ),
                            child: Text(
                              isFree ? (_isHindi ? 'मुफ़्त' : 'Free') : '₹50',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isFree ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: status == 'answered'
                                  ? Colors.blue.withAlpha(30)
                                  : isFailed
                                  ? Colors.red.withAlpha(30)
                                  : isRecovery
                                  ? Colors.orange.withAlpha(30)
                                  : Colors.grey.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status == 'answered'
                                  ? (_isHindi ? 'उत्तर दिया' : 'Answered')
                                  : isFailed
                                  ? (_isHindi ? 'विफल' : 'Failed')
                                  : isRecovery
                                  ? (_isHindi
                                        ? 'भुगतान प्राप्त'
                                        : 'Payment Received')
                                  : (_isHindi ? 'प्रतीक्षारत' : 'Pending'),
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: status == 'answered'
                                    ? Colors.blue
                                    : isFailed
                                    ? Colors.red
                                    : isRecovery
                                    ? Colors.orange
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          if (_pollingQuestionIds.contains(q['id']) &&
                              status != 'answered' &&
                              !isFailed) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isHindi ? 'उत्तर बन रहा है…' : 'Generating…',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (createdAt != null)
                            Text(
                              '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: textSec,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (isRecovery)
                        Text(
                          _isHindi
                              ? 'भुगतान सफल — प्रश्न दर्ज करने की प्रतीक्षा'
                              : 'Payment received — awaiting question entry',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: textSec,
                          ),
                        )
                      else
                        Text(
                          q['question_text'] as String? ?? '',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPri,
                            height: 1.5,
                          ),
                        ),
                      if (hasAnswer) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: primaryColor.withAlpha(40),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.psychology_rounded,
                                    size: 13,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isHindi
                                        ? 'HastVeda का उत्तर'
                                        : 'HastVeda Answer',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: primaryColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Speaker/TTS button
                                  GestureDetector(
                                    onTap: () => _speakAnswer(
                                      q['id'] as String,
                                      q['answer_text'] as String,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color:
                                            (_isSpeaking &&
                                                _speakingAnswerId ==
                                                    q['id'] as String?)
                                            ? primaryColor.withAlpha(30)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        (_isSpeaking &&
                                                _speakingAnswerId ==
                                                    q['id'] as String?)
                                            ? Icons.stop_circle_rounded
                                            : Icons.volume_up_rounded,
                                        size: 18,
                                        color:
                                            (_isSpeaking &&
                                                _speakingAnswerId ==
                                                    q['id'] as String?)
                                            ? Colors.red
                                            : primaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                q['answer_text'] as String,
                                softWrap: true,
                                overflow: TextOverflow.visible,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: textPri,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isFailed) ...[
                        const SizedBox(height: 8),
                        Text(
                          _isHindi
                              ? 'उत्तर देने में समस्या हुई। कृपया पुनः प्रयास करें।'
                              : 'Answer generation failed. Please try again.',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Colors.red.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            setState(() => _isSubmitting = true);
                            await _triggerAnswerFunction(q['id'] as String);
                            await Future.delayed(const Duration(seconds: 2));
                            await _loadQuestionHistory();
                            if (mounted) setState(() => _isSubmitting = false);
                          },
                          child: Text(
                            _isHindi ? 'पुनः प्रयास करें' : 'Retry',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 56,
                      color: isDark
                          ? AppTheme.textMuted
                          : AppTheme.textMutedLight,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isHindi
                          ? 'अपना पहला प्रश्न पूछें!'
                          : 'Ask your first question!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPremiumUser
                          ? (_isHindi
                                ? 'प्रीमियम में हर महीने 2 मुफ़्त प्रश्न मिलते हैं। उसके बाद ₹59 प्रति प्रश्न।'
                                : 'Premium includes 2 free questions each month. After that, each question is ₹59.')
                          : (_isHindi
                                ? 'हर प्रश्न ₹59 (₹50 + GST) का है। जितने चाहें पूछ सकते हैं।'
                                : 'Each question is ₹59 (₹50 + GST). Ask as many as you want.'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: 13, color: textSec),
                    ),
                    if (_speechAvailable) ...[
                      const SizedBox(height: 20),
                      Text(
                        _isHindi
                            ? '🎤 माइक्रोफ़ोन से भी पूछ सकते हैं'
                            : '🎤 You can also ask using your microphone',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.textMuted
                              : AppTheme.textMutedLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
      ),
    );
  }

  Widget _buildMicButton(Color primaryColor) {
    return GestureDetector(
      onTap: _startListening,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _isListening
              ? Colors.red.withAlpha(20)
              : primaryColor.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isListening ? Colors.red : primaryColor.withAlpha(60),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isListening ? Icons.mic_off_rounded : Icons.mic_rounded,
              size: 18,
              color: _isListening ? Colors.red : primaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              _isListening
                  ? (_isHindi ? 'रोकें' : 'Stop')
                  : (_isHindi ? 'बोलें' : 'Speak'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isListening ? Colors.red : primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListeningIndicator(Color primaryColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 300 + i * 100),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 4,
          height: 4 + (i * 4).toDouble(),
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
