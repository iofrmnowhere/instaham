import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../widgets/reference_object_details.dart';
import '../widgets/reference_object_picker.dart';

class CaptureScreen extends StatefulWidget {
  final ScanFlowArgs? initialArgs;

  const CaptureScreen({super.key, this.initialArgs});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late ScanGoal _goal = widget.initialArgs?.goal ?? ScanGoal.weightAndHealth;
  late ReferenceSelection? _reference = widget.initialArgs?.reference;
  String? _sessionId;
  AppDatabase? _database;
  bool _initialized = false;
  bool _reviewingPhoto = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _database = DatabaseScope.of(context);
    _sessionId = widget.initialArgs?.sessionId;
    if (_sessionId == null) {
      _createSession();
    }
  }

  Future<String> _createSession() async {
    final id = await _database!.createDraftScan(goal: _goal);
    if (mounted) setState(() => _sessionId = id);
    return id;
  }

  Future<String> _ensureSession() async => _sessionId ?? _createSession();

  Future<void> _changeGoal(ScanGoal goal) async {
    setState(() => _goal = goal);
    final id = await _ensureSession();
    await _database!.updateScanGoal(id, goal);
  }

  Future<void> _showReferencePicker() async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ReferenceObjectPicker(
        onSelect: (selection) => Navigator.pop(sheetContext, selection),
        onCustom: () => Navigator.pop(sheetContext, 'custom'),
        onBack: () => Navigator.pop(sheetContext),
      ),
    );
    if (!mounted) return;
    if (result == 'custom') {
      await _showCustomReference();
    } else if (result is ReferenceSelection) {
      setState(() => _reference = result);
    }
  }

  Future<void> _showCustomReference() async {
    final selection = await showModalBottomSheet<ReferenceSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ReferenceObjectDetails(
          onConfirm: (value) => Navigator.pop(sheetContext, value),
          onBack: () => Navigator.pop(sheetContext),
        ),
      ),
    );
    if (selection != null && mounted) {
      setState(() => _reference = selection);
    }
  }

  void _showGuidance() {
    final tips = _goal == ScanGoal.weightAndHealth
        ? const [
            'Photograph one pig from directly above.',
            'Keep the full head, body, and tail inside the frame.',
            'Place the straight reference flat beside the pig.',
            'Keep both reference endpoints visible.',
            'Hold the phone parallel to the ground.',
          ]
        : const [
            'Fill the frame with the visibly affected area.',
            'Keep enough pig context visible for screening.',
            'Use even lighting and avoid motion blur.',
          ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_goal.label} capture',
                style: AppTextStyles.headline.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 12),
              ...tips.map(
                (tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tip, style: AppTextStyles.body)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _capture() async {
    if (_goal.requiresReference && _reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the known reference object before capturing.'),
        ),
      );
      await _showReferencePicker();
      return;
    }
    setState(() => _saving = true);
    final id = await _ensureSession();
    await _database!.markCaptured(id, imagePath: widget.initialArgs?.imagePath);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _reviewingPhoto = true;
    });
  }

  Future<void> _usePhoto() async {
    final id = await _ensureSession();
    final args = ScanFlowArgs(
      sessionId: id,
      goal: _goal,
      reference: _reference,
      imagePath: widget.initialArgs?.imagePath,
      imageWidthPx: widget.initialArgs?.imageWidthPx,
      imageHeightPx: widget.initialArgs?.imageHeightPx,
      suggestion: widget.initialArgs?.suggestion,
    );
    if (!mounted) return;
    if (_goal.requiresReference) {
      await _database!.updateScanStatus(id, ScanStatuses.referenceReview);
      if (mounted) context.push('/reference-marking', extra: args);
    } else {
      await _database!.updateScanStatus(id, ScanStatuses.analyzing);
      await _database!.addPipelineEvent(
        id,
        'analysis',
        'queued',
        message: 'Awaiting health model integration.',
      );
      if (mounted) context.push('/analysis', extra: args);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showNav: false,
      child: _reviewingPhoto ? _buildReview() : _buildCamera(),
    );
  }

  Widget _buildCamera() {
    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          Container(
            color: Colors.black.withValues(alpha: 0.78),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close camera',
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                Expanded(
                  child: _ModeSelector(selected: _goal, onChanged: _changeGoal),
                ),
                IconButton(
                  tooltip: 'Capture tips',
                  onPressed: _showGuidance,
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFF171717),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 56,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Live camera preview',
                        style: AppTextStyles.subtext.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_goal.requiresReference)
                  CustomPaint(painter: _DorsalGuidePainter())
                else
                  Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white54, width: 2),
                        borderRadius: BorderRadius.circular(AppRadius.x2l),
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 14,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_goal.requiresReference)
                        ActionChip(
                          avatar: Icon(
                            _reference == null
                                ? Icons.warning_amber
                                : Icons.straighten,
                            size: 17,
                            color: _reference == null
                                ? AppColors.blocked
                                : AppColors.signalPink,
                          ),
                          label: Text(
                            _reference == null
                                ? 'Set reference'
                                : '${_reference!.name} · ${_reference!.lengthCm.toStringAsFixed(0)} cm',
                          ),
                          onPressed: _showReferencePicker,
                          backgroundColor: Colors.white,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Text(
                      _goal.requiresReference
                          ? 'One pig · dorsal view · full body and reference visible'
                          : 'Keep the affected area sharp and well lit',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.label.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: IconButton(
                    tooltip: 'Capture tips',
                    onPressed: _showGuidance,
                    icon: const Icon(
                      Icons.tips_and_updates_outlined,
                      color: Colors.white70,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'Take photo',
                      child: GestureDetector(
                        onTap: _saving ? null : _capture,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _saving ? Colors.white54 : Colors.white,
                            ),
                            child: _saving
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: _goal.requiresReference
                      ? IconButton(
                          tooltip: 'Change reference',
                          onPressed: _showReferencePicker,
                          icon: const Icon(
                            Icons.straighten,
                            color: Colors.white70,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReview() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _reviewingPhoto = false),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Review photo',
                style: AppTextStyles.headline.copyWith(fontSize: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF202020),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.photo_camera_back_outlined,
                  size: 56,
                  color: Colors.white54,
                ),
                const SizedBox(height: 8),
                Text(
                  'Captured photo preview',
                  style: AppTextStyles.label.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.signalPink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _goal.requiresReference
                          ? 'Next, verify the app suggestion or mark both reference endpoints manually.'
                          : 'Use this photo only if the affected area is clear and in focus.',
                      style: AppTextStyles.subtext.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _reviewingPhoto = false),
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _usePhoto,
                      child: Text(
                        _goal.requiresReference
                            ? 'Verify reference'
                            : 'Use photo',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final ScanGoal selected;
  final ValueChanged<ScanGoal> onChanged;

  const _ModeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: ScanGoal.values.map((goal) {
          final active = goal == selected;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(goal),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  goal.label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.foreground : Colors.white70,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DorsalGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final bodyRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.48,
      height: size.height * 0.58,
    );
    canvas.drawOval(bodyRect, paint);
    canvas.drawCircle(Offset(size.width / 2, bodyRect.top - 20), 34, paint);
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.25),
      Offset(size.width * 0.2, size.height * 0.75),
      paint,
    );
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.25), 8, paint);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.75), 8, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
