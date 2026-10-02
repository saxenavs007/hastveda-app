import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart' as prov;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/ai_client.dart';
import '../../core/services/aiIntegrations/chat_completion_service.dart';
import '../../routes/app_routes.dart';
import '../../services/app_strings.dart';
import '../../services/error_logger.dart';
import '../../services/locale_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hastveda_error_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Change indicator enum
// ─────────────────────────────────────────────────────────────────────────────
enum ChangeType {
  improved,
  declined,
  unchanged,
  newInsight,
  noSignificantChange,
}

extension ChangeTypeExt on ChangeType {
  String label(bool isHindi) {
    switch (this) {
      case ChangeType.improved:
        return isHindi ? '↑ बेहतर' : '↑ Improved';
      case ChangeType.declined:
        return isHindi ? '↓ कम' : '↓ Declined';
      case ChangeType.unchanged:
        return isHindi ? '= अपरिवर्तित' : '= Unchanged';
      case ChangeType.newInsight:
        return isHindi ? '★ नई अंतर्दृष्टि' : '★ New Insight';
      case ChangeType.noSignificantChange:
        return isHindi ? '~ कोई बड़ा बदलाव नहीं' : '~ No Significant Change';
    }
  }

  Color get color {
    switch (this) {
      case ChangeType.improved:
        return const Color(0xFF2ECC8A);
      case ChangeType.declined:
        return const Color(0xFFE05555);
      case ChangeType.unchanged:
        return const Color(0xFF9A96A8);
      case ChangeType.newInsight:
        return const Color(0xFF00C8E0);
      case ChangeType.noSignificantChange:
        return const Color(0xFF9A96A8);
    }
  }

