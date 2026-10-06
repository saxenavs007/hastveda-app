import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/indian_tts.dart';
import '../../services/speech_text.dart';
import '../../services/app_strings.dart';
import '../../services/error_logger.dart';
import '../../services/locale_provider.dart';
import '../../services/reading_narration.dart';
import '../../services/web_speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hastveda_error_widget.dart';

/// Reading History Screen (separate from Report History)
class ReadingHistoryScreen extends StatefulWidget {
  final String locale;
  const ReadingHistoryScreen({super.key, this.locale = 'en'});

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _readings = [];

  // Compare mode state
  bool _compareMode = false;
  final Set<String> _selectedForCompare = {};

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _loadReadings();
    analytics.track(HastVedaEvents.readingHistoryViewed);
  }

  Future<void> _loadAndShowCoupleReading(
    BuildContext ctx,
    String coupleReadingId,
    Map<String, dynamic> historyRecord,
  ) async {
    try {
      final data = await Supabase.instance.client
          .from('couple_readings')
          .select()
          .eq('id', coupleReadingId)
          .maybeSingle();

      if (data == null || !ctx.mounted) return;

      final compatData =
          data['compatibility_data'] as Map<String, dynamic>? ?? {};
      final locale = data['language'] as String? ?? widget.locale;

      ctx.push(
        AppRoutes.coupleReadingResult,
        extra: {
          'person1Name': data['person1_name'] as String? ?? 'Person 1',
          'person2Name': data['person2_name'] as String? ?? 'Person 2',
          'compatibility': {
            ...compatData,
            'id': coupleReadingId,
            'person1_name': data['person1_name'] as String? ?? 'Person 1',
            'person2_name': data['person2_name'] as String? ?? 'Person 2',
            'overall_compatibility_score': data['overall_compatibility_score'],
            'love_score': data['love_score'],
            'emotional_score': data['emotional_score'],
            'communication_score': data['communication_score'],
            'financial_score': data['financial_score'],
            'career_score': data['career_score'],
            'personality_score': data['personality_score'],
            'attraction_score': data['attraction_score'],
            'marriage_score': data['marriage_score'],
          },
          'locale': locale,
        },
      );
    } catch (e) {
      debugPrint('Load couple reading error: $e');
      await errorLogger.log(
        category: ErrorCategory.readingHistory,
        operation: 'load_couple_reading',
        userMessage: 'Could not load reading. Please try again.',
        error: e,
        severity: ErrorSeverity.medium,
      );
    }
  }

  Future<void> _loadReadings() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final data = await Supabase.instance.client
          .from('reading_history')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _readings = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Reading history load error: $e');
      await errorLogger.logSupabaseError(
        operation: 'load_reading_history',
        error: e,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  String _readingNarration(Map<String, dynamic> reading, bool hindi) {
    final title = (reading['title'] as String?)?.trim();
    final summary = (reading['summary'] as String?)?.trim() ?? '';
    final heading = title != null && title.isNotEmpty
        ? title
        : (hindi ? 'हस्तरेखा पठन' : 'Palm Reading');
    return [heading, summary].where((part) => part.isNotEmpty).join('. ');
  }

  // Single readings only (not couple) for comparison
  List<Map<String, dynamic>> get _singleReadings => _readings
      .where((r) => (r['reading_type'] as String? ?? '') != 'couple')
      .toList();

  void _toggleCompareMode() {
    setState(() {
      _compareMode = !_compareMode;
      _selectedForCompare.clear();
    });
  }

  void _toggleCompareSelection(String id) {
    setState(() {
      if (_selectedForCompare.contains(id)) {
        _selectedForCompare.remove(id);
      } else if (_selectedForCompare.length < 2) {
        _selectedForCompare.add(id);
      }
    });
  }

  void _openComparison() {
    if (_selectedForCompare.length != 2) return;
    final ids = _selectedForCompare.toList();
    context.push(
      '${AppRoutes.readingComparison}?locale=${widget.locale}',
      extra: {'reading_id_a': ids[0], 'reading_id_b': ids[1]},
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final subTextColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final borderColor = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    final singleCount = _singleReadings.length;
    final canShowCompare = singleCount >= 2;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        foregroundColor: textColor,
        elevation: 0,
        title: Text(
          _compareMode
              ? (_isHindi ? 'तुलना के लिए चुनें' : 'Select to Compare')
              : s.readingHistory,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            _compareMode
                ? Icons.close_rounded
                : Icons.arrow_back_ios_new_rounded,
          ),
          onPressed: _compareMode ? _toggleCompareMode : popOrHome,
        ),
        actions: [
          if (!_isLoading && !_hasError && canShowCompare && !_compareMode)
            TextButton.icon(
              onPressed: _toggleCompareMode,
              icon: const Icon(
                Icons.compare_arrows_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
              label: Text(
                s.compareReadings,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          if (_compareMode && _selectedForCompare.length == 2)
            TextButton(
              onPressed: _openComparison,
              child: Text(
                _isHindi ? 'तुलना करें' : 'Compare',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _hasError
          ? HastVedaInlineError(
              title: s.somethingWentWrong,
              message: s.troubleConnecting,
              onRetry: _loadReadings,
            )
          : _readings.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 64,
                      color: isDark
                          ? AppTheme.textMuted
                          : AppTheme.textMutedLight,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isHindi
                          ? 'आपकी हस्तरेखा यात्रा यहाँ से शुरू होती है'
                          : 'Your Palm Journey Starts Here',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isHindi
                          ? 'अपनी पहली हस्तरेखा स्कैन करें'
                          : 'Scan your palm to begin your reading journey.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: subTextColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.push(AppRoutes.palmScanScreen),
                      icon: const Icon(Icons.back_hand_rounded, size: 18),
                      label: Text(
                        _isHindi ? 'हस्तरेखा स्कैन करें' : 'Scan Your Palm',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Compare mode banner
                if (_compareMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: AppTheme.primary.withAlpha(20),
                    child: Text(
                      _selectedForCompare.isEmpty
                          ? (_isHindi
                                ? 'तुलना के लिए 2 पठन चुनें (केवल एकल पठन)'
                                : 'Select 2 readings to compare (single readings only)')
                          : _selectedForCompare.length == 1
                          ? (_isHindi
                                ? '1 चुना गया — 1 और चुनें'
                                : '1 selected — select 1 more')
                          : (_isHindi
                                ? '2 चुने गए — "तुलना करें" टैप करें'
                                : '2 selected — tap "Compare"'),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadReadings,
                    color: AppTheme.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _readings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final reading = _readings[index];
                        final createdAt = reading['created_at'] != null
                            ? DateTime.tryParse(reading['created_at'] as String)
                            : null;
                        final readingType =
                            reading['reading_type'] as String? ?? 'single';
                        final isCouple = readingType == 'couple';
                        final metadata =
                            reading['metadata'] as Map<String, dynamic>? ?? {};
                        final readingId = reading['id'] as String;
                        final isSelectableForCompare =
                            _compareMode && !isCouple;
                        final isSelectedForCompare = _selectedForCompare
                            .contains(readingId);
                        final isDisabledForCompare =
                            _compareMode &&
                            !isCouple &&
                            !isSelectedForCompare &&
                            _selectedForCompare.length >= 2;

                        return GestureDetector(
                          onTap: () {
                            if (_compareMode) {
                              if (!isCouple) {
                                _toggleCompareSelection(readingId);
                              }
                              return;
                            }
                            if (isCouple) {
                              final coupleReadingId =
                                  metadata['couple_reading_id'] as String?;
                              if (coupleReadingId != null) {
                                _loadAndShowCoupleReading(
                                  context,
                                  coupleReadingId,
                                  reading,
                                );
                              }
                            } else {
                              final currentLocale = context
                                  .read<LocaleProvider>()
                                  .languageCode;
                              var autoSpeak = true;
                              if (kIsWeb) {
                                final script = _readingNarration(
                                  reading,
                                  currentLocale == 'hi',
                                );
                                if (script.isNotEmpty) {
                                  final started = WebSpeech.speak(
                                    text: script,
                                    hindi: currentLocale == 'hi',
                                    onDone: () => ReadingNarration.instance
                                        .setSpeaking(false),
                                    onError: (message) {
                                      debugPrint(
                                        'Reading TTS autoplay failed: $message',
                                      );
                                      ReadingNarration.instance.setSpeaking(
                                        false,
                                      );
                                    },
                                  );
                                  if (started) {
                                    ReadingNarration.instance.setSpeaking(true);
                                    autoSpeak = false;
                                  }
                                }
                              }
                              context.push(
                                '${AppRoutes.detailedReading}?locale=$currentLocale',
                                extra: {
                                  'readingId': reading['id'],
                                  'autoSpeak': autoSpeak,
                                },
                              );
                            }
                          },
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: isDisabledForCompare ? 0.4 : 1.0,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelectedForCompare
                                    ? AppTheme.primary.withAlpha(18)
                                    : surfaceColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelectedForCompare
                                      ? AppTheme.primary.withAlpha(120)
                                      : borderColor,
                                  width: isSelectedForCompare ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Leading icon / compare checkbox
                                  if (isSelectableForCompare)
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelectedForCompare
                                            ? AppTheme.primary
                                            : (isDark
                                                  ? AppTheme.surfaceElevated
                                                  : AppTheme
                                                        .surfaceElevatedLight),
                                        border: Border.all(
                                          color: isSelectedForCompare
                                              ? AppTheme.primary
                                              : borderColor,
                                        ),
                                      ),
                                      child: Center(
                                        child: isSelectedForCompare
                                            ? Text(
                                                _selectedForCompare
                                                            .toList()
                                                            .indexOf(
                                                              readingId,
                                                            ) ==
                                                        0
                                                    ? 'A'
                                                    : 'B',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  color: const Color(
                                                    0xFF0A0A0F,
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                Icons.radio_button_unchecked,
                                                size: 18,
                                                color: subTextColor,
                                              ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isCouple
                                            ? const Color(
                                                0xFFEC4899,
                                              ).withAlpha(15)
                                            : AppTheme.primary.withAlpha(15),
                                      ),
                                      child: Icon(
                                        isCouple
                                            ? Icons.favorite_rounded
                                            : Icons.back_hand_rounded,
                                        color: isCouple
                                            ? const Color(0xFFEC4899)
                                            : AppTheme.primary,
                                        size: 22,
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          reading['title'] as String? ??
                                              (_isHindi
                                                  ? 'हस्तरेखा पठन'
                                                  : 'Palm Reading'),
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (createdAt != null)
                                          Text(
                                            '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              color: subTextColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isCouple)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFEC4899,
                                        ).withAlpha(15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _isHindi ? 'जोड़ी' : 'Couple',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFEC4899),
                                        ),
                                      ),
                                    ),
                                  if (!isCouple && !_compareMode) ...[
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () {
                                        final analysisId =
                                            reading['analysis_id'] as String? ??
                                            metadata['analysis_id'] as String?;
                                        context.push(
                                          '${AppRoutes.detailedReport}?locale=${context.read<LocaleProvider>().languageCode}',
                                          extra: {
                                            'analysis_id': analysisId,
                                            'reading_id':
                                                reading['id'] as String?,
                                          },
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withAlpha(15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          _isHindi ? 'रिपोर्ट' : 'Report',
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 4),
                                  if (!_compareMode)
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFFD4C5BB),
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
      // Compare mode FAB
      floatingActionButton: _compareMode && _selectedForCompare.length == 2
          ? FloatingActionButton.extended(
              onPressed: _openComparison,
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF0A0A0F),
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text(
                _isHindi ? 'तुलना करें' : 'Compare Now',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }
}

/// Detailed Reading Screen (single reading view)
class DetailedReadingScreen extends StatefulWidget {
  final String? readingId;
  final String locale;
  final bool autoSpeak;

  const DetailedReadingScreen({
    super.key,
    this.readingId,
    this.locale = 'en',
    this.autoSpeak = true,
  });

  @override
  State<DetailedReadingScreen> createState() => _DetailedReadingScreenState();
}

class _DetailedReadingScreenState extends State<DetailedReadingScreen> {
  bool _isLoading = true;
  bool _isSpeaking = false;
  bool _speakingChunks = false;
  bool _autoSpeakDone = false;
  int _speakGeneration = 0;
  Map<String, dynamic>? _reading;
  final FlutterTts _tts = FlutterTts();
  // Always derive language from the live provider so the reading detail
  // reflects the current app language, not the route parameter default.
  bool get _isHindi => context.read<LocaleProvider>().languageCode == 'hi';

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (_speakingChunks || !mounted) return;
      setState(() => _isSpeaking = false);
    });
    _tts.setCancelHandler(() {
      if (_speakingChunks || !mounted) return;
      setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((message) {
      debugPrint('Reading detail TTS error: $message');
      if (_speakingChunks || !mounted) return;
      setState(() => _isSpeaking = false);
    });
    if (!widget.autoSpeak) {
      ReadingNarration.instance.addListener(_syncNarration);
      _isSpeaking = ReadingNarration.instance.speaking;
    }
    _loadReading();
  }

  void _syncNarration() {
    if (!mounted) return;
    final speaking = ReadingNarration.instance.speaking;
    if (speaking == _isSpeaking) return;
    setState(() => _isSpeaking = speaking);
  }

  @override
  void dispose() {
    if (!widget.autoSpeak) {
      ReadingNarration.instance.removeListener(_syncNarration);
    }
    _haltSpeech();
    super.dispose();
  }

  void _haltSpeech() {
    _speakGeneration++;
    _speakingChunks = false;
    if (kIsWeb) {
      WebSpeech.stop();
      ReadingNarration.instance.setSpeaking(false);
    } else {
      _tts.stop();
    }
  }

  String? _localeCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = context.watch<LocaleProvider>().languageCode;
    if (_localeCode != null && _localeCode != code && _isSpeaking) {
      _isSpeaking = false;
      _haltSpeech();
    }
    _localeCode = code;
  }

  void _speakSummary(String title, String summary) {
    if (_isSpeaking) {
      _haltSpeech();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    final script = [title, summary]
        .where((part) => part.trim().isNotEmpty)
        .join('. ');
    if (script.isEmpty) return;
    _autoSpeakDone = true;
    _startSpeech(script, automatic: false);
  }

  void _scheduleAutoSpeak() {
    if (!widget.autoSpeak || _autoSpeakDone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoSpeakDone || _isSpeaking) return;
      final title =
          _reading?['title'] as String? ??
          (_isHindi ? 'हस्तरेखा पठन' : 'Palm Reading');
      final summary = _reading?['summary'] as String? ?? '';
      final script = [title, summary]
          .where((part) => part.trim().isNotEmpty)
          .join('. ');
      if (script.isEmpty) return;
      _autoSpeakDone = true;
      _startSpeech(script, automatic: true);
    });
  }

  void _startSpeech(String script, {required bool automatic}) {
    if (kIsWeb) {
      setState(() => _isSpeaking = true);
      ReadingNarration.instance.setSpeaking(true);
      final started = WebSpeech.speak(
        text: script,
        hindi: _isHindi,
        onDone: () {
          ReadingNarration.instance.setSpeaking(false);
          if (mounted) setState(() => _isSpeaking = false);
        },
        onError: (message) {
          ReadingNarration.instance.setSpeaking(false);
          _reportSpeechFailure(message, automatic: automatic);
        },
      );
      if (!started) {
        ReadingNarration.instance.setSpeaking(false);
        if (mounted) setState(() => _isSpeaking = false);
      }
      return;
    }

    unawaited(_speakSummaryNative(script, automatic: automatic));
  }

  Future<void> _speakSummaryNative(
    String script, {
    required bool automatic,
  }) async {
    final generation = ++_speakGeneration;
    try {
      await _tts.awaitSpeakCompletion(true);
      await IndianTts.apply(_tts, hindi: _isHindi);
      if (!mounted || generation != _speakGeneration) return;
      _speakingChunks = true;
      setState(() => _isSpeaking = true);
      for (final chunk in SpeechText.chunks(script)) {
        if (!mounted || generation != _speakGeneration) {
          _speakingChunks = false;
          return;
        }
        await _tts.speak(chunk);
      }
      _speakingChunks = false;
      if (mounted && generation == _speakGeneration) {
        setState(() => _isSpeaking = false);
      }
    } catch (e) {
      _speakingChunks = false;
      _reportSpeechFailure('$e', automatic: automatic);
    }
  }

  void _reportSpeechFailure(String message, {required bool automatic}) {
    debugPrint('Reading detail TTS failed: $message');
    unawaited(
      errorLogger.log(
        category: ErrorCategory.ui,
        operation: automatic ? 'reading_tts_autoplay' : 'reading_tts',
        userMessage: 'Could not play the reading aloud.',
        error: message,
        severity: ErrorSeverity.low,
      ),
    );
    if (!mounted) return;
    setState(() => _isSpeaking = false);
    if (automatic) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isHindi
              ? 'आवाज़ नहीं चल सकी। फिर से कोशिश करें।'
              : 'Could not play audio. Please try again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadReading() async {
    if (widget.readingId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('reading_history')
          .select()
          .eq('id', widget.readingId!)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _reading = data;
          _isLoading = false;
        });
        if (data != null) _scheduleAutoSpeak();
      }
    } catch (e) {
      debugPrint('DetailedReadingScreen load error: $e');
      unawaited(
        errorLogger.logSupabaseError(
          operation: 'load_detailed_reading',
          error: e,
        ),
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider so the widget rebuilds when language changes.
    final localeProvider = context.watch<LocaleProvider>();
    final currentLocale = localeProvider.languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;

    final createdAt = _reading?['created_at'] != null
        ? DateTime.tryParse(_reading!['created_at'] as String)
        : null;
    final analysisId = _reading?['analysis_id'] as String?;
    final readingTitle =
        _reading?['title'] as String? ??
        (_isHindi ? 'हस्तरेखा पठन' : 'Palm Reading');
    final summary = _reading?['summary'] as String? ?? '';
    final isPremium = _reading?['is_premium'] as bool? ?? false;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: Text(
          _isHindi ? 'पठन विवरण' : 'Reading Detail',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: popOrHome,
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reading header card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withAlpha(60)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.back_hand_rounded,
                              color: AppTheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    readingTitle,
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (createdAt != null)
                                    Text(
                                      '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: _isHindi
                                  ? (_isSpeaking ? 'रोकें' : 'पढ़कर सुनाएँ')
                                  : (_isSpeaking ? 'Stop' : 'Listen'),
                              onPressed: () => _speakSummary(readingTitle, summary),
                              icon: Icon(
                                _isSpeaking
                                    ? Icons.stop_circle_rounded
                                    : Icons.volume_up_rounded,
                                color: AppTheme.primary,
                              ),
                            ),
                            if (isPremium)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withAlpha(30),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppTheme.primary.withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  _isHindi ? 'प्रीमियम' : 'Premium',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            summary,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white70,
                              height: 1.6,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          _isHindi
                              ? 'हस्तरेखा पारंपरिक व्याख्या है — वैज्ञानिक तथ्य नहीं।'
                              : 'Palmistry is interpretive — not scientific fact.',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Colors.white38,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // View full analysis button (if analysisId available)
                  if (analysisId != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _haltSpeech();
                          if (mounted) setState(() => _isSpeaking = false);
                          context.push(
                            '${AppRoutes.palmAnalysis}?locale=$currentLocale',
                            extra: {'analysis_id': analysisId},
                          );
                        },
                        icon: const Icon(Icons.back_hand_rounded, size: 18),
                        label: Text(
                          _isHindi
                              ? 'पूर्ण विश्लेषण देखें'
                              : 'View Full Analysis',
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
                    const SizedBox(height: 12),
                  ],

                  _ReadingSection(
                    title: _isHindi ? 'भविष्यवाणियां' : 'Predictions',
                    onTap: () => context.push(AppRoutes.predictionsScreen),
                  ),
                  const SizedBox(height: 10),
                  _ReadingSection(
                    title: _isHindi ? 'विस्तृत रिपोर्ट' : 'Detailed Report',
                    onTap: () => context.push(
                      '${AppRoutes.detailedReport}?locale=$currentLocale',
                      extra: {
                        'analysis_id': analysisId,
                        'reading_id': widget.readingId,
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _ReadingSection extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _ReadingSection({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final borderColor = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
