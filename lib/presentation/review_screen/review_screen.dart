// HastVeda Review & Feedback Screen
// Shows after a meaningful completed Premium experience.
// Collects 1-5 star rating, optional text, feature context,
// recommendation/improvement follow-up, and consent checkboxes.
// Implements frequency control via shared_preferences.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

// ── Feature context constants ─────────────────────────────────────────────────
class ReviewFeatureContext {
  static const String palmAnalysis = 'palm_analysis';
  static const String detailedReport = 'detailed_report';
  static const String predictions = 'predictions';
  static const String askHastveda = 'ask_hastveda';
  static const String overallApp = 'overall_app';
}

// ── Frequency control helper ──────────────────────────────────────────────────
class ReviewFrequencyControl {
  static const String _lastPromptKey = 'review_last_prompt_ts';
  static const String _promptCountKey = 'review_prompt_count';
  static const int _minDaysBetweenPrompts = 7;

  /// Returns true if we should show the review prompt.
  static Future<bool> shouldShowPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getInt(_lastPromptKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceLast = (now - lastTs) / (1000 * 60 * 60 * 24);
      return daysSinceLast >= _minDaysBetweenPrompts;
    } catch (_) {
      return true;
    }
  }

  /// Records that the prompt was shown.
  static Future<void> recordPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPromptKey, DateTime.now().millisecondsSinceEpoch);
      final count = (prefs.getInt(_promptCountKey) ?? 0) + 1;
      await prefs.setInt(_promptCountKey, count);
    } catch (_) {}
  }
}

// ── Show review dialog helper ─────────────────────────────────────────────────
Future<void> showReviewDialogIfAppropriate({
  required BuildContext context,
  required String featureContext,
  bool forceShow = false,
}) async {
  if (!forceShow) {
    final should = await ReviewFrequencyControl.shouldShowPrompt();
    if (!should) return;
  }

  // Check if user is authenticated
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;

  await ReviewFrequencyControl.recordPromptShown();

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        ReviewBottomSheet(featureContext: featureContext, userId: user.id),
  );
}

// ── Review Bottom Sheet ───────────────────────────────────────────────────────
class ReviewBottomSheet extends StatefulWidget {
  final String featureContext;
  final String userId;

  const ReviewBottomSheet({
    super.key,
    required this.featureContext,
    required this.userId,
  });

  @override
  State<ReviewBottomSheet> createState() => _ReviewBottomSheetState();
}

class _ReviewBottomSheetState extends State<ReviewBottomSheet> {
  int _rating = 0;
  final TextEditingController _reviewController = TextEditingController();
  String? _recommendation;
  String? _improvementCategory;
  bool _marketingConsent = false;
  bool _publicDisplayConsent = false;
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _error;

  // Step: 0 = rating, 1 = follow-up, 2 = text + consent, 3 = done
  int _step = 0;

  bool get _isPositive => _rating >= 4;
  bool get _isNegative => _rating <= 3 && _rating > 0;

