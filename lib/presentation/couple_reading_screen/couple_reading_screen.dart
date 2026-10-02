// HastVeda Couple Reading Screen
// Real Gemini pipeline: uploads both palm images → Edge Function analyzes each
// separately → compatibility interpretation → result screen.
// No mock data. All AI calls are server-side via Supabase Edge Function.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/connectivity_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/entitlement_service.dart';
import '../../services/error_logger.dart';
import '../../services/locale_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_lock_widget.dart';

// ── Analysis stage for couple reading ────────────────────────────────────────
enum _CoupleStage {
  idle,
  uploadingPerson1,
  analyzingPerson1,
  uploadingPerson2,
  analyzingPerson2,
  generatingCompatibility,
  complete,
  failed,
}

extension _CoupleStageExt on _CoupleStage {
  String label(bool isHindi) {
    switch (this) {
      case _CoupleStage.uploadingPerson1:
        return isHindi
            ? 'व्यक्ति १ की छवि अपलोड हो रही है...'
            : 'Uploading Person 1 image...';
      case _CoupleStage.analyzingPerson1:
        return isHindi
            ? 'व्यक्ति १ की हथेली का विश्लेषण हो रहा है...'
            : 'Analyzing Person 1\'s palm...';
      case _CoupleStage.uploadingPerson2:
        return isHindi
            ? 'व्यक्ति २ की छवि अपलोड हो रही है...'
            : 'Uploading Person 2 image...';
      case _CoupleStage.analyzingPerson2:
        return isHindi
            ? 'व्यक्ति २ की हथेली का विश्लेषण हो रहा है...'
            : 'Analyzing Person 2\'s palm...';
      case _CoupleStage.generatingCompatibility:
        return isHindi
            ? 'अनुकूलता रिपोर्ट तैयार हो रही है...'
            : 'Generating compatibility report...';
      case _CoupleStage.complete:
        return isHindi ? 'पठन तैयार है!' : 'Reading ready!';
      default:
        return isHindi ? 'प्रक्रिया हो रही है...' : 'Processing...';
    }
  }
}

class CoupleReadingScreen extends StatefulWidget {
  final String locale;

  const CoupleReadingScreen({super.key, this.locale = 'en'});

  @override
  State<CoupleReadingScreen> createState() => _CoupleReadingScreenState();
}

