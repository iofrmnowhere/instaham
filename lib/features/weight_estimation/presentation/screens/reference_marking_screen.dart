import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_scope.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_card.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';

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

  void _placePin(TapUpDetails details, Size size) {
    if (_pins.length >= 2) return;
    setState(() {
      _pins.add(
        Offset(
          (details.localPosition.dx / size.width).clamp(0.0, 1.0),
          (details.localPosition.dy / size.height).clamp(0.0, 1.0),
        ),
      );
      _error = null;
    });
  }

  void _movePin(int index, DragUpdateDetails details, Size size) {
    setState(() {
      final current = _pins[index];
      _pins[index] = Offset(
        (current.dx + details.delta.dx / size.width).clamp(0.0, 1.0),
        (current.dy + details.delta.dy / size.height).clamp(0.0, 1.0),
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
    final cmPerPixel = pixelLength == null || pixelLength <= 0
        ? null
        : _reference.lengthCm / pixelLength;
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

  Future<void> _continueHealthOnly() async {
    final sessionId = widget.args.sessionId;
    if (sessionId == null) return;
    final database = DatabaseScope.of(context);
    await database.updateScanGoal(sessionId, ScanGoal.healthOnly);
    await database.updateScanStatus(sessionId, ScanStatuses.analyzing);
    await database.addPipelineEvent(
      sessionId,
      'reference_review',
      'skipped',
      message: 'User continued with visual health assessment only.',
    );
    if (mounted) {
      context.push(
        '/analysis',
        extra: widget.args.copyWith(
          goal: ScanGoal.healthOnly,
          clearReference: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixelLength = _originalPixelLength;
    final scale = pixelLength == null || pixelLength <= 0
        ? null
        : _reference.lengthCm / pixelLength;

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
                    _hasSuggestion
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
                  return GestureDetector(
                    onTapUp: (details) => _placePin(details, size),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ReferencePhoto(path: widget.args.imagePath),
                          if (_pins.length == 2)
                            CustomPaint(
                              painter: _ReferenceLinePainter(
                                start: Offset(
                                  _pins[0].dx * size.width,
                                  _pins[0].dy * size.height,
                                ),
                                end: Offset(
                                  _pins[1].dx * size.width,
                                  _pins[1].dy * size.height,
                                ),
                              ),
                            ),
                          ..._pins.asMap().entries.map((entry) {
                            final point = entry.value;
                            return Positioned(
                              left: point.dx * size.width - 22,
                              top: point.dy * size.height - 22,
                              child: GestureDetector(
                                onPanUpdate: (details) =>
                                    _movePin(entry.key, details, size),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.signalPink,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: AppTextStyles.label.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
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
                CheckboxListTile(
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
                TextButton(
                  onPressed: _continueHealthOnly,
                  child: const Text(
                    'Skip weight and continue with health only',
                  ),
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

  const _ReferencePhoto({this.path});

  @override
  Widget build(BuildContext context) {
    if (path != null && File(path!).existsSync()) {
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