  final List<String> _improvementCategories = [
    'Palm Analysis',
    'Detailed Report',
    'Predictions',
    'Ask HastVeda',
    'App Experience',
    'Payment',
    'Other',
  ];

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_rating == 0) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Upsert — one review per user per feature context
      await Supabase.instance.client.from('user_reviews').upsert({
        'user_id': widget.userId,
        'rating': _rating,
        'review_text': _reviewController.text.trim().isEmpty
            ? null
            : _reviewController.text.trim(),
        'feature_context': widget.featureContext,
        'recommend_hastveda': _recommendation,
        'improvement_category': _improvementCategory,
        'marketing_consent': _marketingConsent,
        'public_display_consent': _publicDisplayConsent,
        'review_status': 'new',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,feature_context');

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitted = true;
          _step = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Could not submit review. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A0E06) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1410);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF8B7355);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_step == 3) ...[
              _buildThankYouStep(textPrimary, textSecondary),
            ] else if (_step == 0) ...[
              _buildRatingStep(textPrimary, textSecondary, isDark),
            ] else if (_step == 1) ...[
              _buildFollowUpStep(textPrimary, textSecondary, isDark),
            ] else if (_step == 2) ...[
              _buildTextConsentStep(textPrimary, textSecondary, isDark),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.error),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingStep(Color textPrimary, Color textSecondary, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How was your HastVeda experience?',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _featureLabel(widget.featureContext),
          style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.primary),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final star = i + 1;
            return GestureDetector(
              onTap: () => setState(() => _rating = star),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  _rating >= star
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 44,
                  color: _rating >= star
                      ? const Color(0xFFF59E0B)
                      : (isDark ? Colors.white24 : Colors.black26),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _ratingLabel(_rating),
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Not Now',
                  style: GoogleFonts.outfit(color: textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _rating == 0
                    ? null
                    : () => setState(() => _step = 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFollowUpStep(
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(
            5,
            (i) => Icon(
              _rating > i ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 20,
              color: _rating > i ? const Color(0xFFF59E0B) : Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_isPositive) ...[
          Text(
            'Would you recommend HastVeda to others?',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...['yes', 'maybe', 'no'].map(
            (opt) => _RecommendTile(
              label: opt == 'yes'
                  ? 'Yes, definitely!'
                  : opt == 'maybe'
                  ? 'Maybe'
                  : 'No',
              value: opt,
              selected: _recommendation == opt,
              isDark: isDark,
              onTap: () => setState(() => _recommendation = opt),
            ),
          ),
        ] else ...[
          Text(
            'What could we improve?',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _improvementCategories
                .map(
                  (cat) => GestureDetector(
                    onTap: () => setState(() => _improvementCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _improvementCategory == cat
                            ? AppTheme.primary
                            : (isDark
                                  ? Colors.white.withAlpha(15)
                                  : const Color(0xFFF5EFE8)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _improvementCategory == cat
                              ? AppTheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _improvementCategory == cat
                              ? Colors.white
                              : (isDark
                                    ? Colors.white70
                                    : const Color(0xFF8C4F10)),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _step = 0),
                child: Text(
                  'Back',
                  style: GoogleFonts.outfit(color: textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => setState(() => _step = 2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextConsentStep(
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tell us what you liked or how we can improve.',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional',
          style: GoogleFonts.outfit(fontSize: 12, color: textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reviewController,
          maxLines: 4,
          maxLength: 500,
          style: GoogleFonts.outfit(fontSize: 14, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Share your thoughts...',
            hintStyle: GoogleFonts.outfit(color: textSecondary),
            filled: true,
            fillColor: isDark
                ? Colors.white.withAlpha(10)
                : const Color(0xFFF5EFE8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            counterStyle: GoogleFonts.outfit(
              fontSize: 11,
              color: textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Marketing consent
        _ConsentCheckbox(
          value: _marketingConsent,
          label:
              'I agree that HastVeda may use my review/testimonial for promotional purposes.',
          isDark: isDark,
          onChanged: (v) => setState(() => _marketingConsent = v ?? false),
        ),
        const SizedBox(height: 10),
        // Public display consent
        _ConsentCheckbox(
          value: _publicDisplayConsent,
          label:
              'I agree that my review may be displayed publicly (without my personal contact details).',
          isDark: isDark,
          onChanged: (v) => setState(() => _publicDisplayConsent = v ?? false),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _step = 1),
                child: Text(
                  'Back',
                  style: GoogleFonts.outfit(color: textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Submit Review',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThankYouStep(Color textPrimary, Color textSecondary) {
    return Column(
      children: [
        const Center(child: Text('🙏', style: TextStyle(fontSize: 56))),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Thank You!',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Your feedback helps us improve HastVeda for everyone.',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: Text(
              'Done',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  String _featureLabel(String ctx) {
    switch (ctx) {
      case ReviewFeatureContext.palmAnalysis:
        return 'Palm Analysis';
      case ReviewFeatureContext.detailedReport:
        return 'Detailed Report';
      case ReviewFeatureContext.predictions:
        return 'Predictions';
      case ReviewFeatureContext.askHastveda:
        return 'Ask HastVeda';
      default:
        return 'HastVeda App';
    }
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent!';
      default:
        return 'Tap a star to rate';
    }
  }
}

// ── Recommend Tile ────────────────────────────────────────────────────────────
class _RecommendTile extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _RecommendTile({
    required this.label,
    required this.value,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(20)
              : (isDark ? Colors.white.withAlpha(10) : const Color(0xFFF5EFE8)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected
                  ? AppTheme.primary
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppTheme.primary
                    : (isDark ? Colors.white : const Color(0xFF1A1410)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Consent Checkbox ──────────────────────────────────────────────────────────
class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final String label;
  final bool isDark;
  final ValueChanged<bool?> onChanged;

  const _ConsentCheckbox({
    required this.value,
    required this.label,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : const Color(0xFF8B7355),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