class _CoupleReadingScreenState extends State<CoupleReadingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();

  // Person 1
  XFile? _person1Image;
  String _person1Name = '';
  String _person1HandSide = 'right';
  bool _person1Uploaded = false;
  String? _person1ImagePath;

  // Person 2
  XFile? _person2Image;
  String _person2Name = '';
  String _person2HandSide = 'right';
  bool _person2Uploaded = false;
  String? _person2ImagePath;

  bool _isCheckingEntitlement = true;
  bool _hasAccess = false;
  bool _isProcessing = false;
  _CoupleStage _currentStage = _CoupleStage.idle;
  String? _errorMessage;
  String? _qualityErrorPerson;

  bool get _isHindi => widget.locale == 'hi';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkEntitlement();
    analytics.track(
      HastVedaEvents.coupleReadingStarted,
      properties: {'language': widget.locale},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!context.watch<EntitlementNotifier>().isPremium || _hasAccess) return;
    _hasAccess = true;
    _isCheckingEntitlement = false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkEntitlement() async {
    setState(() => _isCheckingEntitlement = true);
    final hasAccess = await EntitlementService.instance.canAccessCoupleReading(
      forceRefresh: true,
    );
    if (mounted) {
      final premium = context.read<EntitlementNotifier>().isPremium;
      setState(() {
        _hasAccess = hasAccess || premium;
        _isCheckingEntitlement = false;
      });
    }
  }

  Future<void> _pickImage(bool isPerson1) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image != null && mounted) {
        setState(() {
          if (isPerson1) {
            _person1Image = image;
            _person1Uploaded = false;
            _person1ImagePath = null;
          } else {
            _person2Image = image;
            _person2Uploaded = false;
            _person2ImagePath = null;
          }
          _errorMessage = null;
          _qualityErrorPerson = null;
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(_isHindi ? 'छवि लोड नहीं हो सकी' : 'Could not load image');
      }
    }
  }

  // Upload a single palm image to Supabase storage and return the path
  Future<String?> _uploadImage(XFile image, String personLabel) async {
    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      final bytes = await image.readAsBytes();
      final ext = image.path.contains('.') ? image.path.split('.').last : 'jpg';
      final fileName =
          'couple_${personLabel}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storagePath = '$userId/couple/$fileName';

      await Supabase.instance.client.storage
          .from('palm-images')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      return storagePath;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _uploadAndMarkReady(bool isPerson1) async {
    final image = isPerson1 ? _person1Image : _person2Image;
    if (image == null) return;

    if (ConnectivityService.instance.isOffline) {
      final lp = context.read<LocaleProvider>();
      final s = AppStrings.of(lp.languageCode);
      setState(() => _errorMessage = s.internetRequired);
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _qualityErrorPerson = null;
      _currentStage = isPerson1
          ? _CoupleStage.uploadingPerson1
          : _CoupleStage.uploadingPerson2;
    });

    try {
      final path = await _uploadImage(image, isPerson1 ? 'p1' : 'p2');
      if (path == null) throw Exception('Upload failed');

      if (mounted) {
        setState(() {
          if (isPerson1) {
            _person1ImagePath = path;
            _person1Uploaded = true;
          } else {
            _person2ImagePath = path;
            _person2Uploaded = true;
          }
          _isProcessing = false;
          _currentStage = _CoupleStage.idle;
        });

        // Auto-advance tab
        if (isPerson1 && _tabController.index == 0) {
          _tabController.animateTo(1);
        } else if (!isPerson1 && _tabController.index == 1) {
          _tabController.animateTo(2);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStage = _CoupleStage.failed;
          _errorMessage = _isHindi
              ? 'छवि अपलोड विफल। कृपया पुनः प्रयास करें।'
              : 'Image upload failed. Please try again.';
        });
      }
    }
  }

  Future<void> _generateCoupleReading() async {
    if (!_person1Uploaded || !_person2Uploaded) return;
    if (_person1ImagePath == null || _person2ImagePath == null) return;

    if (ConnectivityService.instance.isOffline) {
      final lp = context.read<LocaleProvider>();
      final s = AppStrings.of(lp.languageCode);
      setState(() => _errorMessage = s.internetRequired);
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _qualityErrorPerson = null;
      _currentStage = _CoupleStage.analyzingPerson1;
    });

    try {
      final p1Name = _person1Name.isEmpty
          ? (_isHindi ? 'व्यक्ति १' : 'Person 1')
          : _person1Name;
      final p2Name = _person2Name.isEmpty
          ? (_isHindi ? 'व्यक्ति २' : 'Person 2')
          : _person2Name;

      // Advance stage indicator while waiting
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && _isProcessing) {
          setState(() => _currentStage = _CoupleStage.analyzingPerson2);
        }
      });
      Future.delayed(const Duration(seconds: 18), () {
        if (mounted && _isProcessing) {
          setState(() => _currentStage = _CoupleStage.generatingCompatibility);
        }
      });

      // Call the couple-reading Edge Function
      final response = await Supabase.instance.client.functions
          .invoke(
            'couple-reading',
            body: {
              'person1_image_path': _person1ImagePath,
              'person2_image_path': _person2ImagePath,
              'person1_name': p1Name,
              'person2_name': p2Name,
              'person1_hand_side': _person1HandSide,
              'person2_hand_side': _person2HandSide,
              'language': widget.locale,
            },
          )
          .timeout(const Duration(seconds: 180));

      final responseData = response.data;
      if (responseData == null) throw Exception('Empty response from server');

      Map<String, dynamic> data;
      if (responseData is String) {
        data = jsonDecode(responseData) as Map<String, dynamic>;
      } else if (responseData is Map<String, dynamic>) {
        data = responseData;
      } else {
        throw Exception('Unexpected response format');
      }

      // Handle image quality errors
      if (data['code'] == 'LOW_QUALITY_IMAGE_PERSON1' ||
          data['code'] == 'LOW_QUALITY_IMAGE_PERSON2') {
        final person = data['person'] as int? ?? 1;
        final palmDetected = data['palm_detected'] as bool? ?? false;
        final issues = (data['issues'] as List?)?.cast<String>() ?? [];
        String msg;
        if (_isHindi) {
          msg = palmDetected
              ? 'व्यक्ति $person की छवि की गुणवत्ता पर्याप्त नहीं है। ${issues.isNotEmpty ? issues.first : ""} कृपया बेहतर रोशनी में पुनः प्रयास करें।'
              : 'व्यक्ति $person की छवि में हथेली नहीं मिली। कृपया हथेली सपाट रखकर, उंगलियां खुली रखकर पुनः प्रयास करें।';
        } else {
          msg = palmDetected
              ? 'Person $person\'s image quality is insufficient. ${issues.isNotEmpty ? issues.first : ""} Please try again with better lighting.'
              : 'No palm detected in Person $person\'s image. Please keep palm flat, fingers open, and try again.';
        }
        setState(() {
          _isProcessing = false;
          _currentStage = _CoupleStage.failed;
          _errorMessage = msg;
          _qualityErrorPerson = 'person$person';
          if (person == 1) {
            _person1Uploaded = false;
            _person1ImagePath = null;
            _person1Image = null;
          } else {
            _person2Uploaded = false;
            _person2ImagePath = null;
            _person2Image = null;
          }
        });
        return;
      }

      // Handle entitlement error
      if (data['code'] == 'ENTITLEMENT_REQUIRED') {
        setState(() {
          _isProcessing = false;
          _currentStage = _CoupleStage.failed;
          _errorMessage = _isHindi
              ? 'युगल पठन के लिए प्रीमियम या युगल पठन एंटाइटेलमेंट आवश्यक है।'
              : 'Couple Reading requires Premium or a Couple Reading entitlement.';
        });
        return;
      }

      // Handle other errors
      if (data['error'] != null && data['success'] != true) {
        throw Exception(data['error'] as String? ?? 'Analysis failed');
      }

      if (data['success'] != true) {
        throw Exception('Analysis did not complete successfully');
      }

      final resultData = data['data'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStage = _CoupleStage.complete;
        });

        analytics.track(
          HastVedaEvents.coupleReadingCompleted,
          properties: {
            'language': widget.locale,
            'overall_score': resultData['overall_compatibility_score'],
          },
        );

        context.push(
          AppRoutes.coupleReadingResult,
          extra: {
            'person1Name': p1Name,
            'person2Name': p2Name,
            'compatibility': resultData,
            'locale': widget.locale,
          },
        );
      }
    } catch (e) {
      debugPrint('CoupleReading error: $e');
      // Log the couple reading failure
      final isTimeout =
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out');
      await errorLogger.log(
        category: ErrorCategory.coupleReading,
        operation: 'couple_reading_generate',
        userMessage: isTimeout
            ? 'Analysis timed out. Please try again.'
            : 'Could not generate couple reading. Please try again.',
        error: e,
        severity: isTimeout ? ErrorSeverity.medium : ErrorSeverity.high,
        extra: {'error_type': isTimeout ? 'timeout' : 'api_failure'},
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStage = _CoupleStage.failed;
          _errorMessage = isTimeout
              ? (_isHindi
                    ? 'विश्लेषण में समय अधिक लगा। कृपया पुनः प्रयास करें।'
                    : 'Analysis timed out. Please try again.')
              : (_isHindi
                    ? 'युगल पठन उत्पन्न नहीं हो सका। कृपया पुनः प्रयास करें।'
                    : 'Could not generate couple reading. Please try again.');
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isCheckingEntitlement) {
      return Scaffold(
        backgroundColor: isDark
            ? AppTheme.backgroundDark
            : AppTheme.backgroundLight,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (!_hasAccess) {
      return Scaffold(
        backgroundColor: isDark
            ? AppTheme.backgroundDark
            : AppTheme.backgroundLight,
        appBar: AppBar(
          backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.primary,
          foregroundColor: Colors.white,
          title: Text(
            _isHindi ? 'युगल पठन' : 'Couple Reading',
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
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              PremiumLockWidget(
                feature: PremiumFeatures.coupleReading,
                locale: widget.locale,
                showInline: false,
              ),
            ],
          ),
        ),
      );
    }

    final bgColor = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final appBarColor = isDark ? AppTheme.surfaceDark : AppTheme.primary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        title: Text(
          _isHindi ? 'युगल पठन' : 'Couple Reading',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(text: _isHindi ? 'व्यक्ति १' : 'Person 1'),
            Tab(text: _isHindi ? 'व्यक्ति २' : 'Person 2'),
            Tab(text: _isHindi ? 'परिणाम' : 'Result'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _PersonScanTab(
                personNumber: 1,
                image: _person1Image,
                name: _person1Name,
                handSide: _person1HandSide,
                isUploaded: _person1Uploaded,
                isHindi: _isHindi,
                isDark: isDark,
                onPickImage: () => _pickImage(true),
                onNameChanged: (v) => setState(() => _person1Name = v),
                onHandSideChanged: (v) => setState(() => _person1HandSide = v),
                onUpload: () => _uploadAndMarkReady(true),
                isLoading: _isProcessing,
              ),
              _PersonScanTab(
                personNumber: 2,
                image: _person2Image,
                name: _person2Name,
                handSide: _person2HandSide,
                isUploaded: _person2Uploaded,
                isHindi: _isHindi,
                isDark: isDark,
                onPickImage: () => _pickImage(false),
                onNameChanged: (v) => setState(() => _person2Name = v),
                onHandSideChanged: (v) => setState(() => _person2HandSide = v),
                onUpload: () => _uploadAndMarkReady(false),
                isLoading: _isProcessing,
              ),
              _GenerateTab(
                person1Name: _person1Name,
                person2Name: _person2Name,
                person1Ready: _person1Uploaded,
                person2Ready: _person2Uploaded,
                isHindi: _isHindi,
                isDark: isDark,
                isGenerating: _isProcessing,
                errorMessage: _errorMessage,
                onGenerate: _generateCoupleReading,
                onGoToP1: () => _tabController.animateTo(0),
                onGoToP2: () => _tabController.animateTo(1),
              ),
            ],
          ),
          if (_isProcessing)
            _AnalyzingOverlay(stage: _currentStage, isHindi: _isHindi),
        ],
      ),
    );
  }
}

