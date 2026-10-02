import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../widgets/custom_icon_widget.dart';

class CaptureBarWidget extends StatelessWidget {
  final VoidCallback onCapture;
  final String language;

  const CaptureBarWidget({
    super.key,
    required this.onCapture,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 32,
        right: 32,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 100,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withAlpha(179)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Text(
            language == 'EN'
                ? 'Hold still for best results'
                : 'सर्वोत्तम परिणाम के लिए स्थिर रहें',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white.withAlpha(179),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gallery
              GestureDetector(
                onTap: () {
                  // TODO: Implement gallery picker with image_picker
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(38),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(77)),
                  ),
                  child: const CustomIconWidget(
                    iconName: 'photo_library_outlined',
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              // Shutter
              GestureDetector(
                onTap: onCapture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE8650A),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE8650A).withAlpha(128),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const CustomIconWidget(
                        iconName: 'back_hand',
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              // Flash toggle
              GestureDetector(
                onTap: () {
                  // TODO: Toggle flash on mobile
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(38),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(77)),
                  ),
                  child: const CustomIconWidget(
                    iconName: 'flash_auto',
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
