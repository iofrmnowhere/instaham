import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_scope.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../domain/use_cases/compute_scale_use_case.dart';

/// The rectangle, in the coordinates of a `widgetSize`-sized box, that `BoxFit.contain`
/// actually paints an `imageWidthPx x imageHeightPx` image into. A pure top-level function
/// (rather than a private method) so TASKS.md W0's letterbox math is unit-testable without
/// pumping the whole screen. Returns null when either dimension is unknown or non-positive
/// -- callers must refuse to place a pin rather than fall back to the full widget box
/// (AGENTS.md rule 9).
Rect? computeContainedImageRect({
  required Size widgetSize,
  required int? imageWidthPx,
  required int? imageHeightPx,
}) {
  if (imageWidthPx == null ||
      imageHeightPx == null ||
      imageWidthPx <= 0 ||
      imageHeightPx <= 0 ||
      widgetSize.width <= 0 ||
      widgetSize.height <= 0) {
    return null;
  }
  final imageAspect = imageWidthPx / imageHeightPx;
  final widgetAspect = widgetSize.width / widgetSize.height;
  double displayWidth;
  double displayHeight;
  if (imageAspect > widgetAspect) {
    // Image is relatively wider than the widget -- letterboxed top/bottom.
    displayWidth = widgetSize.width;
    displayHeight = displayWidth / imageAspect;
  } else {
    // Image is relatively taller than the widget -- letterboxed left/right.
    displayHeight = widgetSize.height;
    displayWidth = displayHeight * imageAspect;
  }
  final left = (widgetSize.width - displayWidth) / 2;
  final top = (widgetSize.height - displayHeight) / 2;
  return Rect.fromLTWH(left, top, displayWidth, displayHeight);
}

class ReferenceMarkingScreen extends StatefulWidget {
  final ScanFlowArgs args;

  const ReferenceMarkingScreen({super.key, this.args = const ScanFlowArgs()});

  @override
  State<ReferenceMarkingScreen> createState() => _ReferenceMarkingScreenState();
}

class _ReferenceMarkingScreenState extends State<ReferenceMarkingScreen> {
  late ReferenceSelection _reference =
      widget.args.reference ?? ReferenceSelection.meterStick;
  late List<Offset> _pins = widget.args.suggestion == null
      ? <Offset>[]
      : <Offset>[
          Offset(
            widget.args.suggestion!.startX,
            widget.args.suggestion!.startY,
          ),
          Offset(widget.args.suggestion!.endX, widget.args.suggestion!.endY),
        ];
  bool _sameFloorPlane = false;
  bool _saving = false;
  String? _error;

  bool get _hasSuggestion => widget.args.suggestion != null;

  /// Whether the source image's pixel dimensions are known. Pin placement is refused
  /// without them (AGENTS.md rule 9) rather than accepted and silently producing a null
  /// scale at save time.
  bool get _hasImageDimensions =>
      widget.args.imageWidthPx != null && widget.args.imageHeightPx != null;

  /// The rectangle, in widget-local coordinates, that `BoxFit.contain` actually paints the
  /// photo into for a widget of size `widgetSize`. `_pins` are stored as fractions of THIS
  /// rect, not of `widgetSize` -- with `BoxFit.contain` the two differ by the letterbox
  /// whenever the image and widget aspect ratios don't match (AGENTS.md rule 9). Returns
  /// null when the image dimensions aren't known yet.
  Rect? _imageRectFor(Size widgetSize) => computeContainedImageRect(
    widgetSize: widgetSize,
    imageWidthPx: widget.args.imageWidthPx,
    imageHeightPx: widget.args.imageHeightPx,
  );

  void _placePin(TapUpDetails details, Size size) {
    if (_pins.length >= 2) return;
    final rect = _imageRectFor(size);
    if (rect == null) {
      setState(
        () => _error =
            'Photo dimensions are unavailable; return to the camera and retake the photo.',
      );
      return;
    }
    if (!rect.contains(details.localPosition)) {
      // Outside the displayed photo (in the letterbox) -- ignored, not clamped to the
      // edge, so a stray tap can never fabricate an endpoint (AGENTS.md rule 9).
      return;
    }
    setState(() {
      _pins.add(
        Offset(
          ((details.localPosition.dx - rect.left) / rect.width).clamp(0.0, 1.0),
          ((details.localPosition.dy - rect.top) / rect.height).clamp(0.0, 1.0),
        ),
      );
      _error = null;
    });
  }

  void _movePin(int index, DragUpdateDetails details, Size size) {
    final rect = _imageRectFor(size);
    if (rect == null) return;
    setState(() {
      final current = _pins[index];
      _pins[index] = Offset(
        (current.dx + details.delta.dx / rect.width).clamp(0.0, 1.0),
        (current.dy + details.delta.dy / rect.height).clamp(0.0, 1.0),
      );
      _error = null;
    });
  }

