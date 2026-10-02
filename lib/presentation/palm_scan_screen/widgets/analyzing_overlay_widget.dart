import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

class AnalyzingOverlayWidget extends StatefulWidget {
  final String language;

  const AnalyzingOverlayWidget({super.key, required this.language});

  @override
  State<AnalyzingOverlayWidget> createState() => _AnalyzingOverlayWidgetState();
}

class _AnalyzingOverlayWidgetState extends State<AnalyzingOverlayWidget>
    with TickerProviderStateMixin {
  late AnimationController _rotateController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  int _stepIndex = 0;

  final List<String> _stepsEn = [
    'Detecting palm lines...',
    'Analyzing heart line...',
    'Reading fate line...',
    'Calculating predictions...',
  ];

  final List<String> _stepsHi = [
    'हथेली की रेखाएं पहचान रहे हैं...',
    'हृदय रेखा का विश्लेषण...',
    'भाग्य रेखा पढ़ रहे हैं...',
    'भविष्यवाणी तैयार हो रही है...',
  ];

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

    _cycleSteps();
  }

  void _cycleSteps() async {
    for (int i = 0; i < 4; i++) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _stepIndex = i);
    }
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.language == 'EN' ? _stepsEn : _stepsHi;

    return Container(
      color: Colors.black.withAlpha(191),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Spinning ring
            AnimatedBuilder(
              animation: _rotateController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotateController.value * 2 * math.pi,
                  child: child,
                );
              },
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE8650A), width: 3),
                  gradient: SweepGradient(
                    colors: [
                      const Color(0xFFE8650A).withAlpha(0),
                      const Color(0xFFE8650A),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Pulsing palm icon
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                return Transform.scale(scale: _pulseAnim.value, child: child);
              },
              child: const Icon(
                Icons.back_hand,
                color: Color(0xFFE8650A),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.language == 'EN'
                  ? 'Reading Your Palm...'
                  : 'आपकी हथेली पढ़ी जा रही है...',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                steps[_stepIndex.clamp(0, steps.length - 1)],
                key: ValueKey(_stepIndex),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.white.withAlpha(179),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Progress dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _stepIndex == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _stepIndex == i
                        ? const Color(0xFFE8650A)
                        : Colors.white.withAlpha(77),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
