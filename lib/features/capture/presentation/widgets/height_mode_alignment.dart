import 'package:flutter/material.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';

class HeightModeAlignment extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  const HeightModeAlignment({
    super.key,
    required this.onConfirm,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: onBack,
                  ),
                  Text(
                    'Align Camera',
                    style: AppTextStyles.headline.copyWith(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),

            // Camera preview with silhouette
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(120, 160),
                    painter: _PigSilhouettePainter(),
                  ),
                  // Alignment lines
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.25,
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  Positioned(
                    bottom: MediaQuery.of(context).size.height * 0.25,
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ],
              ),
            ),

            // Guidance & Buttons
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Position pig to match the silhouette guide',
                          style: AppTextStyles.subtext.copyWith(color: Colors.amber),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                          ),
                          child: const Text('Adjust Height'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                          ),
                          child: const Text('Capture'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PigSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Body oval
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 40, 80, 70),
        const Radius.circular(20),
      ),
      paint,
    );
    // Head circle
    canvas.drawCircle(Offset(size.width / 2, 30), 18, paint);
    // 4 legs
    canvas.drawCircle(const Offset(30, 115), 6, paint);
    canvas.drawCircle(const Offset(90, 115), 6, paint);
    canvas.drawCircle(const Offset(35, 125), 6, paint);
    canvas.drawCircle(const Offset(85, 125), 6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
