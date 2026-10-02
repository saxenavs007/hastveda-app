// HastVeda Admin Reviews Dashboard
// Admin-only screen to view, manage, and analyze user reviews.
// Access: Only users with role=admin in auth metadata.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class AdminReviewsDashboard extends StatefulWidget {
  const AdminReviewsDashboard({super.key});

  @override
  State<AdminReviewsDashboard> createState() => _AdminReviewsDashboardState();
}

class _AdminReviewsDashboardState extends State<AdminReviewsDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _error;

  // Analytics
  int _totalReviews = 0;
  double _avgRating = 0;
  Map<int, int> _ratingBreakdown = {};
  Map<String, int> _featureBreakdown = {};
  Map<String, int> _recommendBreakdown = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReviews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('user_reviews')
          .select('*, user_profiles:user_id(full_name, email)')
          .order('created_at', ascending: false);

      final reviews = List<Map<String, dynamic>>.from(data as List);

      // Compute analytics
      _totalReviews = reviews.length;
      _ratingBreakdown = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      _featureBreakdown = {};
      _recommendBreakdown = {};
      double ratingSum = 0;

      for (final r in reviews) {
        final rating = (r['rating'] as num?)?.toInt() ?? 0;
        if (rating >= 1 && rating <= 5) {
          _ratingBreakdown[rating] = (_ratingBreakdown[rating] ?? 0) + 1;
          ratingSum += rating;
        }
        final feature = r['feature_context'] as String? ?? 'overall_app';
        _featureBreakdown[feature] = (_featureBreakdown[feature] ?? 0) + 1;
        final rec = r['recommend_hastveda'] as String?;
        if (rec != null) {
          _recommendBreakdown[rec] = (_recommendBreakdown[rec] ?? 0) + 1;
        }
      }
      _avgRating = _totalReviews > 0 ? ratingSum / _totalReviews : 0;

      setState(() {
        _reviews = reviews;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load reviews: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(String reviewId, String status) async {
    try {
      await Supabase.instance.client
          .from('user_reviews')
          .update({'review_status': status})
          .eq('id', reviewId);
      await _loadReviews();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $status'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A06),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0A06),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: Colors.white70,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reviews & Feedback',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadReviews,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Reviews'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: GoogleFonts.outfit(color: Colors.red.shade400),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [_buildReviewsList(), _buildAnalytics()],
            ),
    );
  }

  Widget _buildReviewsList() {
    if (_reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⭐', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No reviews yet',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reviews.length,
      itemBuilder: (context, i) =>
          _ReviewCard(review: _reviews[i], onStatusChange: _updateStatus),
    );
  }

  Widget _buildAnalytics() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Total Reviews',
                  value: '$_totalReviews',
                  icon: '📝',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Avg Rating',
                  value: _avgRating.toStringAsFixed(1),
                  icon: '⭐',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Rating breakdown
          _SectionTitle('Rating Breakdown'),
          const SizedBox(height: 12),
          ...List.generate(5, (i) {
            final star = 5 - i;
            final count = _ratingBreakdown[star] ?? 0;
            final pct = _totalReviews > 0 ? count / _totalReviews : 0.0;
            return _RatingBar(star: star, count: count, pct: pct);
          }),
          const SizedBox(height: 20),

          // Feature breakdown
          _SectionTitle('Reviews by Feature'),
          const SizedBox(height: 12),
          ..._featureBreakdown.entries.map(
            (e) => _FeatureRow(
              feature: _featureLabel(e.key),
              count: e.value,
              total: _totalReviews,
            ),
          ),
          const SizedBox(height: 20),

          // Recommendation breakdown
          if (_recommendBreakdown.isNotEmpty) ...[
            _SectionTitle('Recommendation Breakdown'),
            const SizedBox(height: 12),
            ..._recommendBreakdown.entries.map(
              (e) => _FeatureRow(
                feature: e.key == 'yes'
                    ? 'Would Recommend'
                    : e.key == 'maybe'
                    ? 'Maybe'
                    : 'Would Not Recommend',
                count: e.value,
                total: _recommendBreakdown.values.fold(0, (a, b) => a + b),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _featureLabel(String ctx) {
    switch (ctx) {
      case 'palm_analysis':
        return 'Palm Analysis';
      case 'detailed_report':
        return 'Detailed Report';
      case 'predictions':
        return 'Predictions';
      case 'ask_hastveda':
        return 'Ask HastVeda';
      default:
        return 'Overall App';
    }
  }
}

// ── Review Card ───────────────────────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final Future<void> Function(String id, String status) onStatusChange;

  const _ReviewCard({required this.review, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final text = review['review_text'] as String?;
    final feature = review['feature_context'] as String? ?? 'overall_app';
    final status = review['review_status'] as String? ?? 'new';
    final recommend = review['recommend_hastveda'] as String?;
    final improvement = review['improvement_category'] as String?;
    final marketingConsent = review['marketing_consent'] as bool? ?? false;
    final publicConsent = review['public_display_consent'] as bool? ?? false;
    final createdAt = review['created_at'] as String?;
    final userProfile = review['user_profiles'] as Map<String, dynamic>?;
    final userName = userProfile?['full_name'] as String? ?? 'Unknown';

    final dateStr = createdAt != null
        ? DateTime.tryParse(createdAt)?.toLocal().toString().split('.').first ??
              createdAt
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    rating > i
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: rating > i
                        ? const Color(0xFFF59E0B)
                        : Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: status),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
                color: const Color(0xFF2A1A0A),
                onSelected: (s) => onStatusChange(review['id'] as String, s),
                itemBuilder: (_) => ['new', 'reviewed', 'featured', 'archived']
                    .map(
                      (s) => PopupMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            userName,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            dateStr,
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Feature', value: _featureLabel(feature)),
          if (recommend != null) _InfoRow(label: 'Recommend', value: recommend),
          if (improvement != null)
            _InfoRow(label: 'Improve', value: improvement),
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"$text"',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.white70,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _ConsentBadge(label: 'Marketing', granted: marketingConsent),
              const SizedBox(width: 8),
              _ConsentBadge(label: 'Public', granted: publicConsent),
            ],
          ),
        ],
      ),
    );
  }

  String _featureLabel(String ctx) {
    switch (ctx) {
      case 'palm_analysis':
        return 'Palm Analysis';
      case 'detailed_report':
        return 'Detailed Report';
      case 'predictions':
        return 'Predictions';
      case 'ask_hastveda':
        return 'Ask HastVeda';
      default:
        return 'Overall App';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: Colors.white60,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'featured':
        color = const Color(0xFFF59E0B);
        break;
      case 'reviewed':
        color = AppTheme.success;
        break;
      case 'archived':
        color = Colors.white38;
        break;
      default:
        color = AppTheme.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        status,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ConsentBadge extends StatelessWidget {
  final String label;
  final bool granted;
  const _ConsentBadge({required this.label, required this.granted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: granted
            ? AppTheme.success.withAlpha(20)
            : Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${granted ? "✓" : "✗"} $label',
        style: GoogleFonts.outfit(
          fontSize: 10,
          color: granted ? AppTheme.success : Colors.white38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Analytics Widgets ─────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  final int star;
  final int count;
  final double pct;
  const _RatingBar({
    required this.star,
    required this.count,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$star ⭐',
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white.withAlpha(15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primary,
                ),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text(
              '$count',
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.white54),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String feature;
  final int count;
  final int total;
  const _FeatureRow({
    required this.feature,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  feature,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ),
              Text(
                '$count (${(pct * 100).toStringAsFixed(0)}%)',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withAlpha(15),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
