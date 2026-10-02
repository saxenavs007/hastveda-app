import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

/// Admin Discount Code Dashboard
/// Access: Only users with role=admin in auth metadata
class AdminDiscountDashboard extends StatefulWidget {
  const AdminDiscountDashboard({super.key});

  @override
  State<AdminDiscountDashboard> createState() => _AdminDiscountDashboardState();
}

class _AdminDiscountDashboardState extends State<AdminDiscountDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _codes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCodes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('discount_codes')
          .select('*, user_profiles:assigned_user_id(full_name, email)')
          .order('created_at', ascending: false);
      setState(() {
        _codes = List<Map<String, dynamic>>.from(data as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load codes: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _disableCode(String codeId) async {
    try {
      await Supabase.instance.client
          .from('discount_codes')
          .update({'is_active': false})
          .eq('id', codeId);
      await _loadCodes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code disabled'),
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

  Future<void> _deleteCode(String codeId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A0E06),
        title: Text(
          'Delete Code?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This action cannot be undone.',
          style: GoogleFonts.outfit(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('discount_codes')
          .delete()
          .eq('id', codeId);
      await _loadCodes();
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

  void _showGenerateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GenerateCodeSheet(onGenerated: _loadCodes),
    );
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
          'Discount Codes',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadCodes,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _showGenerateSheet,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                'Generate',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
            ),
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
            Tab(text: 'Active Codes'),
            Tab(text: 'All Codes'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: GoogleFonts.outfit(color: Colors.red.shade400),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCodeList(
                  _codes.where((c) => c['is_active'] == true).toList(),
                ),
                _buildCodeList(_codes),
              ],
            ),
    );
  }

  Widget _buildCodeList(List<Map<String, dynamic>> codes) {
    if (codes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎟️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No codes yet',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap Generate to create a new discount code',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCodes,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: codes.length,
        itemBuilder: (context, index) {
          final code = codes[index];
          return _CodeCard(
            code: code,
            onDisable: () => _disableCode(code['id'] as String),
            onDelete: () => _deleteCode(code['id'] as String),
          );
        },
      ),
    );
  }
}

// ── Code Card ─────────────────────────────────────────────────

class _CodeCard extends StatelessWidget {
  final Map<String, dynamic> code;
  final VoidCallback onDisable;
  final VoidCallback onDelete;