  double? get _originalPixelLength {
    if (_pins.length != 2 ||
        widget.args.imageWidthPx == null ||
        widget.args.imageHeightPx == null) {
      return null;
    }
    final dx = (_pins[1].dx - _pins[0].dx) * widget.args.imageWidthPx!;
    final dy = (_pins[1].dy - _pins[0].dy) * widget.args.imageHeightPx!;
    return sqrt(dx * dx + dy * dy);
  }

  Future<void> _editReference() async {
    final nameController = TextEditingController(text: _reference.name);
    final lengthController = TextEditingController(
      text: _reference.lengthCm.toStringAsFixed(0),
    );
    String type = _reference.type;

    final updated = await showDialog<ReferenceSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change reference'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Reference type',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'meter_stick',
                      child: Text('1-meter stick'),
                    ),
                    DropdownMenuItem(
                      value: 'porac_stick',
                      child: Text('Porac stick'),
                    ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text('Custom reference'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      type = value;
                      if (value == 'meter_stick') {
                        nameController.text = '1-meter stick';
                        lengthController.text = '100';
                      } else if (value == 'porac_stick') {
                        nameController.text = 'Porac stick';
                        lengthController.text = '131';
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lengthController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Known length',
                    suffixText: 'cm',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final length = double.tryParse(lengthController.text.trim());
                if (length == null || !length.isFinite || length <= 0) return;
                Navigator.pop(
                  dialogContext,
                  ReferenceSelection(
                    type: type,
                    name: nameController.text.trim().isEmpty
                        ? 'Custom reference'
                        : nameController.text.trim(),
                    lengthCm: length,
                  ),
                );
              },
              child: const Text('Use reference'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    lengthController.dispose();
    if (updated != null && mounted) setState(() => _reference = updated);
  }

  Future<void> _confirm() async {
    if (_pins.length != 2) {
      setState(
        () => _error = 'Place exactly two points on the visible endpoints.',
      );
      return;
    }
    if (!_sameFloorPlane) {
      setState(
        () => _error =
            'Confirm that the reference is flat on the same floor plane as the pig.',
      );
      return;
    }

    final displayDistance = (_pins[1] - _pins[0]).distance;
    if (displayDistance < 0.03) {
      setState(() => _error = 'The endpoints are too close together.');
      return;
    }

    final sessionId = widget.args.sessionId;
    if (sessionId == null) {
      setState(
        () => _error =
            'This scan session is missing. Return to the camera and try again.',
      );
      return;
    }

    setState(() => _saving = true);
    final database = DatabaseScope.of(context);
    final pixelLength = _originalPixelLength;
    final cmPerPixel = _computeScale(pixelLength);
    await database.saveReferenceAnnotation(
      scanId: sessionId,
      reference: _reference,
      startX: _pins[0].dx,
      startY: _pins[0].dy,
      endX: _pins[1].dx,
      endY: _pins[1].dy,
      pixelLength: pixelLength,
      cmPerPixel: cmPerPixel,
      source: _hasSuggestion ? 'automatic_adjusted' : 'manual',
      detectorConfidence: widget.args.suggestion?.confidence,
      sameFloorPlaneConfirmed: _sameFloorPlane,
    );
    await database.addPipelineEvent(
      sessionId,
      'analysis',
      'queued',
      message: pixelLength == null
          ? 'Reference confirmed; original image dimensions are required before scale calculation.'
          : 'Reference confirmed by user.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    context.push(
      '/analysis',
      extra: widget.args.copyWith(reference: _reference),
    );
  }

  /// Wraps `ComputeScaleUseCase` -- returns null (rather than throwing) whenever
  /// `pixelLength` isn't a valid positive distance, since a screen mid-edit routinely has
  /// zero or one pins placed.
  double? _computeScale(double? pixelLength) {
    if (pixelLength == null || pixelLength <= 0) return null;
    return const ComputeScaleUseCase().execute(
      referenceLengthCm: _reference.lengthCm,
      referencePixelLength: pixelLength,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pixelLength = _originalPixelLength;
    final scale = _computeScale(pixelLength);

    return AppScaffold(
      showNav: false,
      header: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                'Verify reference',
                style: AppTextStyles.headline.copyWith(fontSize: 20),
              ),
            ),
            TextButton(onPressed: _editReference, child: const Text('Change')),
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: _hasSuggestion ? AppColors.pinkTint : Colors.blue.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _hasSuggestion
                      ? Icons.auto_awesome
                      : Icons.touch_app_outlined,
                  size: 18,
                  color: _hasSuggestion
                      ? AppColors.signalPink
                      : Colors.blue.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !_hasImageDimensions
                        ? 'Photo dimensions unavailable — return to the camera and retake the photo'
                        : _hasSuggestion
                        ? 'Suggested endpoints — review before continuing'
                        : 'Automatic detection unavailable — mark both endpoints manually',
                    style: AppTextStyles.label.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  // The rect BoxFit.contain actually paints the photo into -- pins are
                  // stored as fractions of THIS rect (AGENTS.md rule 9), so every render
                  // maps back through it rather than through the raw widget size.
                  final imageRect = _imageRectFor(size);
                  Offset toWidgetSpace(Offset fraction) {
                    if (imageRect == null) return Offset.zero;
                    return Offset(
                      imageRect.left + fraction.dx * imageRect.width,
                      imageRect.top + fraction.dy * imageRect.height,
                    );
                  }

                  return GestureDetector(
                    key: const Key('referencePhotoArea'),
                    onTapUp: (details) => _placePin(details, size),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ReferencePhoto(
                            path: widget.args.imagePath,
                            bytes: widget.args.imageBytes,
                          ),
                          if (_pins.length == 2)
                            CustomPaint(
                              painter: _ReferenceLinePainter(
                                start: toWidgetSpace(_pins[0]),
                                end: toWidgetSpace(_pins[1]),
                              ),
                            ),
                          ..._pins.asMap().entries.map((entry) {
                            final point = toWidgetSpace(entry.value);
                            return Positioned(
                              left: point.dx - 22,
                              top: point.dy - 22,
                              child: GestureDetector(
                                onPanUpdate: (details) =>
                                    _movePin(entry.key, details, size),
                                // ref_fix.md F5: the touch target stays 44x44 (AGENTS.md's
                                // minimum), but what's PAINTED shrank from an opaque disc to
                                // a small crosshair -- the old disc hid the exact point it
                                // was marking, which made fine placement on a stick's
                                // endpoint harder than it needed to be. The number badge
                                // moves to a corner so it never covers the mark either.
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Positioned.fill(
                                        child: CustomPaint(
                                          painter: _CrosshairPainter(),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.signalPink,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Text(
                                            '${entry.key + 1}',
                                            style: AppTextStyles.label.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.straighten, color: AppColors.signalPink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_reference.name} · ${_reference.lengthCm.toStringAsFixed(1)} cm',
                              style: AppTextStyles.label.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              scale == null
                                  ? 'Scale will use the original image dimensions during analysis.'
                                  : '${_reference.lengthCm.toStringAsFixed(1)} cm / ${pixelLength!.round()} px = ${scale.toStringAsFixed(4)} cm/px',
                              style: AppTextStyles.subtext.copyWith(
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _sameFloorPlane,
                    activeColor: AppColors.signalPink,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setState(() => _sameFloorPlane = value ?? false),
                    title: Text(
                      'Reference is flat on the same floor plane as the pig',
                      style: AppTextStyles.label,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: AppTextStyles.subtext.copyWith(
                        color: AppColors.destructive,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _pins = _hasSuggestion
                              ? [
                                  Offset(
                                    widget.args.suggestion!.startX,
                                    widget.args.suggestion!.startY,
                                  ),
                                  Offset(
                                    widget.args.suggestion!.endX,
                                    widget.args.suggestion!.endY,
                                  ),
                                ]
                              : [];
                          _error = null;
                        }),
                        child: Text(
                          _hasSuggestion ? 'Reset suggestion' : 'Clear points',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _confirm,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Confirm & analyze'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferencePhoto extends StatelessWidget {
  final String? path;
  final Uint8List? bytes;

  const _ReferencePhoto({this.path, this.bytes});

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(bytes!, fit: BoxFit.contain);
    }
    if (!kIsWeb && path != null && File(path!).existsSync()) {
      return Image.file(File(path!), fit: BoxFit.contain);
    }
    return ColoredBox(
      color: const Color(0xFF252525),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_outlined, size: 48, color: Colors.white54),
            const SizedBox(height: 8),
            Text(
              'Captured photo',
              style: AppTextStyles.label.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// ref_fix.md F5: a small ring-and-cross marking the exact recorded point, rather than the
/// opaque 44x44 disc that previously covered it -- painted twice, a wide white halo then a
/// narrower pink mark, so it reads against any photo background.
class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  static const double _ringRadius = 7;
  static const double _armLength = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    void drawCrosshair(Paint paint) {
      canvas.drawCircle(center, _ringRadius, paint);
      canvas.drawLine(
        center + const Offset(-_ringRadius - _armLength, 0),
        center + const Offset(-_ringRadius, 0),
        paint,
      );
      canvas.drawLine(
        center + const Offset(_ringRadius, 0),
        center + const Offset(_ringRadius + _armLength, 0),
        paint,
      );
      canvas.drawLine(
        center + const Offset(0, -_ringRadius - _armLength),
        center + const Offset(0, -_ringRadius),
        paint,
      );
      canvas.drawLine(
        center + const Offset(0, _ringRadius),
        center + const Offset(0, _ringRadius + _armLength),
        paint,
      );
    }

    drawCrosshair(
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    drawCrosshair(
      Paint()
        ..color = AppColors.signalPink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}

class _ReferenceLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _ReferenceLinePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.signalPink
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _ReferenceLinePainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
