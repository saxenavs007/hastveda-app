import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/entitlement_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_lock_widget.dart';

/// Generic Palm Line Detail Screen — reused for all 6 lines
class PalmLineScreen extends StatefulWidget {
  final String lineKey; // 'heart', 'head', 'life', 'fate', 'sun', 'mercury'
  final String locale;
  final Map<String, dynamic>? lineData;

  const PalmLineScreen({
    super.key,
    required this.lineKey,
    this.locale = 'en',
    this.lineData,
  });

  @override
  State<PalmLineScreen> createState() => _PalmLineScreenState();
}

class _PalmLineScreenState extends State<PalmLineScreen> {
  Map<String, dynamic>? _loadedLineData;
  bool _isLoading = false;

  bool get _isHindi => widget.locale == 'hi';

  _LineConfig get _config =>
      _lineConfigs[widget.lineKey] ?? _lineConfigs['heart']!;

  static const Map<String, _LineConfig> _lineConfigs = {
    'heart': _LineConfig(
      emoji: '❤️',
      titleEn: 'Heart Line',
      titleHi: 'हृदय रेखा',
      descEn:
          'The Heart Line traditionally reflects emotional health, romantic tendencies, and the depth of your feelings. A deep, clear line may suggest strong emotional expression.',
      descHi:
          'हृदय रेखा पारंपरिक रूप से भावनात्मक स्वास्थ्य, प्रेम प्रवृत्तियों और आपकी भावनाओं की गहराई को दर्शाती है।',
      dbSection: 'love_analysis',
      summaryKeyEn: 'summary_en',
      summaryKeyHi: 'summary_hi',
      feature: PremiumFeatures.palmLines,
    ),
    'head': _LineConfig(
      emoji: '🧠',
      titleEn: 'Head Line',
      titleHi: 'मस्तिष्क रेखा',
      descEn:
          'The Head Line traditionally indicates intellectual capacity, thinking style, and mental approach to life. This pattern may suggest analytical and creative thinking tendencies.',
      descHi:
          'मस्तिष्क रेखा बौद्धिक क्षमता, सोचने की शैली और जीवन के प्रति मानसिक दृष्टिकोण को दर्शाती है।',
      dbSection: 'personality_analysis',
      summaryKeyEn: 'summary_en',
      summaryKeyHi: 'summary_hi',
      feature: PremiumFeatures.palmLines,
    ),
    'life': _LineConfig(
      emoji: '✋',
      titleEn: 'Life Line',
      titleHi: 'जीवन रेखा',
      descEn:
          'The Life Line traditionally reflects vitality, life energy, and major life changes. Contrary to popular belief, its length does not indicate lifespan — rather the quality of life energy.',
      descHi:
          'जीवन रेखा जीवन शक्ति, जीवन ऊर्जा और प्रमुख जीवन परिवर्तनों को दर्शाती है। इसकी लंबाई आयु नहीं, बल्कि जीवन ऊर्जा की गुणवत्ता दर्शाती है।',
      dbSection: 'life_analysis',
      summaryKeyEn: 'summary_en',
      summaryKeyHi: 'summary_hi',
      feature: PremiumFeatures.palmLines,
    ),
    'fate': _LineConfig(
      emoji: '🌟',
      titleEn: 'Fate Line',
      titleHi: 'भाग्य रेखा',
      descEn:
          'The Fate Line traditionally suggests career direction, life path, and external influences on your destiny. This pattern may indicate strong career focus and determination.',
      descHi: 'भाग्य रेखा करियर दिशा और जीवन पथ को दर्शाती है।',
      dbSection: 'career_analysis',
      summaryKeyEn: 'interpretation_en',
      summaryKeyHi: 'interpretation_hi',
      feature: PremiumFeatures.careerBusiness,
    ),
    'sun': _LineConfig(
      emoji: '☀️',
      titleEn: 'Sun / Success Line',
      titleHi: 'सूर्य रेखा',
      descEn:
          'The Sun Line traditionally indicates potential for success, recognition, and creative achievement. This pattern may suggest artistic or public recognition tendencies.',
      descHi: 'सूर्य रेखा सफलता और प्रसिद्धि की संभावना को दर्शाती है।',
      dbSection: null,
      summaryKeyEn: null,
      summaryKeyHi: null,
      feature: PremiumFeatures.sunLine,
    ),
    'mercury': _LineConfig(
      emoji: '💬',
      titleEn: 'Mercury Line',
      titleHi: 'बुध रेखा',
      descEn:
          'The Mercury Line traditionally reflects communication ability, business acumen, and health tendencies. This pattern may suggest strong verbal and analytical skills.',
      descHi: 'बुध रेखा संचार क्षमता और व्यापारिक कौशल को दर्शाती है।',
      dbSection: null,
      summaryKeyEn: null,
      summaryKeyHi: null,
      feature: PremiumFeatures.mercuryLine,
    ),
  };

