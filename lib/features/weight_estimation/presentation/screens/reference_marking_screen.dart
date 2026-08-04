import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

class DraggablePin {
  final String id;
  Offset offset;

  DraggablePin({required this.id, required this.offset});
}

class ReferenceMarkingScreen extends StatefulWidget {
  const ReferenceMarkingScreen({super.key});

  @override
  State<ReferenceMarkingScreen> createState() => _ReferenceMarkingScreenState();
}

class _ReferenceMarkingScreenState extends State<ReferenceMarkingScreen> {
  final List<DraggablePin> pins = [];

  void _handleCanvasTapDown(TapDownDetails details) {
    if (pins.length >= 2) return;
    setState(() {
      pins.add(DraggablePin(
        id: 'pin-${DateTime.now().millisecondsSinceEpoch}',
        offset: details.localPosition,
      ));
    });
  }

  void _removePin(String id) {
    setState(() {
      pins.removeWhere((p) => p.id == id);
    });
  }

  double? get pixelDistance {
    if (pins.length < 2) return null;
    final dx = pins[1].offset.dx - pins[0].offset.dx;
    final dy = pins[1].offset.dy - pins[0].offset.dy;
    return sqrt(dx * dx + dy * dy);
  }

  @override
  Widget build(BuildContext context) {
    final dist = pixelDistance;

    return AppScaffold(
      showNav: false,
      header: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => context.go('/measurements'),
            ),
            Text('Mark Reference Endpoints', style: AppTextStyles.headline.copyWith(fontSize: 18)),
          ],
        ),
      ),
      child: Column(
        children: [
          // Canvas Area
          Expanded(
            child: GestureDetector(
              onTapDown: _handleCanvasTapDown,
              child: Container(
                color: Colors.grey.shade200,
                child: Stack(
                  children: [
                    const Center(
                      child: Text(
                        'Reference Photo',
                        style: TextStyle(color: AppColors.mutedForeground),
                      ),
                    ),
                    // Dashed line painter
                    if (pins.length >= 2)
                      CustomPaint(
                        size: Size.infinite,
                        painter: _DashedLinePainter(p1: pins[0].offset, p2: pins[1].offset),
                      ),
                    // Pins
                    ...pins.asMap().entries.map((entry) {
                      final index = entry.key;
                      final pin = entry.value;
                      return Positioned(
                        left: pin.offset.dx - 16,
                        top: pin.offset.dy - 16,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              pin.offset += details.delta;
                            });
                          },
                          onTap: () => _removePin(pin.id),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.signalPink,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: AppTextStyles.label.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          // Controls & Readout
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                if (dist != null) ...[
                  AppCard(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Scale Ratio', style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground)),
                        const SizedBox(height: 2),
                        Text(
                          '${dist.round()}px → 1.00cm',
                          style: AppTextStyles.numeric.copyWith(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => pins.clear()),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: pins.length >= 2 ? () => context.push('/analysis') : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.signalPink,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  pins.isEmpty
                      ? 'Click to add 2 points on the reference object endpoints'
                      : pins.length == 1
                          ? 'Click to add the second point'
                          : 'Drag points to adjust or tap a point to remove',
                  style: AppTextStyles.subtext.copyWith(color: AppColors.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Offset p1;
  final Offset p2;

  _DashedLinePainter({required this.p1, required this.p2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.signalPink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 4.0;

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = sqrt(dx * dx + dy * dy);

    final count = (distance / (dashWidth + dashSpace)).floor();

    for (var i = 0; i < count; i++) {
      final startRatio = (i * (dashWidth + dashSpace)) / distance;
      final endRatio = (i * (dashWidth + dashSpace) + dashWidth) / distance;

      final start = Offset(p1.dx + dx * startRatio, p1.dy + dy * startRatio);
      final end = Offset(p1.dx + dx * endRatio, p1.dy + dy * endRatio);

      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.p1 != p1 || oldDelegate.p2 != p2;
  }
}
