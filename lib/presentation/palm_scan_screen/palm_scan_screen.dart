import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../routes/app_routes.dart';
import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/connectivity_service.dart';
import '../../services/entitlement_service.dart';
import '../../services/locale_provider.dart';
import '../../services/palm_analysis_service.dart';
import '../../services/palm_failure_logger.dart';
import '../../services/palm_failure_reason.dart';
import './widgets/palm_guide_overlay_widget.dart';

// ── Scan flow states ──────────────────────────────────────────────────────────
enum _ScanFlowState {
  handSelection, // Step 1: choose left/right hand
  positioning, // Step 2: live camera + guide, waiting for user to tap scan
  scanning, // Step 3: animated scan in progress
  analyzing, // Step 4: uploading + AI analysis
  complete, // Step 5: success
  error, // Error state
}

class PalmScanScreen extends StatefulWidget {
  const PalmScanScreen({super.key});

  @override
  State<PalmScanScreen> createState() => _PalmScanScreenState();
}

class _PalmScanScreenState extends State<PalmScanScreen>
    with TickerProviderStateMixin {
  _ScanFlowState _flowState = _ScanFlowState.handSelection;
  String _handSide = 'right';
  String? _errorMessage;

  // The specific reason the last attempt failed. Drives the error headline and
  // the correction tips, so the user is told what to change rather than just
  // that the scan failed.
  PalmFailureReason _failureReason = PalmFailureReason.unknown;

  /// Set when the Edge Function's own message is more specific than the fixed
  /// copy for [_failureReason] (e.g. "palm is cut off at the bottom").
  String? _failureDetail;

  // Set when the failure is a quota limit rather than a scan problem, so the
  // error view offers "View Premium Plans" instead of "Try Again".
  bool _showUpgradeAction = false;
  PalmAnalysisStage _analysisStage = PalmAnalysisStage.idle;

  // Camera
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _cameraPermissionDenied = false;

  // Used when no live camera is available (browser blocked it, or no device).
  final ImagePicker _picker = ImagePicker();

  // Scan animation
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnim;
  Timer? _stageTimer;

  // Success animation
  late AnimationController _successController;
  late Animation<double> _successAnim;

  /// True while this screen is holding the display awake.
  bool _screenWakeEnabled = false;

  @override
  void initState() {
    super.initState();
    analytics.track(HastVedaEvents.palmScanStarted);
    _enableScreenWake();

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successAnim = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _disableScreenWake();
    _scanLineController.dispose();
    _successController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Screen-wake lock ──────────────────────────────────────────────────────

  /// Keeps the display on for the whole palm-scan screen, including camera
  /// setup. A missing platform implementation must not stop the scan.
  Future<void> _enableScreenWake() async {
    if (_screenWakeEnabled) return;
    try {
      await WakelockPlus.enable();
      _screenWakeEnabled = true;
    } catch (e) {
      debugPrint('WakelockPlus.enable failed: $e');
    }
  }

  /// Restores the normal screen timeout. Safe to call more than once.
  Future<void> _disableScreenWake() async {
    if (!_screenWakeEnabled) return;
    _screenWakeEnabled = false;
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('WakelockPlus.disable failed: $e');
    }
  }

  /// Applies a flow-state transition. The wake lock stays on until the scan
  /// completes or this screen is disposed.
  void _setFlowState(VoidCallback mutation) {
    if (!mounted) return;
    setState(mutation);
  }

  // ── Camera init ───────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      // permission_handler has no web implementation — on web the browser's own
      // getUserMedia prompt handles consent when the controller initializes.
      if (!kIsWeb) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) setState(() => _cameraPermissionDenied = true);
          return;
        }
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraPermissionDenied = true);
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // veryHigh (1080p) rather than high (720p): palm lines are fine detail and
      // 720p was costing real resolution at the quality gate. Falls back if the
      // device cannot provide it.
      CameraController controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await controller.initialize();
      } on CameraException catch (e) {
        debugPrint('Camera veryHigh preset failed (${e.code}) — using high');
        await controller.dispose();
        controller = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await controller.initialize();
      }

      if (!mounted) {
        controller.dispose();
        return;
      }

      // Point autofocus and metering at the centre of the frame, where the
      // palm guide sits. Without this the camera meters the whole scene and a
      // close-range palm — a large flat surface — makes continuous AF hunt.
      // That hunting is why a first attempt often came back soft while the
      // immediate retry, with focus already converged, passed the gate.
      //
      // camera_web throws `UnimplementedError` (not `CameraException`) for
      // every point-AF/AE method, and some Android devices throw arbitrary
      // platform errors. Catch broadly so an unsupported feature doesn't
      // dead-end the whole preview on the "Camera Permission Required"
      // fallback — the capture path still works without it.
      if (!kIsWeb) {
        try {
          await controller.setFocusPoint(const Offset(0.5, 0.5));
          await controller.setExposurePoint(const Offset(0.5, 0.5));
          await controller.setFocusMode(FocusMode.auto);
          await controller.setExposureMode(ExposureMode.auto);
        } catch (e) {
          debugPrint('Camera focus/exposure setup unsupported: $e');
        }
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _cameraPermissionDenied = true);
    }
  }

  // ── Hand selection confirmed ──────────────────────────────────────────────

  Future<void> _onHandSelected(String hand) async {
    await _enableScreenWake();
    _setFlowState(() {
      _handSide = hand;
      _flowState = _ScanFlowState.positioning;
    });
    await _initCamera();
  }

  // ── User taps "Scan Now" ──────────────────────────────────────────────────

  Future<void> _onStartScan() async {
    final connectivity = ConnectivityService.instance;
    if (connectivity.isOffline) {
      final lp = context.read<LocaleProvider>();
      final s = AppStrings.of(lp.languageCode);
      _setFlowState(() {
        _flowState = _ScanFlowState.error;
        _failureReason = PalmFailureReason.networkError;
        _failureDetail = null;
        _errorMessage = s.internetRequired;
      });
      return;
    }

    // Start scanning animation
    _setFlowState(() => _flowState = _ScanFlowState.scanning);
    _scanLineController.repeat();

    // Simulate guided scan for 2.5 seconds before capture
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    // Capture
    await _captureAndAnalyze();
  }

  // ── Focus settling ────────────────────────────────────────────────────────

  /// Gives autofocus time to converge on the palm, then locks it for the shot.
  ///
  /// A palm held close to the lens is a large, low-contrast, flat subject —
  /// exactly what makes continuous autofocus hunt. Capturing mid-hunt yields a
  /// soft image that the quality gate correctly rejects, which is the most
  /// likely cause of "attempt 1 failed, attempt 2 succeeded": by the retry the
  /// lens had already settled on the same subject.
  ///
  /// This improves the image the gate receives. It does not change the gate.
  Future<void> _settleFocusBeforeCapture(CameraController controller) async {
    if (kIsWeb) return;
    try {
      await controller.setFocusPoint(const Offset(0.5, 0.5));
      await controller.setExposurePoint(const Offset(0.5, 0.5));
      await controller.setFocusMode(FocusMode.auto);

      // Increased from 900ms to 1500ms to allow slower PDAF devices to fully
      // converge. A palm held close is a large, low-contrast subject that
      // causes continuous AF to hunt — the extra settle time prevents the
      // lens from still moving when the shutter fires.
      await Future.delayed(const Duration(milliseconds: 1500));

      // Lock so the lens cannot start hunting again during the exposure.
      await controller.setFocusMode(FocusMode.locked);
      await controller.setExposureMode(ExposureMode.locked);
      // Brief pause after lock to let the hardware register the locked state.
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint('Focus settle skipped: $e');
    }
  }

  /// Returns the camera to continuous AF/AE so a retry is not stuck on the
  /// focus locked for the previous shot.
  Future<void> _releaseFocusLock() async {
    if (kIsWeb) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {
      // Nothing to recover — the controller is disposed on retry anyway.
    }
  }

  // ── Capture + analyze ─────────────────────────────────────────────────────

  Future<void> _captureAndAnalyze() async {
    final lp = context.read<LocaleProvider>();
    final s = AppStrings.of(lp.languageCode);

    // Hoisted so the catch blocks can attribute a client-side failure to the
    // scan it belongs to.
    String? scanIdForLog;

    try {
      // Check the monthly quota before capturing anything. The Edge Function
      // enforces this authoritatively; this call only saves the user from
      // uploading an image that would be rejected. A failed check falls
      // through and lets the server decide.
      final quota = await EntitlementService.instance.checkFreeTierLimit(
        'scans_per_month',
      );
        if (quota.hasReachedLimit) {
        _stopStageProgressionTimer();
        _scanLineController.stop();
        if (mounted) {
          _setFlowState(() {
            _flowState = _ScanFlowState.error;
            _failureReason = PalmFailureReason.freeLimitReached;
            _failureDetail = null;
            _errorMessage = s.freeScanLimitReached(quota.limit ?? 2);
            _showUpgradeAction = !quota.isPremium;
          });
        }
        return;
      }

      analytics.track(HastVedaEvents.palmCaptureStarted);

      // Stop scan animation, start analysis
      _scanLineController.stop();
      _setFlowState(() {
        _flowState = _ScanFlowState.analyzing;
        _analysisStage = PalmAnalysisStage.uploadingImage;
      });

      // Capture image. XFile.readAsBytes() works on every platform — reading via
      // dart:io File(photo.path) would break on web, where the path is a blob URL.
      Uint8List imageBytes;
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _settleFocusBeforeCapture(_cameraController!);
        final XFile photo = await _cameraController!.takePicture();
        imageBytes = await photo.readAsBytes();
      } else {
        // No live camera (browser blocked it, or no device) — let the user pick
        // a palm photo instead. Sending an empty image guarantees a failed scan.
        final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2048,
        );
        if (picked == null) {
          // User cancelled — go back to positioning rather than failing the scan.
          if (mounted) {
            _setFlowState(() => _flowState = _ScanFlowState.positioning);
          }
          return;
        }
        imageBytes = await picked.readAsBytes();
      }

      if (imageBytes.isEmpty) {
        throw Exception('Captured image was empty');
      }

      analytics.track(HastVedaEvents.palmCaptureCompleted);
      analytics.track(HastVedaEvents.palmAnalysisStarted);

      final palmService = PalmAnalysisService.instance;

      // Create scan record
      final scan = await palmService.createScanRecord(handType: _handSide);
      if (scan == null) throw Exception('Failed to create scan record');
      scanIdForLog = scan.id;

      // Upload image
      final imagePath = await palmService.uploadPalmImage(
        scanId: scan.id,
        imageBytes: imageBytes,
        fileName: 'palm_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      if (imagePath == null) throw Exception('Failed to upload palm image');

      // Advance stages visually while Edge Function runs
      setState(() => _analysisStage = PalmAnalysisStage.checkingQuality);
      _startStageProgressionTimer();

      final result = await palmService.analyzePalm(
        scanId: scan.id,
        imagePath: imagePath,
        handSide: _handSide,
        language: lp.languageCode,
        onStageChange: (stage) {
          if (mounted) setState(() => _analysisStage = stage);
        },
      );

      _stopStageProgressionTimer();

      analytics.track(
        HastVedaEvents.palmAnalysisCompleted,
        properties: {
          'hand_side': _handSide,
          'confidence': result.overallConfidence,
          'is_premium': result.isPremium,
          'cached': result.cached,
        },
      );

      if (mounted) {
        _setFlowState(() => _flowState = _ScanFlowState.complete);
        await _disableScreenWake();
        _successController.forward();

        // Navigate after showing success for 1.5s.
        //
        // `pushReplacement` (not `push`) is deliberate: it removes THIS camera
        // screen from the back stack before Palm Analysis is shown. That means
        // when the user taps the back arrow on Palm Analysis they land on the
        // screen that opened the scan (Home / Reading History), not on the
        // camera preview — and it also means go_router's imperative stack
        // stays shallow enough that `context.pop()` on Palm Analysis behaves
        // predictably in release APKs (the deep shell-branch + top-level push
        // combination was silently no-op'ing pop on Android).
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          context.pushReplacement(
            '${AppRoutes.palmAnalysis}?locale=${lp.languageCode}',
            extra: _buildAnalysisExtra(result, lp.languageCode),
          );
        }
      }
    } on FreeScanLimitException catch (e) {
      _stopStageProgressionTimer();
      analytics.track(
        HastVedaEvents.palmScanFailed,
        properties: {'reason': 'free_limit_reached', 'limit': e.limit},
      );
      if (mounted) {
        final lp2 = context.read<LocaleProvider>();
        final s2 = AppStrings.of(lp2.languageCode);
        _setFlowState(() {
          _flowState = _ScanFlowState.error;
          _failureReason = PalmFailureReason.freeLimitReached;
          _failureDetail = null;
          _errorMessage = s2.freeScanLimitReached(e.limit);
          _showUpgradeAction = !e.isPremium;
        });
      }
    } on ImageQualityException catch (e) {
      _stopStageProgressionTimer();
      // Log the resolved reason, not a flat "image_quality" — this is what
      // makes "which capture problem is most common" answerable.
      analytics.track(
        HastVedaEvents.palmScanFailed,
        properties: {
          'reason': e.reason.code,
          'quality_score': e.qualityScore,
          'palm_detected': e.palmDetected,
          'hand_side': _handSide,
        },
      );
      debugPrint(
        '[PalmScan] quality gate rejected: ${e.reason.code} '
        'score=${e.qualityScore} palmDetected=${e.palmDetected} '
        'issues=${e.issues}',
      );
      if (mounted) {
        _setFlowState(() {
          _flowState = _ScanFlowState.error;
          _failureReason = e.reason;
          _failureDetail = e.detail;
          _errorMessage = null;
        });
      }
    } catch (e) {
      _stopStageProgressionTimer();
      debugPrint('Palm scan error: $e');
      final reason = palmFailureReasonOf(e);
      analytics.track(
        HastVedaEvents.palmScanFailed,
        properties: {
          'reason': reason.code,
          'hand_side': _handSide,
          'detail': e.toString().substring(
            0,
            e.toString().length.clamp(0, 100),
          ),
        },
      );
      // Failures that never reached the Edge Function (no connectivity, upload
      // errors) have no server-side row — record them from here so the failure
      // log stays complete.
      unawaited(
        PalmFailureLogger.instance.logClientFailure(
          reason: reason,
          stage: 'client',
          scanId: scanIdForLog,
          handSide: _handSide,
          language: lp.languageCode,
          error: e,
          serverLogged: PalmFailureLogger.wasLoggedByServer(e),
        ),
      );
      if (mounted) {
        final lp2 = context.read<LocaleProvider>();
        final s2 = AppStrings.of(lp2.languageCode);
        _setFlowState(() {
          _flowState = _ScanFlowState.error;
          _failureReason = reason;
          _failureDetail = null;
          // Keep the existing translated copy for reasons the shared map does
          // not cover better (auth, offline, scan-record problems).
          _errorMessage = reason == PalmFailureReason.unknown
              ? describePalmAnalysisError(
                  e,
                  strings: s2,
                  isHindi: lp2.languageCode == 'hi',
                )
              : null;
        });
      }
    }
  }

  void _startStageProgressionTimer() {
    _stageTimer?.cancel();
    final stages = [
      (8, PalmAnalysisStage.extractingFeatures),
      (25, PalmAnalysisStage.generatingReading),
    ];
    for (final (delay, stage) in stages) {
      Future.delayed(Duration(seconds: delay), () {
        if (mounted && _flowState == _ScanFlowState.analyzing) {
          setState(() => _analysisStage = stage);
        }
      });
    }
  }

  void _stopStageProgressionTimer() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  void _retryFromHandSelection() {
    // Release the AF/AE lock before disposing so a device that keeps camera
    // state across controllers does not start the retry stuck on the focus
    // chosen for the failed shot.
    unawaited(_releaseFocusLock());
    _cameraController?.dispose();
    _cameraController = null;
    _setFlowState(() {
      _flowState = _ScanFlowState.handSelection;
      _cameraReady = false;
      _cameraPermissionDenied = false;
      _errorMessage = null;
      _failureReason = PalmFailureReason.unknown;
      _failureDetail = null;
      _showUpgradeAction = false;
      _analysisStage = PalmAnalysisStage.idle;
    });
    _scanLineController.stop();
    _scanLineController.reset();
    _successController.reset();
  }

  Map<String, dynamic> _buildAnalysisExtra(
    PalmAnalysisResult result,
    String lang,
  ) {
    return {
      'analysis_id': result.analysisId,
      'scan_id': result.scanId,
      'hand_side': result.handSide,
      'overall_score': result.overallScore,
      'summary': result.summary(lang),
      'summary_en': result.summaryEn,
      'summary_hi': result.summaryHi,
      'confidence_score': result.overallConfidence,
      'is_premium': result.isPremium,
      'key_traits': result.keyTraits(lang),
      'key_traits_en': result.keyTraitsEn,
      'key_traits_hi': result.keyTraitsHi,
      'daily_insight': result.dailyInsight(lang),
      'daily_insight_en': result.dailyInsightEn,
      'daily_insight_hi': result.dailyInsightHi,
      'remedies_en': result.remediesEn,
      'remedies_hi': result.remediesHi,
      'confidence_note': result.confidenceNote(lang),
      'confidence_note_en': result.confidenceNoteEn,
      'confidence_note_hi': result.confidenceNoteHi,
      'heart_line_score': result.loveRelationships.score,
      'head_line_score': result.personality.score,
      'life_line_score': result.lifePath.score,
      'personality': {
        'title': result.personality.title(lang),
        'content': result.personality.content(lang),
        'content_en': result.personality.contentEn,
        'content_hi': result.personality.contentHi,
        'score': result.personality.score,
        'locked': result.personality.isPremiumLocked,
      },
      'love_relationships': {
        'title': result.loveRelationships.title(lang),
        'content': result.loveRelationships.content(lang),
        'content_en': result.loveRelationships.contentEn,
        'content_hi': result.loveRelationships.contentHi,
        'score': result.loveRelationships.score,
        'locked': result.loveRelationships.isPremiumLocked,
      },
      'career': {
        'title': result.career.title(lang),
        'content': result.career.content(lang),
        'content_en': result.career.contentEn,
        'content_hi': result.career.contentHi,
        'score': result.career.score,
        'locked': result.career.isPremiumLocked,
      },
      'wealth': {
        'title': result.wealth.title(lang),
        'content': result.wealth.content(lang),
        'content_en': result.wealth.contentEn,
        'content_hi': result.wealth.contentHi,
        'score': result.wealth.score,
        'locked': result.wealth.isPremiumLocked,
      },
      'health': {
        'title': result.health.title(lang),
        'content': result.health.content(lang),
        'content_en': result.health.contentEn,
        'content_hi': result.health.contentHi,
        'score': result.health.score,
        'locked': result.health.isPremiumLocked,
      },
      'life_path': {
        'title': result.lifePath.title(lang),
        'content': result.lifePath.content(lang),
        'content_en': result.lifePath.contentEn,
        'content_hi': result.lifePath.contentHi,
        'score': result.lifePath.score,
        'locked': result.lifePath.isPremiumLocked,
      },
      'future_tendencies': {
        'title': result.futureTendencies.title(lang),
        'content': result.futureTendencies.content(lang),
        'content_en': result.futureTendencies.contentEn,
        'content_hi': result.futureTendencies.contentHi,
        'score': result.futureTendencies.score,
        'locked': result.futureTendencies.isPremiumLocked,
      },
      'palm_features': result.palmFeatures,
      'mounts': result.mounts,
      'special_marks': result.specialMarks,
      'palm_shape': result.palmShape,
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final isHindi = localeProvider.isHindi;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildCurrentState(isHindi),
      ),
    );
  }

  Widget _buildCurrentState(bool isHindi) {
    switch (_flowState) {
      case _ScanFlowState.handSelection:
        return _HandSelectionView(
          key: const ValueKey('hand_selection'),
          selectedHand: _handSide,
          isHindi: isHindi,
          onHandSelected: _onHandSelected,
          onBack: popOrHome,
        );
      case _ScanFlowState.positioning:
        return _PositioningView(
          key: const ValueKey('positioning'),
          isHindi: isHindi,
          handSide: _handSide,
          cameraController: _cameraController,
          cameraReady: _cameraReady,
          cameraPermissionDenied: _cameraPermissionDenied,
          onScan: _onStartScan,
          onUploadInstead: _captureAndAnalyze,
          onBack: _retryFromHandSelection,
        );
      case _ScanFlowState.scanning:
        return _ScanningView(
          key: const ValueKey('scanning'),
          isHindi: isHindi,
          handSide: _handSide,
          cameraController: _cameraController,
          scanLineAnim: _scanLineAnim,
        );
      case _ScanFlowState.analyzing:
        return _AnalyzingView(
          key: const ValueKey('analyzing'),
          isHindi: isHindi,
          stage: _analysisStage,
        );
      case _ScanFlowState.complete:
        return _CompleteView(
          key: const ValueKey('complete'),
          isHindi: isHindi,
          successAnim: _successAnim,
        );
      case _ScanFlowState.error:
        final lang = context.read<LocaleProvider>().languageCode;
        // A pre-built message (auth, offline, quota) wins; otherwise the
        // reason-specific copy supplies both headline and correction tips.
        final base = palmFailureCopy(
          _failureReason,
          lang: lang,
          detail: _failureDetail,
        );
        final copy = _errorMessage == null
            ? base
            : PalmFailureCopy(
                title: base.title,
                message: _errorMessage!,
                tips: base.tips,
              );
        return _ErrorView(
          key: ValueKey('error_${_failureReason.code}'),
          isHindi: isHindi,
          message: _errorMessage,
          copy: copy,
          isCaptureProblem: _failureReason.isCaptureProblem,
          onRetry: _retryFromHandSelection,
          onBack: popOrHome,
          showUpgrade: _showUpgradeAction,
          onUpgrade: () => context.push(AppRoutes.premiumPaywall),
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 1: Hand Selection View
// ══════════════════════════════════════════════════════════════════════════════

class _HandSelectionView extends StatelessWidget {
  final String selectedHand;
  final bool isHindi;
  final ValueChanged<String> onHandSelected;
  final VoidCallback onBack;

  const _HandSelectionView({
    super.key,
    required this.selectedHand,
    required this.isHindi,
    required this.onHandSelected,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0805), Color(0xFF1A0F05), Color(0xFF0D0805)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'HastVeda',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE8A020), Color(0xFFD4A843)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4A843).withAlpha(80),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.back_hand_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Text(
                      isHindi ? 'हाथ चुनें' : 'Select Your Hand',
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isHindi
                          ? 'सटीक हस्तरेखा विश्लेषण के लिए\nकौन सा हाथ स्कैन करना है?'
                          : 'Which hand would you like to scan\nfor your palm reading?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.white60,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Hand selection buttons — side by side, never overlapping
                    Row(
                      children: [
                        Expanded(
                          child: _HandButton(
                            label: isHindi ? 'बायां हाथ' : 'Left Hand',
                            sublabel: isHindi ? 'Left' : 'Left',
                            icon: Icons.back_hand_outlined,
                            isSelected: selectedHand == 'left',
                            onTap: () => onHandSelected('left'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _HandButton(
                            label: isHindi ? 'दायां हाथ' : 'Right Hand',
                            sublabel: isHindi ? 'Right' : 'Right',
                            icon: Icons.back_hand,
                            isSelected: selectedHand == 'right',
                            onTap: () => onHandSelected('right'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Info note
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A843).withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD4A843).withAlpha(60),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFD4A843),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isHindi
                                  ? 'परंपरागत रूप से दाहिना हाथ भाग्य और बायां हाथ जन्मजात गुण दर्शाता है'
                                  : 'Traditionally, the right hand shows destiny and the left shows innate traits',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: const Color(0xFFD4A843),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HandButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _HandButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFD4A843).withAlpha(30)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4A843)
                : Colors.white.withAlpha(30),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFD4A843).withAlpha(40),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFD4A843) : Colors.white54,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFFD4A843) : Colors.white70,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A843),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '✓ Selected',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 2: Positioning View (live camera + guide)
// ══════════════════════════════════════════════════════════════════════════════

class _PositioningView extends StatelessWidget {
  final bool isHindi;
  final String handSide;
  final CameraController? cameraController;
  final bool cameraReady;
  final bool cameraPermissionDenied;
  final VoidCallback onScan;
  final VoidCallback onUploadInstead;
  final VoidCallback onBack;

  const _PositioningView({
    super.key,
    required this.isHindi,
    required this.handSide,
    required this.cameraController,
    required this.cameraReady,
    required this.cameraPermissionDenied,
    required this.onScan,
    required this.onUploadInstead,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final handLabel = handSide == 'left'
        ? (isHindi ? 'बायां हाथ' : 'Left Hand')
        : (isHindi ? 'दायां हाथ' : 'Right Hand');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview or fallback
        _buildCameraBackground(),

        // Palm guide overlay
        if (cameraReady && !cameraPermissionDenied)
          const PalmGuideOverlayWidget(animationState: ScanAnimationState.idle),

        // Permission denied overlay
        if (cameraPermissionDenied) _buildPermissionDenied(isHindi),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(100),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFD4A843).withAlpha(100),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        handSide == 'left'
                            ? Icons.back_hand_outlined
                            : Icons.back_hand,
                        color: const Color(0xFFD4A843),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        handLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD4A843),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Instructions
        if (cameraReady && !cameraPermissionDenied)
          Positioned(
            bottom: 160 + bottomPadding,
            left: 24,
            right: 24,
            child: Column(
              children: [
                // Left-hand specific orientation tip — the most common cause of
                // left-palm failures is the user presenting the back of their
                // hand or holding it at an angle. Right-hand users naturally
                // face their palm toward the camera; left-hand users need to
                // rotate their wrist outward (supinate) to do the same.
                if (handSide == 'left')
                  _InstructionChip(
                    text: isHindi
                        ? 'बायीं हथेली को कैमरे की ओर मोड़ें'
                        : 'Rotate your left wrist so your palm faces the camera',
                    isWarning: true,
                  ),
                if (handSide == 'left') const SizedBox(height: 8),
                _InstructionChip(
                  text: isHindi
                      ? 'हथेली को फ्रेम के अंदर रखें'
                      : 'Place your palm inside the frame',
                ),
                const SizedBox(height: 8),
                _InstructionChip(
                  text: isHindi ? 'हाथ को स्थिर रखें' : 'Keep your hand steady',
                  secondary: true,
                ),
              ],
            ),
          ),

        // Scan button
        if (cameraReady && !cameraPermissionDenied)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottomPadding),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.black.withAlpha(0)],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onScan,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE8A020), Color(0xFFD4A843)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4A843).withAlpha(80),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.document_scanner_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isHindi ? 'स्कैन शुरू करें' : 'Start Palm Scan',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Gallery upload option — always visible when camera is working
                  GestureDetector(
                    onTap: onUploadInstead,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withAlpha(15),
                        border: Border.all(
                          color: const Color(0xFFD4A843).withAlpha(80),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.photo_library_rounded,
                            color: Color(0xFFD4A843),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isHindi
                                ? 'गैलरी से अपलोड करें'
                                : 'Upload from Gallery',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFD4A843),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Loading camera
        if (!cameraReady && !cameraPermissionDenied)
          Container(
            color: Colors.black.withAlpha(180),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFFE8650A),
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isHindi
                        ? 'कैमरा तैयार हो रहा है...'
                        : 'Preparing camera...',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCameraBackground() {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [Color(0xFF1A0F05), Color(0xFF0A0603)],
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: cameraController!.value.previewSize?.height ?? 1,
          height: cameraController!.value.previewSize?.width ?? 1,
          child: CameraPreview(cameraController!),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied(bool isHindi) {
    return Container(
      color: Colors.black.withAlpha(220),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withAlpha(30),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.orange,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isHindi
                    ? 'कैमरा अनुमति आवश्यक है'
                    : 'Camera Permission Required',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isHindi
                    ? 'हथेली स्कैन के लिए कैमरा एक्सेस दें, या एक फोटो अपलोड करें'
                    : 'Grant camera access to scan your palm, or upload a photo',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 14, color: Colors.white60),
              ),
              const SizedBox(height: 24),
              // permission_handler has no web implementation, so there are no
              // app settings to open in a browser.
              if (!kIsWeb)
                ElevatedButton(
                  onPressed: () => openAppSettings(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A843),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  child: Text(
                    isHindi ? 'सेटिंग्स खोलें' : 'Open Settings',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onUploadInstead,
                icon: const Icon(
                  Icons.upload_file_rounded,
                  color: Color(0xFFD4A843),
                  size: 20,
                ),
                label: Text(
                  isHindi ? 'फोटो अपलोड करें' : 'Upload a photo instead',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFD4A843),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionChip extends StatelessWidget {
  final String text;
  final bool secondary;
  final bool isWarning;

  const _InstructionChip({
    required this.text,
    this.secondary = false,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isWarning
        ? const Color(0xFFD4A843).withAlpha(180)
        : secondary
        ? Colors.white.withAlpha(30)
        : const Color(0xFFE8650A).withAlpha(80);
    final Color bgColor = isWarning
        ? const Color(0xFFD4A843).withAlpha(30)
        : secondary
        ? Colors.black.withAlpha(100)
        : Colors.black.withAlpha(160);
    final Color textColor = isWarning
        ? const Color(0xFFD4A843)
        : secondary
        ? Colors.white60
        : Colors.white;
    final FontWeight fontWeight = isWarning
        ? FontWeight.w600
        : secondary
        ? FontWeight.w400
        : FontWeight.w500;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isWarning) ...[
            Icon(Icons.rotate_left_rounded, color: textColor, size: 15),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: textColor,
                fontWeight: fontWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 3: Scanning View (animated scan in progress)
// ══════════════════════════════════════════════════════════════════════════════

class _ScanningView extends StatelessWidget {
  final bool isHindi;
  final String handSide;
  final CameraController? cameraController;
  final Animation<double> scanLineAnim;

  const _ScanningView({
    super.key,
    required this.isHindi,
    required this.handSide,
    required this.cameraController,
    required this.scanLineAnim,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera background
        _buildCameraBackground(),

        // Animated palm guide with scan line
        const PalmGuideOverlayWidget(
          animationState: ScanAnimationState.scanning,
        ),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFE8650A).withAlpha(120),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE8650A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isHindi ? 'स्कैनिंग...' : 'Scanning...',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE8650A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom instruction
        Positioned(
          bottom: 40 + bottomPadding,
          left: 24,
          right: 24,
          child: Column(
            children: [
              _InstructionChip(
                text: isHindi
                    ? 'हाथ को स्थिर रखें...'
                    : 'Keep your hand steady...',
              ),
              const SizedBox(height: 8),
              _InstructionChip(
                text: isHindi
                    ? 'हथेली की रेखाएं पढ़ी जा रही हैं'
                    : 'Reading palm lines...',
                secondary: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraBackground() {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [Color(0xFF1A0F05), Color(0xFF0A0603)],
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: cameraController!.value.previewSize?.height ?? 1,
          height: cameraController!.value.previewSize?.width ?? 1,
          child: CameraPreview(cameraController!),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 4: Analyzing View
// ══════════════════════════════════════════════════════════════════════════════

class _AnalyzingView extends StatefulWidget {
  final bool isHindi;
  final PalmAnalysisStage stage;

  const _AnalyzingView({super.key, required this.isHindi, required this.stage});

  @override
  State<_AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<_AnalyzingView>
    with TickerProviderStateMixin {
  late AnimationController _rotateController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String _stageLabel() {
    final isHindi = widget.isHindi;
    switch (widget.stage) {
      case PalmAnalysisStage.uploadingImage:
        return isHindi ? 'छवि अपलोड हो रही है...' : 'Preparing scan...';
      case PalmAnalysisStage.checkingQuality:
        return isHindi ? 'गुणवत्ता जांच हो रही है...' : 'Scanning palm...';
      case PalmAnalysisStage.extractingFeatures:
        return isHindi
            ? 'हथेली की विशेषताएं निकाली जा रही हैं...'
            : 'Analyzing palm...';
      case PalmAnalysisStage.generatingReading:
        return isHindi
            ? 'भविष्यवाणी तैयार हो रही है...'
            : 'Generating reading...';
      case PalmAnalysisStage.complete:
        return isHindi ? 'स्कैन पूर्ण!' : 'Scan complete!';
      default:
        return isHindi ? 'विश्लेषण हो रहा है...' : 'Analyzing...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHindi = widget.isHindi;
    final stageLabel = _stageLabel();

    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Spinning ring + palm icon
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _rotateController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotateController.value * 2 * 3.14159,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE8650A).withAlpha(60),
                          width: 2,
                        ),
                        gradient: SweepGradient(
                          colors: [
                            const Color(0xFFE8650A).withAlpha(0),
                            const Color(0xFFE8650A),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) =>
                        Transform.scale(scale: _pulseAnim.value, child: child),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE8650A).withAlpha(20),
                      ),
                      child: const Icon(
                        Icons.back_hand_rounded,
                        color: Color(0xFFE8650A),
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                isHindi ? 'आपकी हथेली पढ़ी जा रही है' : 'Reading Your Palm',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  stageLabel,
                  key: ValueKey(stageLabel),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    color: const Color(0xFFD4A843),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Stage progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: PalmAnalysisStage.values
                    .where(
                      (s) =>
                          s != PalmAnalysisStage.idle &&
                          s != PalmAnalysisStage.failed &&
                          s != PalmAnalysisStage.complete,
                    )
                    .map((s) {
                      final isActive = s == widget.stage;
                      final isPast = s.index < widget.stage.index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFE8650A)
                              : isPast
                              ? const Color(0xFFD4A843)
                              : Colors.white.withAlpha(50),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    })
                    .toList(),
              ),
              const SizedBox(height: 40),
              Text(
                isHindi
                    ? 'कृपया प्रतीक्षा करें...'
                    : 'Please wait, this may take a moment',
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 5: Complete View
// ══════════════════════════════════════════════════════════════════════════════

class _CompleteView extends StatelessWidget {
  final bool isHindi;
  final Animation<double> successAnim;

  const _CompleteView({
    super.key,
    required this.isHindi,
    required this.successAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: ScaleTransition(
          scale: successAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CAF50).withAlpha(220),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withAlpha(80),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isHindi ? '✓ हस्त स्कैन पूर्ण' : '✓ Palm Scan Complete',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isHindi
                    ? 'आपकी हथेली का विश्लेषण तैयार है'
                    : 'Your palm reading is ready',
                style: GoogleFonts.outfit(fontSize: 15, color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Error View
// ══════════════════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final bool isHindi;
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  /// A quota failure is not a scan failure — retrying cannot help, so the
  /// primary action becomes the upgrade path instead of "Try Again".
  final bool showUpgrade;
  final VoidCallback onUpgrade;

  /// The specific reason the scan failed. Drives the headline, the explanation
  /// and the correction tips — a capture problem tells the user what to change
  /// instead of showing a blanket "Scan Failed".
  final PalmFailureCopy copy;

  /// True when the user can fix this by re-taking the photo.
  final bool isCaptureProblem;

  const _ErrorView({
    super.key,
    required this.isHindi,
    required this.message,
    required this.onRetry,
    required this.onBack,
    this.showUpgrade = false,
    required this.onUpgrade,
    required this.copy,
    this.isCaptureProblem = false,
  });

  @override
  Widget build(BuildContext context) {
    // A capture problem is guidance, not an error: an amber camera icon reads
    // as "adjust and retry" where a red cross reads as "something broke".
    final accent = isCaptureProblem
        ? const Color(0xFFD4A843)
        : Colors.redAccent;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical -
                  48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withAlpha(30),
                  ),
                  child: Icon(
                    isCaptureProblem
                        ? Icons.back_hand_outlined
                        : Icons.error_outline_rounded,
                    color: accent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  copy.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  copy.message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white60,
                    height: 1.5,
                  ),
                ),
                if (copy.tips.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final tip in copy.tips)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: accent.withAlpha(200),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tip,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onBack,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          isHindi ? 'वापस जाएं' : 'Go Back',
                          style: GoogleFonts.outfit(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: showUpgrade ? onUpgrade : onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4A843),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          showUpgrade
                              ? (isHindi ? 'प्रीमियम देखें' : 'View Premium')
                              : (isHindi ? 'फिर से स्कैन करें' : 'Scan Again'),
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
