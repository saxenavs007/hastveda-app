import 'package:flutter/material.dart';
import 'dart:math' as math;

enum ScanAnimationState { idle, scanning, complete }

class PalmGuideOverlayWidget extends StatefulWidget {
  final ScanAnimationState animationState;
  final String? instructionText;

  const PalmGuideOverlayWidget({
    super.key,
    this.animationState = ScanAnimationState.idle,
    this.instructionText,
  });

  @override
  State<PalmGuideOverlayWidget> createState() => _PalmGuideOverlayWidgetState();
}

class _PalmGuideOverlayWidgetState extends State<PalmGuideOverlayWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  late AnimationController _gridController;
  late Animation<double> _pulseAnim;
  late Animation<double> _scanLineAnim;
  late Animation<double> _gridAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _gridController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );
    _gridAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _gridController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PalmGuideOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationState == ScanAnimationState.scanning) {
      _scanLineController.repeat();
      _gridController.repeat(reverse: true);
    } else if (widget.animationState == ScanAnimationState.complete) {
      _scanLineController.stop();
      _gridController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanLineController.dispose();
    _gridController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final guideW = size.width * 0.72;
    final guideH = guideW * 1.2;
    final centerX = size.width / 2;
    final centerY = size.height * 0.42;
    final guideTop = centerY - guideH / 2;
    final guideLeft = centerX - guideW / 2;

    final isScanning = widget.animationState == ScanAnimationState.scanning;
    final isComplete = widget.animationState == ScanAnimationState.complete;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Dim overlay with cutout
        CustomPaint(
          painter: _DimOverlayPainter(
            guideW: guideW,
            guideH: guideH,
            center: Offset(centerX, centerY),
          ),
        ),

        // Palm outline (pulsing)
        Positioned(
          top: guideTop,
          left: guideLeft,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Transform.scale(scale: _pulseAnim.value, child: child);
            },
            child: SizedBox(
              width: guideW,
              height: guideH,
              child: CustomPaint(
                painter: _PalmOutlinePainter(
                  isScanning: isScanning,
                  isComplete: isComplete,
                ),
              ),
            ),
          ),
        ),

        // Corner brackets
        Positioned(
          top: guideTop - 2,
          left: guideLeft - 2,
          child: SizedBox(
            width: guideW + 4,
            height: guideH + 4,
            child: CustomPaint(
              painter: _CornerBracketsPainter(
                color: isComplete
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFE8650A),
              ),
            ),
          ),
        ),

        // Scanning line (only when scanning)
        if (isScanning)
          Positioned(
            top: guideTop,
            left: guideLeft,
            child: ClipRect(
              child: SizedBox(
                width: guideW,
                height: guideH,
                child: AnimatedBuilder(
                  animation: _scanLineAnim,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ScanLinePainter(
                        progress: _scanLineAnim.value,
                        gridOpacity: _gridAnim.value,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

        // Complete checkmark
        if (isComplete)
          Positioned(
            top: centerY - 36,
            left: centerX - 36,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4CAF50).withAlpha(220),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
      ],
    );
  }
}

class _DimOverlayPainter extends CustomPainter {
  final double guideW;
  final double guideH;
  final Offset center;

  _DimOverlayPainter({
    required this.guideW,
    required this.guideH,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withAlpha(150);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: guideW, height: guideH),
      const Radius.circular(24),
    );
    final path = Path()
      ..addRect(rect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DimOverlayPainter old) =>
      old.guideW != guideW || old.guideH != guideH;
}

class _PalmOutlinePainter extends CustomPainter {
  final bool isScanning;
  final bool isComplete;

  _PalmOutlinePainter({required this.isScanning, required this.isComplete});

  @override
  void paint(Canvas canvas, Size size) {
    final color = isComplete
        ? const Color(0xFF4CAF50)
        : isScanning
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE8650A);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Rounded rect outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(24),
      ),
      borderPaint,
    );

    // Palm line suggestions
    final linePaint = Paint()
      ..color = color.withAlpha(80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.38;

    // Life line
    final lifePath = Path();
    lifePath.moveTo(cx - r * 0.25, cy + r * 0.6);
    lifePath.quadraticBezierTo(cx - r * 0.55, cy, cx - r * 0.2, cy - r * 0.7);
    canvas.drawPath(lifePath, linePaint);

    // Heart line
    final heartPath = Path();
    heartPath.moveTo(cx - r * 0.65, cy - r * 0.25);
    heartPath.quadraticBezierTo(
      cx,
      cy - r * 0.45,
      cx + r * 0.65,
      cy - r * 0.15,
    );
    canvas.drawPath(heartPath, linePaint);

    // Head line
    final headPath = Path();
    headPath.moveTo(cx - r * 0.65, cy + r * 0.05);
    headPath.quadraticBezierTo(cx, cy + r * 0.02, cx + r * 0.55, cy + r * 0.2);
    canvas.drawPath(headPath, linePaint);

    // Fate line
    final fatePath = Path();
    fatePath.moveTo(cx, cy + r * 0.7);
    fatePath.lineTo(cx, cy - r * 0.5);
    canvas.drawPath(fatePath, linePaint);

    // Hand silhouette hint (fingers)
    final fingerPaint = Paint()
      ..color = color.withAlpha(40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 4 finger lines at top
    for (int i = 0; i < 4; i++) {
      final fx = cx - r * 0.45 + i * r * 0.3;
      final fingerPath = Path();
      fingerPath.moveTo(fx, size.height * 0.08);
      fingerPath.lineTo(fx, size.height * 0.28);
      canvas.drawPath(fingerPath, fingerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PalmOutlinePainter old) =>
      old.isScanning != isScanning || old.isComplete != isComplete;
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  final double gridOpacity;

  _ScanLinePainter({required this.progress, required this.gridOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle grid mesh
    final gridPaint = Paint()
      ..color = const Color(0xFFE8650A).withAlpha((gridOpacity * 35).round())
      ..strokeWidth = 0.5;

    const gridSpacing = 24.0;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Glowing scan line
    final lineY = progress * size.height;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFE8650A).withAlpha(0),
          const Color(0xFFFFB74D).withAlpha(220),
          const Color(0xFFE8650A).withAlpha(0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, lineY - 20, size.width, 40))
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), scanPaint);

    // Glow below scan line
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFE8650A).withAlpha(60),
          const Color(0xFFE8650A).withAlpha(0),
        ],
      ).createShader(Rect.fromLTWH(0, lineY, size.width, 40));
    canvas.drawRect(Rect.fromLTWH(0, lineY, size.width, 40), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter old) =>
      old.progress != progress || old.gridOpacity != gridOpacity;
}

class _CornerBracketsPainter extends CustomPainter {
  final Color color;
  _CornerBracketsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const len = 22.0;
    const r = 6.0;

    // Top-left
    canvas.drawLine(Offset(0, r + len), Offset(0, r), paint);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, r * 2, r * 2),
      math.pi,
      math.pi / 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(r, 0), Offset(r + len, 0), paint);

    // Top-right
    canvas.drawLine(
      Offset(size.width - r - len, 0),
      Offset(size.width - r, 0),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2),
      -math.pi / 2,
      math.pi / 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(size.width, r), Offset(size.width, r + len), paint);

    // Bottom-left
    canvas.drawLine(
      Offset(0, size.height - r - len),
      Offset(0, size.height - r),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2),
      math.pi / 2,
      math.pi / 2,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(r, size.height),
      Offset(r + len, size.height),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - r - len, size.height),
      Offset(size.width - r, size.height),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(size.width - r * 2, size.height - r * 2, r * 2, r * 2),
      0,
      math.pi / 2,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height - r - len),
      Offset(size.width, size.height - r),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter old) =>
      old.color != color;
}