  Color get bgColor {
    switch (this) {
      case ChangeType.improved:
        return const Color(0xFF0A2A1E);
      case ChangeType.declined:
        return const Color(0xFF2A0A0A);
      case ChangeType.unchanged:
        return const Color(0xFF1A1A26);
      case ChangeType.newInsight:
        return const Color(0xFF001E24);
      case ChangeType.noSignificantChange:
        return const Color(0xFF1A1A26);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point: Reading Selection Screen
// ─────────────────────────────────────────────────────────────────────────────
class ReadingSelectionScreen extends StatefulWidget {
  final String locale;
  const ReadingSelectionScreen({super.key, this.locale = 'en'});

  @override
  State<ReadingSelectionScreen> createState() => _ReadingSelectionScreenState();
}

class _ReadingSelectionScreenState extends State<ReadingSelectionScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _readings = [];
  String? _selectedIdA;
  String? _selectedIdB;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _loadReadings();
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
      // Only single palm readings (not couple) that belong to this user
      final data = await Supabase.instance.client
          .from('reading_history')
          .select()
          .eq('user_id', userId)
          .neq('reading_type', 'couple')
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _readings = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ReadingSelection load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIdA == id) {
        _selectedIdA = null;
      } else if (_selectedIdB == id) {
        _selectedIdB = null;
      } else if (_selectedIdA == null) {
        _selectedIdA = id;
      } else
        _selectedIdB ??= id;
      // If both already selected, do nothing (user must deselect one first)
    });
  }

  bool _isSelected(String id) => _selectedIdA == id || _selectedIdB == id;

  int _selectionIndex(String id) {
    if (_selectedIdA == id) return 1;
    if (_selectedIdB == id) return 2;
    return 0;
  }

  void _startComparison() {
    if (_selectedIdA == null || _selectedIdB == null) return;
    context.push(
      '${AppRoutes.readingComparison}?locale=${widget.locale}',
      extra: {'reading_id_a': _selectedIdA, 'reading_id_b': _selectedIdB},
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = prov.Provider.of<LocaleProvider>(context);
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final subTextColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;
    final borderColor = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    final canCompare = _selectedIdA != null && _selectedIdB != null;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        foregroundColor: textColor,
        elevation: 0,
        title: Text(
          s.compareReadings,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
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
          : _readings.length < 2
          ? _buildEmptyState(s, isDark, textColor, subTextColor)
          : Column(
              children: [
                _buildSelectionHeader(
                  s,
                  isDark,
                  surfaceColor,
                  textColor,
                  subTextColor,
                  borderColor,
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadReadings,
                    color: AppTheme.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _readings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final r = _readings[index];
                        return _ReadingSelectCard(
                          reading: r,
                          isHindi: _isHindi,
                          isSelected: _isSelected(r['id'] as String),
                          selectionIndex: _selectionIndex(r['id'] as String),
                          isDark: isDark,
                          textColor: textColor,
                          subTextColor: subTextColor,
                          borderColor: borderColor,
                          surfaceColor: surfaceColor,
                          onTap: () => _toggleSelection(r['id'] as String),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _readings.length >= 2
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: canCompare ? _startComparison : null,
                    icon: const Icon(Icons.compare_arrows_rounded, size: 20),
                    label: Text(
                      canCompare
                          ? s.compareNow
                          : (_isHindi
                                ? 'दो पठन चुनें'
                                : 'Select 2 readings to compare'),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canCompare
                          ? AppTheme.primary
                          : AppTheme.disabled,
                      foregroundColor: canCompare
                          ? const Color(0xFF0A0A0F)
                          : AppTheme.textMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState(
    AppStrings s,
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_arrows_rounded,
              size: 64,
              color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
            ),
            const SizedBox(height: 20),
            Text(
              s.needTwoReadings,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.needTwoReadingsDesc,
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
                _isHindi ? 'हथेली स्कैन करें' : 'Scan Your Palm',
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
    );
  }

  Widget _buildSelectionHeader(
    AppStrings s,
    bool isDark,
    Color surfaceColor,
    Color textColor,
    Color subTextColor,
    Color borderColor,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isHindi
                ? 'तुलना के लिए दो पठन चुनें'
                : 'Select two readings to compare',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: subTextColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SelectionSlot(
                label: _isHindi ? 'पठन A' : 'Reading A',
                reading: _selectedIdA != null
                    ? _readings.firstWhere(
                        (r) => r['id'] == _selectedIdA,
                        orElse: () => {},
                      )
                    : null,
                isHindi: _isHindi,
                isDark: isDark,
                textColor: textColor,
                subTextColor: subTextColor,
                borderColor: borderColor,
                onClear: () => setState(() => _selectedIdA = null),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.compare_arrows_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              _SelectionSlot(
                label: _isHindi ? 'पठन B' : 'Reading B',
                reading: _selectedIdB != null
                    ? _readings.firstWhere(
                        (r) => r['id'] == _selectedIdB,
                        orElse: () => {},
                      )
                    : null,
                isHindi: _isHindi,
                isDark: isDark,
                textColor: textColor,
                subTextColor: subTextColor,
                borderColor: borderColor,
                onClear: () => setState(() => _selectedIdB = null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selection slot widget
// ─────────────────────────────────────────────────────────────────────────────
class _SelectionSlot extends StatelessWidget {
  final String label;
  final Map<String, dynamic>? reading;
  final bool isHindi;
  final bool isDark;
  final Color textColor;
  final Color subTextColor;
  final Color borderColor;
  final VoidCallback onClear;

  const _SelectionSlot({
    required this.label,
    required this.reading,
    required this.isHindi,
    required this.isDark,
    required this.textColor,
    required this.subTextColor,
    required this.borderColor,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasReading = reading != null && reading!.isNotEmpty;
    final createdAt = hasReading && reading!['created_at'] != null
        ? DateTime.tryParse(reading!['created_at'] as String)
        : null;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasReading
              ? AppTheme.primary.withAlpha(20)
              : (isDark
                    ? AppTheme.surfaceElevated
                    : AppTheme.surfaceElevatedLight),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasReading ? AppTheme.primary.withAlpha(80) : borderColor,
          ),
        ),
        child: hasReading
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          reading!['title'] as String? ??
                              (isHindi ? 'पठन' : 'Reading'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
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
                              fontSize: 10,
                              color: subTextColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: subTextColor,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: subTextColor,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: subTextColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reading select card
// ─────────────────────────────────────────────────────────────────────────────
class _ReadingSelectCard extends StatelessWidget {
  final Map<String, dynamic> reading;
  final bool isHindi;
  final bool isSelected;
  final int selectionIndex; // 0=none, 1=A, 2=B
  final bool isDark;
  final Color textColor;
  final Color subTextColor;
  final Color borderColor;
  final Color surfaceColor;
  final VoidCallback onTap;

  const _ReadingSelectCard({
    required this.reading,
    required this.isHindi,
    required this.isSelected,
    required this.selectionIndex,
    required this.isDark,
    required this.textColor,
    required this.subTextColor,
    required this.borderColor,
    required this.surfaceColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt = reading['created_at'] != null
        ? DateTime.tryParse(reading['created_at'] as String)
        : null;
    final metadata = reading['metadata'] as Map<String, dynamic>? ?? {};
    final confidenceScore = metadata['confidence_score'] as num?;
    final summary = reading['summary'] as String? ?? '';
    final title =
        reading['title'] as String? ??
        (isHindi ? 'हस्तरेखा पठन' : 'Palm Reading');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withAlpha(18) : surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primary.withAlpha(120) : borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Selection badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppTheme.primary
                    : (isDark
                          ? AppTheme.surfaceElevated
                          : AppTheme.surfaceElevatedLight),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : borderColor,
                ),
              ),
              child: Center(
                child: isSelected
                    ? Text(
                        selectionIndex == 1 ? 'A' : 'B',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0A0A0F),
                        ),
                      )
                    : Icon(
                        Icons.back_hand_rounded,
                        size: 18,
                        color: subTextColor,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                      '${createdAt.day}/${createdAt.month}/${createdAt.year} · ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: subTextColor,
                      ),
                    ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        summary,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: subTextColor,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (confidenceScore != null) ...[
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(
                    '${confidenceScore.round()}%',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                  Text(
                    isHindi ? 'विश्वास' : 'Conf.',
                    style: GoogleFonts.outfit(fontSize: 9, color: subTextColor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comparison Screen
// ─────────────────────────────────────────────────────────────────────────────
class ReadingComparisonScreen extends ConsumerStatefulWidget {
  final String readingIdA;
  final String readingIdB;
  final String locale;

  const ReadingComparisonScreen({
    super.key,
    required this.readingIdA,
    required this.readingIdB,
    this.locale = 'en',
  });

  @override
  ConsumerState<ReadingComparisonScreen> createState() =>
      _ReadingComparisonScreenState();
}

class _ReadingComparisonScreenState
    extends ConsumerState<ReadingComparisonScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  Map<String, dynamic>? _readingA;
  Map<String, dynamic>? _readingB;
  Map<String, dynamic>? _analysisA;
  Map<String, dynamic>? _analysisB;

  bool _isAiLoading = false;
  String _aiComparison = '';
  bool _aiError = false;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _loadReadings();
  }

  Future<void> _loadReadings() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // Load both reading_history records (RLS enforced by user_id)
      final results = await Future.wait([
        Supabase.instance.client
            .from('reading_history')
            .select()
            .eq('id', widget.readingIdA)
            .eq('user_id', userId)
            .maybeSingle(),
        Supabase.instance.client
            .from('reading_history')
            .select()
            .eq('id', widget.readingIdB)
            .eq('user_id', userId)
            .maybeSingle(),
      ]);

      final rA = results[0];
      final rB = results[1];

      if (rA == null || rB == null) {
        throw Exception('One or both readings not found');
      }

      // Load palm_analysis for each if available
      final analysisIdA = rA['analysis_id'] as String?;
      final analysisIdB = rB['analysis_id'] as String?;

      Map<String, dynamic>? aA;
      Map<String, dynamic>? aB;

      if (analysisIdA != null) {
        aA = await Supabase.instance.client
            .from('palm_analysis')
            .select()
            .eq('id', analysisIdA)
            .eq('user_id', userId)
            .maybeSingle();
      }
      if (analysisIdB != null) {
        aB = await Supabase.instance.client
            .from('palm_analysis')
            .select()
            .eq('id', analysisIdB)
            .eq('user_id', userId)
            .maybeSingle();
      }

      if (mounted) {
        setState(() {
          _readingA = rA;
          _readingB = rB;
          _analysisA = aA;
          _analysisB = aB;
          _isLoading = false;
        });
        // Auto-trigger AI comparison
        _generateAiComparison();
      }
    } catch (e) {
      debugPrint('Comparison load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _generateAiComparison() async {
    if (_readingA == null || _readingB == null) return;
    setState(() {
      _isAiLoading = true;
      _aiError = false;
      _aiComparison = '';
    });

    try {
      final metaA = _readingA!['metadata'] as Map<String, dynamic>? ?? {};
      final metaB = _readingB!['metadata'] as Map<String, dynamic>? ?? {};

      final summaryA = _readingA!['summary'] as String? ?? '';
      final summaryB = _readingB!['summary'] as String? ?? '';

      // Build analysis snippets from stored data only
      final analysisSnippetA = _buildAnalysisSnippet(_analysisA, metaA);
      final analysisSnippetB = _buildAnalysisSnippet(_analysisB, metaB);

      final dateA = _readingA!['created_at'] != null
          ? DateTime.tryParse(_readingA!['created_at'] as String)
          : null;
      final dateB = _readingB!['created_at'] != null
          ? DateTime.tryParse(_readingB!['created_at'] as String)
          : null;

      final lang = _isHindi ? 'Hindi' : 'English';

      final systemPrompt =
          '''You are HastVeda, an AI palmistry assistant.
You are comparing two saved palm reading records for the same user.
Do NOT perform a new palm analysis. Only compare the existing stored data provided.
Respond entirely in $lang.
Keep your response concise (200-300 words).
Do not make medical, financial or guaranteed future predictions.
Add a brief disclaimer that palmistry is a traditional/spiritual interpretation.''';

      final userPrompt =
          '''Compare these two palm readings:

READING A (${dateA != null ? '${dateA.day}/${dateA.month}/${dateA.year}' : 'Earlier reading'}):
Summary: $summaryA
Analysis: $analysisSnippetA

READING B (${dateB != null ? '${dateB.day}/${dateB.month}/${dateB.year}' : 'Later reading'}):
Summary: $summaryB
Analysis: $analysisSnippetB

Please provide:
1. What changed between the two readings
2. What remained consistent
3. Which areas show the strongest change
4. Which areas show stability
5. A concise overall interpretation

Remember: compare only the stored data above. Do not invent new analysis.''';

      final response = await getChatCompletion(
        'GEMINI',
        'gemini/gemini-2.5-flash',
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        parameters: {'temperature': 0.4, 'max_tokens': 600},
      );

      final content =
          response['choices']?[0]?['message']?['content'] as String? ?? '';

      if (mounted) {
        setState(() {
          _aiComparison = content;
          _isAiLoading = false;
        });
      }
    } catch (e) {
      debugPrint('AI comparison error: $e');
      // Log the Gemini comparison failure
      await errorLogger.logGeminiError(
        operation: 'reading_comparison_ai',
        error: e,
        errorType: e is HastVedaAiException ? e.errorType : null,
      );
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _aiError = true;
        });
      }
    }
  }

  String _buildAnalysisSnippet(
    Map<String, dynamic>? analysis,
    Map<String, dynamic> meta,
  ) {
    if (analysis == null) {
      // Fall back to metadata
      final parts = <String>[];
      if (meta['career_insight'] != null) {
        parts.add('Career: ${meta['career_insight']}');
      }
      if (meta['relationship_insight'] != null) {
        parts.add('Relationships: ${meta['relationship_insight']}');
      }
      if (meta['personality_insight'] != null) {
        parts.add('Personality: ${meta['personality_insight']}');
      }
      return parts.isEmpty ? 'No detailed analysis stored.' : parts.join('\n');
    }

    final parts = <String>[];
    void addSection(String key, String label) {
      final section = analysis[key] as Map<String, dynamic>?;
      if (section != null && section.isNotEmpty) {
        final summary =
            section['summary'] as String? ??
            section['interpretation'] as String? ??
            section['description'] as String? ??
            '';
        if (summary.isNotEmpty) parts.add('$label: $summary');
      }
    }

    addSection('career_analysis', 'Career');
    addSection('love_analysis', 'Relationships');
    addSection('wealth_analysis', 'Finance');
    addSection('personality_analysis', 'Personality');
    addSection('life_analysis', 'Life');
    addSection('health_analysis', 'Health');

    final summary = analysis['summary'] as String? ?? '';
    if (summary.isNotEmpty) parts.add('Overall: $summary');

    return parts.isEmpty ? 'Stored analysis available.' : parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = prov.Provider.of<LocaleProvider>(context);
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final subTextColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.textSecondaryLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        foregroundColor: textColor,
        elevation: 0,
        title: Text(
          s.readingComparison,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _hasError
          ? HastVedaInlineError(
              title: s.somethingWentWrong,
              message: _errorMessage.isNotEmpty
                  ? _errorMessage
                  : s.troubleConnecting,
              onRetry: _loadReadings,
            )
          : RefreshIndicator(
              onRefresh: _loadReadings,
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header cards side by side
                    _buildReadingHeaderRow(isDark, textColor, subTextColor),
                    const SizedBox(height: 20),

                    // AI Comparison section
                    _buildAiSection(s, isDark, textColor, subTextColor),
                    const SizedBox(height: 20),

                    // Field-by-field comparison
                    _buildFieldComparisons(s, isDark, textColor, subTextColor),
                    const SizedBox(height: 20),

                    // Disclaimer
                    _buildDisclaimer(isDark, subTextColor),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildReadingHeaderRow(
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    return Row(
      children: [
        Expanded(
          child: _ReadingHeaderCard(
            label: _isHindi ? 'पठन A' : 'Reading A',
            reading: _readingA!,
            isHindi: _isHindi,
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
            accentColor: AppTheme.primary,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Icon(
                Icons.compare_arrows_rounded,
                color: AppTheme.primary,
                size: 28,
              ),
            ],
          ),
        ),
        Expanded(
          child: _ReadingHeaderCard(
            label: _isHindi ? 'पठन B' : 'Reading B',
            reading: _readingB!,
            isHindi: _isHindi,
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
            accentColor: AppTheme.cyan,
          ),
        ),
      ],
    );
  }

  Widget _buildAiSection(
    AppStrings s,
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final borderColor = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A26), Color(0xFF12121A)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withAlpha(30),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isHindi ? 'AI तुलना विश्लेषण' : 'AI Comparison Analysis',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (_aiError)
                  GestureDetector(
                    onTap: _generateAiComparison,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isHindi ? 'पुनः प्रयास' : 'Retry',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: _isAiLoading
                ? Column(
                    children: [
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isHindi
                            ? 'AI तुलना तैयार हो रही है...'
                            : 'Generating AI comparison...',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: subTextColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  )
                : _aiError
                ? Text(
                    _isHindi
                        ? 'AI तुलना उत्पन्न करने में असमर्थ। ऊपर "पुनः प्रयास" टैप करें।'
                        : 'Unable to generate AI comparison. Tap "Retry" above.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppTheme.error,
                      height: 1.5,
                    ),
                  )
                : _aiComparison.isEmpty
                ? Text(
                    _isHindi
                        ? 'AI तुलना उपलब्ध नहीं।'
                        : 'AI comparison not available.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: subTextColor,
                    ),
                  )
                : Text(
                    _aiComparison,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: textColor,
                      height: 1.6,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldComparisons(
    AppStrings s,
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    // Extract comparable fields from both analyses
    final fields = _extractComparableFields();
    if (fields.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isHindi ? 'क्षेत्र-वार तुलना' : 'Field-by-Field Comparison',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        ...fields.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ComparisonFieldCard(
              field: f,
              isHindi: _isHindi,
              isDark: isDark,
              textColor: textColor,
              subTextColor: subTextColor,
            ),
          ),
        ),
      ],
    );
  }

  List<_ComparisonField> _extractComparableFields() {
    final fields = <_ComparisonField>[];

    // Helper to extract text from an analysis section
    String extractText(Map<String, dynamic>? analysis, String key) {
      if (analysis == null) return '';
      final section = analysis[key] as Map<String, dynamic>?;
      if (section == null) return '';
      return section['summary'] as String? ??
          section['interpretation'] as String? ??
          section['description'] as String? ??
          '';
    }

    // Helper to extract from metadata
    String extractMeta(Map<String, dynamic>? reading, String key) {
      if (reading == null) return '';
      final meta = reading['metadata'] as Map<String, dynamic>? ?? {};
      return meta[key] as String? ?? '';
    }

    final sectionDefs = [
      {
        'key': 'career_analysis',
        'metaKey': 'career_insight',
        'labelEn': 'Career',
        'labelHi': 'करियर',
      },
      {
        'key': 'love_analysis',
        'metaKey': 'relationship_insight',
        'labelEn': 'Relationships',
        'labelHi': 'रिश्ते',
      },
      {
        'key': 'wealth_analysis',
        'metaKey': 'financial_insight',
        'labelEn': 'Finance',
        'labelHi': 'वित्त',
      },
      {
        'key': 'personality_analysis',
        'metaKey': 'personality_insight',
        'labelEn': 'Personality',
        'labelHi': 'व्यक्तित्व',
      },
      {
        'key': 'life_analysis',
        'metaKey': 'life_insight',
        'labelEn': 'Life Direction',
        'labelHi': 'जीवन दिशा',
      },
      {
        'key': 'health_analysis',
        'metaKey': 'health_insight',
        'labelEn': 'Vitality',
        'labelHi': 'जीवन शक्ति',
      },
    ];

    for (final def in sectionDefs) {
      final textA = extractText(_analysisA, def['key']!).isNotEmpty
          ? extractText(_analysisA, def['key']!)
          : extractMeta(_readingA, def['metaKey']!);
      final textB = extractText(_analysisB, def['key']!).isNotEmpty
          ? extractText(_analysisB, def['key']!)
          : extractMeta(_readingB, def['metaKey']!);

      if (textA.isEmpty && textB.isEmpty) continue;

      ChangeType changeType;
      if (textA.isEmpty && textB.isNotEmpty) {
        changeType = ChangeType.newInsight;
      } else if (textA.isNotEmpty && textB.isEmpty) {
        changeType = ChangeType.noSignificantChange;
      } else if (textA == textB) {
        changeType = ChangeType.unchanged;
      } else {
        // Simple heuristic: check for positive/negative keywords
        changeType = _inferChangeType(textA, textB);
      }

      fields.add(
        _ComparisonField(
          labelEn: def['labelEn']!,
          labelHi: def['labelHi']!,
          textA: textA,
          textB: textB,
          changeType: changeType,
        ),
      );
    }

    // Also compare overall confidence scores
    final confA =
        _analysisA?['confidence_score'] as num? ??
        (_readingA?['metadata'] as Map<String, dynamic>?)?['confidence_score']
            as num?;
    final confB =
        _analysisB?['confidence_score'] as num? ??
        (_readingB?['metadata'] as Map<String, dynamic>?)?['confidence_score']
            as num?;

    if (confA != null && confB != null) {
      ChangeType ct;
      if ((confB - confA).abs() < 3) {
        ct = ChangeType.unchanged;
      } else if (confB > confA) {
        ct = ChangeType.improved;
      } else {
        ct = ChangeType.declined;
      }
      fields.insert(
        0,
        _ComparisonField(
          labelEn: 'Confidence Score',
          labelHi: 'विश्वास स्कोर',
          textA: '${confA.round()}%',
          textB: '${confB.round()}%',
          changeType: ct,
        ),
      );
    }

    return fields;
  }

  ChangeType _inferChangeType(String textA, String textB) {
    // Simple keyword-based heuristic — only used when both texts exist and differ
    final positiveWords = [
      'strong',
      'excellent',
      'great',
      'positive',
      'good',
      'high',
      'success',
      'growth',
      'improve',
      'better',
      'शक्तिशाली',
      'उत्कृष्ट',
      'अच्छा',
      'सफलता',
    ];
    final negativeWords = [
      'weak',
      'challenge',
      'difficult',
      'low',
      'poor',
      'struggle',
      'decline',
      'कमज़ोर',
      'चुनौती',
      'कठिन',
      'कम',
    ];

    int scoreA = 0, scoreB = 0;
    for (final w in positiveWords) {
      if (textA.toLowerCase().contains(w)) scoreA++;
      if (textB.toLowerCase().contains(w)) scoreB++;
    }
    for (final w in negativeWords) {
      if (textA.toLowerCase().contains(w)) scoreA--;
      if (textB.toLowerCase().contains(w)) scoreB--;
    }

    if ((scoreB - scoreA).abs() <= 1) return ChangeType.noSignificantChange;
    if (scoreB > scoreA) return ChangeType.improved;
    return ChangeType.declined;
  }

  Widget _buildDisclaimer(bool isDark, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.surfaceElevated.withAlpha(80)
            : AppTheme.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.outlineDark : AppTheme.outlineLight,
        ),
      ),
      child: Text(
        _isHindi
            ? 'हस्तरेखा एक पारंपरिक और आध्यात्मिक व्याख्या है। यह वैज्ञानिक रूप से सिद्ध भविष्यवाणी नहीं है। इसे चिकित्सा, वित्तीय या कानूनी सलाह के रूप में न लें।'
            : 'Palmistry is a traditional and spiritual interpretation. It is not scientifically proven prediction. Do not treat this as medical, financial or legal advice.',
        style: GoogleFonts.outfit(
          fontSize: 11,
          color: subTextColor,
          fontStyle: FontStyle.italic,
          height: 1.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reading header card (used in comparison screen)
// ─────────────────────────────────────────────────────────────────────────────
class _ReadingHeaderCard extends StatelessWidget {
  final String label;
  final Map<String, dynamic> reading;
  final bool isHindi;
  final bool isDark;
  final Color textColor;
  final Color subTextColor;
  final Color accentColor;

  const _ReadingHeaderCard({
    required this.label,
    required this.reading,
    required this.isHindi,
    required this.isDark,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt = reading['created_at'] != null
        ? DateTime.tryParse(reading['created_at'] as String)
        : null;
    final title =
        reading['title'] as String? ??
        (isHindi ? 'हस्तरेखा पठन' : 'Palm Reading');
    final meta = reading['metadata'] as Map<String, dynamic>? ?? {};
    final confidence = meta['confidence_score'] as num?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '${createdAt.day}/${createdAt.month}/${createdAt.year}',
              style: GoogleFonts.outfit(fontSize: 11, color: subTextColor),
            ),
          ],
          if (confidence != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 12, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  '${confidence.round()}%',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comparison field data model
// ─────────────────────────────────────────────────────────────────────────────
class _ComparisonField {
  final String labelEn;
  final String labelHi;
  final String textA;
  final String textB;
  final ChangeType changeType;

  const _ComparisonField({
    required this.labelEn,
    required this.labelHi,
    required this.textA,
    required this.textB,
    required this.changeType,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Comparison field card
// ─────────────────────────────────────────────────────────────────────────────
class _ComparisonFieldCard extends StatelessWidget {
  final _ComparisonField field;
  final bool isHindi;
  final bool isDark;
  final Color textColor;
  final Color subTextColor;

  const _ComparisonFieldCard({
    required this.field,
    required this.isHindi,
    required this.isDark,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final borderColor = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final ct = field.changeType;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isHindi ? field.labelHi : field.labelEn,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ct.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ct.color.withAlpha(60)),
                  ),
                  child: Text(
                    ct.label(isHindi),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ct.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppTheme.outlineDark : AppTheme.outlineLight,
          ),
          // Side-by-side or stacked
          LayoutBuilder(
            builder: (context, constraints) {
              final useRow = constraints.maxWidth > 340;
              if (useRow) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _FieldSide(
                          label: isHindi ? 'पठन A' : 'Reading A',
                          text: field.textA,
                          accentColor: AppTheme.primary,
                          textColor: textColor,
                          subTextColor: subTextColor,
                          isDark: isDark,
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: isDark
                            ? AppTheme.outlineDark
                            : AppTheme.outlineLight,
                      ),
                      Expanded(
                        child: _FieldSide(
                          label: isHindi ? 'पठन B' : 'Reading B',
                          text: field.textB,
                          accentColor: AppTheme.cyan,
                          textColor: textColor,
                          subTextColor: subTextColor,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Column(
                  children: [
                    _FieldSide(
                      label: isHindi ? 'पठन A' : 'Reading A',
                      text: field.textA,
                      accentColor: AppTheme.primary,
                      textColor: textColor,
                      subTextColor: subTextColor,
                      isDark: isDark,
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? AppTheme.outlineDark
                          : AppTheme.outlineLight,
                    ),
                    _FieldSide(
                      label: isHindi ? 'पठन B' : 'Reading B',
                      text: field.textB,
                      accentColor: AppTheme.cyan,
                      textColor: textColor,
                      subTextColor: subTextColor,
                      isDark: isDark,
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FieldSide extends StatelessWidget {
  final String label;
  final String text;
  final Color accentColor;
  final Color textColor;
  final Color subTextColor;
  final bool isDark;

  const _FieldSide({
    required this.label,
    required this.text,
    required this.accentColor,
    required this.textColor,
    required this.subTextColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 4),
          text.isEmpty
              ? Text(
                  '—',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: subTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Text(
                  text,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: textColor,
                    height: 1.5,
                  ),
                ),
        ],
      ),
    );
  }
}