  @override
  void initState() {
    super.initState();
    // If lineData was passed directly, use it; otherwise load from DB
    if (widget.lineData == null && _config.dbSection != null) {
      _loadFromDb();
    }
  }

  Future<void> _loadFromDb() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final data = await SupabaseService.instance.client
          .from('palm_analysis')
          .select()
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data != null && mounted) {
        final section = data[_config.dbSection!] as Map<String, dynamic>?;
        setState(() {
          _loadedLineData = section;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('PalmLineScreen load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? get _effectiveLineData =>
      widget.lineData ?? _loadedLineData;

  /// Returns the personalized description for this line from the DB data,
  /// falling back to the static config description if not available.
  String _getDescription() {
    final data = _effectiveLineData;
    if (data == null) {
      return _isHindi ? _config.descHi : _config.descEn;
    }

    if (_isHindi) {
      final keyHi = _config.summaryKeyHi;
      if (keyHi != null) {
        final val = data[keyHi] as String?;
        if (val != null && val.isNotEmpty) return val;
      }
      // Try interpretation_hi as fallback
      final interpHi = data['interpretation_hi'] as String?;
      if (interpHi != null && interpHi.isNotEmpty) return interpHi;
      return _config.descHi;
    } else {
      final keyEn = _config.summaryKeyEn;
      if (keyEn != null) {
        final val = data[keyEn] as String?;
        if (val != null && val.isNotEmpty) return val;
      }
      final interpEn = data['interpretation_en'] as String?;
      if (interpEn != null && interpEn.isNotEmpty) return interpEn;
      return _config.descEn;
    }
  }

  int _getScore() {
    final data = _effectiveLineData;
    if (data == null) return 75;
    return (data['score'] as num?)?.toInt() ?? 75;
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        foregroundColor: AppTheme.textPrimary,
        title: Text(
          _isHindi ? config.titleHi : config.titleEn,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: Colors.white,
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
          : _gated(
              config,
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Score card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2A1200), Color(0xFF1A0A00)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(60),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            config.emoji,
                            style: const TextStyle(fontSize: 48),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isHindi ? config.titleHi : config.titleEn,
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: _getScore() / 100,
                                  backgroundColor: Colors.white12,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        AppTheme.primary,
                                      ),
                                  borderRadius: BorderRadius.circular(4),
                                  minHeight: 8,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_getScore()} / 100',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Description
                    Text(
                      _isHindi ? 'व्याख्या' : 'Interpretation',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1208),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF3A2A18)),
                      ),
                      child: Text(
                        _getDescription(),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Disclaimer
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1208),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(40),
                        ),
                      ),
                      child: Text(
                        _isHindi
                            ? '⚠️ यह हस्तरेखा की पारंपरिक व्याख्या है। यह वैज्ञानिक तथ्य नहीं है।'
                            : '⚠️ This is a traditional palmistry interpretation. It is not scientific fact and should not be used for medical, financial, or life decisions.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF8B7355),
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Back to analysis
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isHindi ? 'वापस जाएं' : 'Back to Analysis',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  /// Premium lines (Fate / Sun / Mercury) render behind the entitlement gate.
  /// Free lines (Heart / Head / Life) render directly. Tiering comes from
  /// [PremiumFeatures] only — never from a local bool.
  Widget _gated(_LineConfig config, Widget child) {
    if (PremiumFeatures.isFree(config.feature)) return child;
    return EntitlementGate(
      feature: config.feature,
      locale: widget.locale,
      fullPage: true,
      child: child,
    );
  }
}

class _LineConfig {
  final String emoji;
  final String titleEn;
  final String titleHi;
  final String descEn;
  final String descHi;

  /// The palm_analysis DB column to load data from (e.g. 'love_analysis').
  final String? dbSection;

  /// Key within the DB section for the English summary.
  final String? summaryKeyEn;

  /// Key within the DB section for the Hindi summary.
  final String? summaryKeyHi;

  /// Feature key from [PremiumFeatures] — decides whether this line is gated.
  final String feature;

  const _LineConfig({
    required this.emoji,
    required this.titleEn,
    required this.titleHi,
    required this.descEn,
    required this.descHi,
    required this.dbSection,
    required this.summaryKeyEn,
    required this.summaryKeyHi,
    required this.feature,
  });
}