  const _CodeCard({
    required this.code,
    required this.onDisable,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = code['is_active'] as bool? ?? false;
    final discountType = code['discount_type'] as String? ?? 'fixed_amount';
    final discountValue = (code['discount_value'] as num?)?.toDouble() ?? 0;
    final usedCount = (code['used_count'] as num?)?.toInt() ?? 0;
    final maxRedemptions = (code['max_redemptions'] as num?)?.toInt() ?? 1;
    final expiresAt = code['expires_at'] as String?;
    final campaign = code['campaign'] as String?;
    final assignedUser = code['user_profiles'] as Map<String, dynamic>?;

    final discountLabel = discountType == 'percentage'
        ? '${discountValue.toStringAsFixed(0)}% off'
        : '₹${discountValue.toStringAsFixed(0)} off';

    final isExpired =
        expiresAt != null &&
        DateTime.tryParse(expiresAt)?.isBefore(DateTime.now()) == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive && !isExpired
              ? AppTheme.primary.withAlpha(60)
              : Colors.white.withAlpha(12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        code['code'] as String? ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: code['code'] as String? ?? ''),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code copied'),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  isActive: isActive,
                  isExpired: isExpired,
                  usedCount: usedCount,
                  maxRedemptions: maxRedemptions,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Discount info
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(icon: Icons.discount_outlined, label: discountLabel),
                _InfoChip(
                  icon: Icons.repeat_rounded,
                  label: '$usedCount / $maxRedemptions used',
                ),
                if (expiresAt != null)
                  _InfoChip(
                    icon: Icons.schedule_rounded,
                    label: isExpired
                        ? 'Expired'
                        : 'Expires ${_formatDate(expiresAt)}',
                    color: isExpired ? Colors.red.shade400 : null,
                  ),
                if (campaign != null)
                  _InfoChip(icon: Icons.campaign_outlined, label: campaign),
                if (assignedUser != null)
                  _InfoChip(
                    icon: Icons.person_outline_rounded,
                    label:
                        assignedUser['full_name'] as String? ??
                        assignedUser['email'] as String? ??
                        'Assigned',
                    color: Colors.amber.shade400,
                  ),
              ],
            ),
            if (code['admin_note'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Note: ${code['admin_note']}',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white38),
              ),
            ],
            const SizedBox(height: 12),
            // Actions
            Row(
              children: [
                if (isActive)
                  _ActionButton(
                    label: 'Disable',
                    icon: Icons.block_rounded,
                    color: Colors.orange,
                    onTap: onDisable,
                  ),
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  color: Colors.red,
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  final bool isExpired;
  final int usedCount;
  final int maxRedemptions;

  const _StatusBadge({
    required this.isActive,
    required this.isExpired,
    required this.usedCount,
    required this.maxRedemptions,
  });

  @override
  Widget build(BuildContext context) {
    final isExhausted = usedCount >= maxRedemptions;
    final Color color;
    final String label;

    if (!isActive) {
      color = Colors.grey;
      label = 'Disabled';
    } else if (isExpired) {
      color = Colors.red;
      label = 'Expired';
    } else if (isExhausted) {
      color = Colors.orange;
      label = 'Exhausted';
    } else {
      color = Colors.green;
      label = 'Active';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white54;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.outfit(fontSize: 12, color: c)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Generate Code Bottom Sheet ────────────────────────────────

class _GenerateCodeSheet extends StatefulWidget {
  final VoidCallback onGenerated;

  const _GenerateCodeSheet({required this.onGenerated});

  @override
  State<_GenerateCodeSheet> createState() => _GenerateCodeSheetState();
}

class _GenerateCodeSheetState extends State<_GenerateCodeSheet> {
  String _discountType = 'fixed_amount';
  final _valueController = TextEditingController(text: '50');
  final _maxRedemptionsController = TextEditingController(text: '1');
  final _maxPerCustomerController = TextEditingController(text: '1');
  final _campaignController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _expiryDate;
  bool _isLoading = false;
  String _generatedCode = '';

  @override
  void initState() {
    super.initState();
    _generatedCode = _generateCode();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _maxRedemptionsController.dispose();
    _maxPerCustomerController.dispose();
    _campaignController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final part1 = List.generate(
      2,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    final part2 = List.generate(
      6,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    return 'HV-$part1$part2';
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _saveCode() async {
    final value = double.tryParse(_valueController.text);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid discount value')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('discount_codes').insert({
        'code': _generatedCode,
        'discount_type': _discountType,
        'discount_value': value,
        'applicable_product': 'hastveda_premium',
        'max_redemptions': int.tryParse(_maxRedemptionsController.text) ?? 1,
        'max_per_customer': int.tryParse(_maxPerCustomerController.text) ?? 1,
        'campaign': _campaignController.text.trim().isNotEmpty
            ? _campaignController.text.trim()
            : null,
        'admin_note': _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        'is_active': true,
        'expires_at': _expiryDate?.toIso8601String(),
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });

      widget.onGenerated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code $_generatedCode created!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade800,
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A0E06),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Generate Discount Code',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Generated code display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0A06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withAlpha(80)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _generatedCode,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white54,
                    ),
                    onPressed: () =>
                        setState(() => _generatedCode = _generateCode()),
                    tooltip: 'Regenerate',
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white54),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _generatedCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Discount type
            Text(
              'Discount Type',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.white60),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TypeButton(
                    label: 'Fixed Amount (₹)',
                    isSelected: _discountType == 'fixed_amount',
                    onTap: () => setState(() => _discountType = 'fixed_amount'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeButton(
                    label: 'Percentage (%)',
                    isSelected: _discountType == 'percentage',
                    onTap: () => setState(() => _discountType = 'percentage'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Discount value
            _FormField(
              label: _discountType == 'percentage'
                  ? 'Discount %'
                  : 'Discount Amount (₹)',
              controller: _valueController,
              keyboardType: TextInputType.number,
              hint: _discountType == 'percentage' ? 'e.g. 20' : 'e.g. 50',
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _FormField(
                    label: 'Max Total Uses',
                    controller: _maxRedemptionsController,
                    keyboardType: TextInputType.number,
                    hint: '1',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormField(
                    label: 'Max Per Customer',
                    controller: _maxPerCustomerController,
                    keyboardType: TextInputType.number,
                    hint: '1',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Expiry date
            GestureDetector(
              onTap: _pickExpiry,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0A06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _expiryDate == null
                          ? 'No expiry date (optional)'
                          : 'Expires: ${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: _expiryDate == null
                            ? Colors.white38
                            : Colors.white70,
                      ),
                    ),
                    if (_expiryDate != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _expiryDate = null),
                        child: const Icon(
                          Icons.clear,
                          size: 16,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            _FormField(
              label: 'Campaign / Source (optional)',
              controller: _campaignController,
              hint: 'e.g. launch_offer, influencer_xyz',
            ),
            const SizedBox(height: 12),

            _FormField(
              label: 'Admin Note (optional)',
              controller: _noteController,
              hint: 'Internal note for this code',
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Create Code',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(30)
              : const Color(0xFF0F0A06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white.withAlpha(20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppTheme.primary : Colors.white54,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final String hint;

  const _FormField({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 13, color: Colors.white60),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.outfit(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(fontSize: 13, color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF0F0A06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}