// ── Analyzing Overlay ─────────────────────────────────────────────────────────
class _AnalyzingOverlay extends StatelessWidget {
  final _CoupleStage stage;
  final bool isHindi;

  const _AnalyzingOverlay({required this.stage, required this.isHindi});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(160),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withAlpha(60)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 20),
              const Icon(
                Icons.favorite_rounded,
                color: AppTheme.primary,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                isHindi ? 'युगल पठन' : 'Couple Reading',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stage.label(isHindi),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                isHindi
                    ? 'Gemini AI दोनों हथेलियों का विश्लेषण कर रहा है...\nइसमें 1-2 मिनट लग सकते हैं।'
                    : 'Gemini AI is analyzing both palms...\nThis may take 1-2 minutes.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Person Scan Tab ───────────────────────────────────────────────────────────
class _PersonScanTab extends StatelessWidget {
  final int personNumber;
  final XFile? image;
  final String name;
  final String handSide;
  final bool isUploaded;
  final bool isHindi;
  final bool isDark;
  final VoidCallback onPickImage;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onHandSideChanged;
  final VoidCallback onUpload;
  final bool isLoading;

  const _PersonScanTab({
    required this.personNumber,
    required this.image,
    required this.name,
    required this.handSide,
    required this.isUploaded,
    required this.isHindi,
    required this.isDark,
    required this.onPickImage,
    required this.onNameChanged,
    required this.onHandSideChanged,
    required this.onUpload,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppTheme.surfaceElevated : Colors.white;
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subTextColor = isDark
        ? AppTheme.textSecondary
        : const Color(0xFF8B7355);
    final borderColor = isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Header card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withAlpha(20),
                    border: Border.all(color: AppTheme.primary.withAlpha(60)),
                  ),
                  child: Center(
                    child: Text(
                      '$personNumber',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHindi
                            ? 'व्यक्ति $personNumber की हथेली'
                            : 'Person $personNumber\'s Palm',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      Text(
                        isHindi
                            ? 'हथेली की फोटो अपलोड करें'
                            : 'Upload a clear palm photo',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUploaded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppTheme.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isHindi ? 'तैयार' : 'Ready',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Name field
          Text(
            isHindi ? 'नाम (वैकल्पिक)' : 'Name (optional)',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: onNameChanged,
            style: GoogleFonts.outfit(fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: isHindi
                  ? 'व्यक्ति $personNumber का नाम दर्ज करें'
                  : 'Enter Person $personNumber\'s name',
              hintStyle: GoogleFonts.outfit(fontSize: 14, color: subTextColor),
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Hand side selector
          Text(
            isHindi ? 'हाथ चुनें' : 'Select Hand',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HandSideButton(
                  label: isHindi ? 'बायां हाथ' : 'Left Hand',
                  isSelected: handSide == 'left',
                  isDark: isDark,
                  onTap: () => onHandSideChanged('left'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HandSideButton(
                  label: isHindi ? 'दायां हाथ' : 'Right Hand',
                  isSelected: handSide == 'right',
                  isDark: isDark,
                  onTap: () => onHandSideChanged('right'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Palm image upload
          Text(
            isHindi ? 'हथेली की फोटो' : 'Palm Photo',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onPickImage,
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.surfaceElevated
                    : const Color(0xFFFFF8F3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: image != null
                      ? AppTheme.primary
                      : AppTheme.primary.withAlpha(60),
                  width: image != null ? 2 : 1,
                ),
              ),
              child: image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: kIsWeb
                          ? Image.network(
                              image!.path,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppTheme.primary,
                                size: 48,
                              ),
                            )
                          : Image.file(File(image!.path), fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primary.withAlpha(15),
                          ),
                          child: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AppTheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isHindi
                              ? 'गैलरी से फोटो चुनें'
                              : 'Choose from Gallery',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isHindi
                              ? 'स्पष्ट हथेली की फोटो अपलोड करें'
                              : 'Upload a clear palm photo',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Tips
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cyanMuted : const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? AppTheme.cyan.withAlpha(40)
                    : const Color(0xFFBAE6FD),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: isDark ? AppTheme.cyan : const Color(0xFF0284C7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isHindi
                        ? 'सर्वोत्तम परिणाम के लिए: हथेली को सपाट रखें, अच्छी रोशनी में फोटो लें, उंगलियां थोड़ी खुली रखें।'
                        : 'For best results: Keep palm flat, good lighting, fingers slightly spread.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark ? AppTheme.cyan : const Color(0xFF0369A1),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Upload / Ready button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: image != null && !isLoading ? onUpload : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isUploaded
                    ? AppTheme.success
                    : AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isUploaded
                        ? Icons.check_circle_rounded
                        : Icons.cloud_upload_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isUploaded
                        ? (isHindi
                              ? 'तैयार — पुनः अपलोड करें'
                              : 'Ready — Re-upload')
                        : (isHindi ? 'हथेली अपलोड करें' : 'Upload Palm'),
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandSideButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _HandSideButton({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(20)
              : (isDark ? AppTheme.surfaceElevated : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : (isDark ? AppTheme.outlineDark : const Color(0xFFEDE5DF)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? AppTheme.primary
                  : (isDark ? AppTheme.textSecondary : const Color(0xFF8B7355)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Generate Tab ──────────────────────────────────────────────────────────────
class _GenerateTab extends StatelessWidget {
  final String person1Name;
  final String person2Name;
  final bool person1Ready;
  final bool person2Ready;
  final bool isHindi;
  final bool isDark;
  final bool isGenerating;
  final String? errorMessage;
  final VoidCallback onGenerate;
  final VoidCallback onGoToP1;
  final VoidCallback onGoToP2;

  const _GenerateTab({
    required this.person1Name,
    required this.person2Name,
    required this.person1Ready,
    required this.person2Ready,
    required this.isHindi,
    required this.isDark,
    required this.isGenerating,
    required this.errorMessage,
    required this.onGenerate,
    required this.onGoToP1,
    required this.onGoToP2,
  });

  @override
  Widget build(BuildContext context) {
    final bothReady = person1Ready && person2Ready;
    final p1Label = person1Name.isEmpty
        ? (isHindi ? 'व्यक्ति १' : 'Person 1')
        : person1Name;
    final p2Label = person2Name.isEmpty
        ? (isHindi ? 'व्यक्ति २' : 'Person 2')
        : person2Name;
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF1A1410);
    final subTextColor = isDark
        ? AppTheme.textSecondary
        : const Color(0xFF8B7355);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primary.withAlpha(30),
                  AppTheme.primary.withAlpha(8),
                ],
              ),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppTheme.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isHindi ? 'युगल अनुकूलता पठन' : 'Couple Compatibility Reading',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isHindi
                ? 'Gemini AI दोनों हथेलियों का विश्लेषण करके वास्तविक अनुकूलता रिपोर्ट तैयार करेगा'
                : 'Gemini AI will analyze both palms and generate a real compatibility report',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: subTextColor,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Status cards
          Row(
            children: [
              Expanded(
                child: _StatusCard(
                  name: p1Label,
                  isReady: person1Ready,
                  isHindi: isHindi,
                  isDark: isDark,
                  onFix: onGoToP1,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.favorite_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatusCard(
                  name: p2Label,
                  isReady: person2Ready,
                  isHindi: isHindi,
                  isDark: isDark,
                  onFix: onGoToP2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // What you'll get
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.surfaceElevated
                  : const Color(0xFFFFF8F3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withAlpha(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHindi ? 'आपको क्या मिलेगा:' : 'What you\'ll receive:',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 12),
                ..._aspects(isHindi).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          item['emoji']!,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['label']!,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: isDark
                                  ? AppTheme.textSecondary
                                  : const Color(0xFF5C4A3A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI disclaimer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.goldMuted : const Color(0xFFFFF9E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isHindi
                        ? 'Gemini AI प्रत्येक हथेली की वास्तविक रेखाओं और विशेषताओं का विश्लेषण करके अनुकूलता निर्धारित करेगा। यह हस्तरेखा शास्त्र की पारंपरिक व्याख्या है — वैज्ञानिक तथ्य नहीं।'
                        : 'Gemini AI will analyze the actual lines and features of each palm to determine compatibility. This is traditional palmistry interpretation — not scientific fact.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark
                          ? AppTheme.goldLight
                          : const Color(0xFF92400E),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                errorMessage!,
                style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.error),
              ),
            ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: bothReady && !isGenerating ? onGenerate : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isHindi
                        ? 'अनुकूलता रिपोर्ट तैयार करें'
                        : 'Generate Compatibility Report',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!bothReady)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                isHindi
                    ? 'पहले दोनों व्यक्तियों की हथेली अपलोड करें'
                    : 'Please upload both persons\' palms first',
                style: GoogleFonts.outfit(fontSize: 12, color: subTextColor),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, String>> _aspects(bool isHindi) => [
    {
      'emoji': '🔬',
      'label': isHindi
          ? 'प्रत्येक हथेली का वास्तविक Gemini विश्लेषण'
          : 'Real Gemini analysis of each palm',
    },
    {
      'emoji': '❤️',
      'label': isHindi
          ? 'हृदय रेखा तुलना से प्रेम अनुकूलता'
          : 'Love compatibility from heart line comparison',
    },
    {
      'emoji': '💞',
      'label': isHindi ? 'भावनात्मक प्रवृत्तियां' : 'Emotional tendencies',
    },
    {
      'emoji': '💬',
      'label': isHindi
          ? 'मस्तिष्क रेखा से संचार पैटर्न'
          : 'Communication patterns from head line',
    },
    {
      'emoji': '🤝',
      'label': isHindi
          ? 'वास्तविक हथेली डेटा से शक्तियां और चुनौतियां'
          : 'Strengths & challenges from real palm data',
    },
    {'emoji': '💍', 'label': isHindi ? 'विवाह संकेतक' : 'Marriage indicators'},
    {
      'emoji': '📊',
      'label': isHindi ? 'समग्र अनुकूलता स्कोर' : 'Overall compatibility score',
    },
  ];
}

class _StatusCard extends StatelessWidget {
  final String name;
  final bool isReady;
  final bool isHindi;
  final bool isDark;
  final VoidCallback onFix;

  const _StatusCard({
    required this.name,
    required this.isReady,
    required this.isHindi,
    required this.isDark,
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isReady ? null : onFix,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isReady
              ? AppTheme.success.withAlpha(10)
              : (isDark ? AppTheme.surfaceElevated : const Color(0xFFFFF8F3)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isReady
                ? AppTheme.success.withAlpha(60)
                : AppTheme.primary.withAlpha(40),
          ),
        ),
        child: Column(
          children: [
            Icon(
              isReady
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isReady ? AppTheme.success : AppTheme.primary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.textPrimary : const Color(0xFF1A1410),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              isReady
                  ? (isHindi ? 'तैयार ✓' : 'Ready ✓')
                  : (isHindi ? 'अपलोड बाकी' : 'Pending'),
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: isReady
                    ? AppTheme.success
                    : (isDark ? AppTheme.textMuted : const Color(0xFF8B7355)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
