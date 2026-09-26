import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_scope.dart';
import '../../../../core/models/capture_orientation.dart';
import '../../../../core/models/measurement_mode.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/widgets/app_scaffold.dart';
import '../../../../core/utils/captured_image_result.dart';
import '../../../../core/utils/image_service.dart';
import '../../../../core/utils/length_units.dart';
import '../../../inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart';
import '../../data/capture_preferences.dart';
import '../widgets/reference_object_picker.dart';

class CaptureScreen extends StatefulWidget {
  final ScanFlowArgs? initialArgs;

  const CaptureScreen({super.key, this.initialArgs});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  // docs/metrics-plan.md phase 4 task 5: height mode is withdrawn (finding 9) -- reference
  // object is now the only capture mode. `measurementMode` stays on ScanRecords/ScanFlowArgs
  // (AGENTS.md "Database rules": no schema change for no behavioural gain), so this is kept
  // as a constant rather than removed, to keep writing the same enum value every capture.
  static const MeasurementMode _mode = MeasurementMode.referenceObject;
  LengthUnit _unit = LengthUnit.cm;
  late ReferenceSelection? _reference = widget.initialArgs?.reference;
  String? _sessionId;
  AppDatabase? _database;
  bool _initialized = false;
  bool _reviewingPhoto = false;
  bool _saving = false;

  List<CameraDescription> _cameras = const [];
  CameraController? _cameraController;
  bool _isCameraInitializing = true;
  bool _cameraError = false;
  CapturedImageResult? _capturedResult;

  // docs/fix-phase-4/6-capture-orientation.md: the confirm step's attestation, reset to false
  // for every new capture. Never pre-ticked.
  bool _orientationAttested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isCameraInitializing = false;
            _cameraError = true;
          });
        }
        return;
      }

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _cameraController = controller;
      await controller.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraError = false;
        });
      }
    } catch (e) {
      debugPrint('CaptureScreen: Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraError = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _database = DatabaseScope.of(context);
    // plan-phase-2/2.1-capture-screen-guards.md finding 3: do not create a draft scan just
    // for opening this screen. A session is created lazily, the first time a photo actually
    // succeeds (via _ensureSession in _capture/_pickFromGallery/_usePhoto) -- a user who
    // opens the camera and leaves without capturing anything must leave no row behind.
    _sessionId = widget.initialArgs?.sessionId;
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final savedRef = await CapturePreferences.loadReference();
    final savedUnit = await CapturePreferences.loadUnit();
    if (!mounted) return;
    setState(() {
      if (_reference == null && savedRef != null) {
        _reference = savedRef;
      }
      _unit = savedUnit;
    });
  }

  void _updateUnit(LengthUnit newUnit) {
    if (_unit == newUnit) return;
    setState(() => _unit = newUnit);
    CapturePreferences.saveUnit(newUnit);
  }

  Future<String> _createSession() async {
    final id = await _database!.createDraftScan(goal: ScanGoal.weightAndHealth);
    if (mounted) setState(() => _sessionId = id);
    return id;
  }

  Future<String> _ensureSession() async => _sessionId ?? _createSession();

  Future<void> _openReferenceConfig() async {
    final result = await ReferenceObjectPicker.showAsBottomSheet(
      context,
      unit: _unit,
      onUnitChanged: _updateUnit,
    );
    if (!mounted || result == null) return;
    setState(() => _reference = result);
    await CapturePreferences.saveReference(result);
  }

  void _showGuidance() {
    const tips = [
      'Photograph one pig from directly above.',
      'Keep the full head, body, and tail inside the frame.',
      'Place the straight reference flat beside the pig.',
      'Keep both reference endpoints visible.',
      'Hold the phone parallel to the ground.',
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
                '${_mode.label} capture tips',
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
    if (_reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the known reference object before capturing.'),
        ),
      );
      await _openReferenceConfig();
      return;
    }

    setState(() => _saving = true);

    try {
      CapturedImageResult? result;

      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        final xFile = await _cameraController!.takePicture();
        result = await ImageService.processCapture(xFile);
      } else {
        // Fallback for environments without live controller (web/desktop)
        result = await ImageService.pickFromCamera();
      }

      if (result == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      // plan-phase-2/2.1-capture-screen-guards.md finding 3: nothing is written to the
      // database until the widget is confirmed still mounted -- a capture the user quits
      // out of before this point leaves no scan behind.
      if (!mounted) return;
      final id = await _ensureSession();
      await _database!.markCaptured(
        id,
        imagePath: result.localPath,
        measurementMode: _mode,
        captureOrientation: result.orientation,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _capturedResult = result;
        _reviewingPhoto = true;
        _orientationAttested = false;
      });
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to capture photo: $e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose the known reference object before choosing photo.',
          ),
        ),
      );
      await _openReferenceConfig();
      return;
    }

    setState(() => _saving = true);

    try {
      final result = await ImageService.pickFromGallery();
      if (result == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      // plan-phase-2/2.1-capture-screen-guards.md finding 3: nothing is written to the
      // database until the widget is confirmed still mounted -- a pick the user quits out
      // of before this point leaves no scan behind.
      if (!mounted) return;
      final id = await _ensureSession();
      await _database!.markCaptured(
        id,
        imagePath: result.localPath,
        measurementMode: _mode,
        captureOrientation: result.orientation,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _capturedResult = result;
        _reviewingPhoto = true;
        _orientationAttested = false;
      });
    } catch (e) {
      debugPrint('Gallery pick error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick photo: $e')));
      }
    }
  }

  /// TASKS.md's P0: the view gate must run and route BEFORE reference marking, not after
  /// (previously this method routed on `_mode` alone and the view model never ran until
  /// ResultsScreen, so a non-dorsal photo still walked through the reference-marking step
  /// that exists only to serve the weight branch). A native/inference failure here falls
  /// back to the pre-P0 routing (proceed as if the gate had not run) rather than trapping
  /// the user on the review screen.
  /// The orientation shown/attested on the review step, derived the same way regardless of
  /// whether this capture came from the live camera, gallery pick or a re-entered flow: from
  /// the actual image dimensions, never from the live sensor reading at review time (the phone
  /// may have rotated since the shutter fired).
  CaptureOrientation? get _capturedOrientation {
    if (_capturedResult != null) return _capturedResult!.orientation;
    final w = widget.initialArgs?.imageWidthPx;
    final h = widget.initialArgs?.imageHeightPx;
    if (w == null || h == null) return null;
    return CaptureOrientation.fromDimensions(w, h);
  }

  Future<void> _usePhoto() async {
    final orientation = _capturedOrientation;
    if (orientation != null && !_orientationAttested) {
      // Confirm step (point 3): the app cannot verify head direction, so it cannot proceed on
      // a default action without the explicit attestation.
      return;
    }
    // plan-phase-2/2.1-capture-screen-guards.md finding 5: armed here, not after the two
    // awaits below. The button's onPressed already checks `_saving`, but that check is at
    // least one frame behind -- a fast double-tap can enter this method twice before the
    // first call's setState takes effect, each creating its own session via _ensureSession.
    if (_saving) return;
    setState(() => _saving = true);

    final id = await _ensureSession();
    if (orientation != null) {
      await _database!.recordOrientationAttestation(
        id,
        orientation: orientation,
        attested: _orientationAttested,
      );
    }
    final imagePath =
        _capturedResult?.localPath ?? widget.initialArgs?.imagePath;
    final args = ScanFlowArgs(
      sessionId: id,
      goal: ScanGoal.weightAndHealth,
      measurementMode: _mode,
      reference: _reference,
      imagePath: imagePath,
      imageBytes: _capturedResult?.bytes ?? widget.initialArgs?.imageBytes,
      imageWidthPx:
          _capturedResult?.widthPx ?? widget.initialArgs?.imageWidthPx,
      imageHeightPx:
          _capturedResult?.heightPx ?? widget.initialArgs?.imageHeightPx,
      suggestion: widget.initialArgs?.suggestion,
    );
    if (!mounted) return;

    String? viewLabel;
    double viewConfidence = 0.0;
    if (imagePath != null) {
      try {
        final view = await RunAndPersistPipelineUseCase.resolveViewGate(
          _database!,
          id,
          imagePath,
        );
        viewLabel = view.label;
        viewConfidence = view.confidence;
      } catch (e) {
        debugPrint('View gate failed, falling back to unfiltered routing: $e');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);

    // docs/fix-phase-6/2-dialog-and-routing.md (F68/F70): both a `reject` and a
    // `health_only` verdict can be wrong, so both now show the same three-option dialog
    // instead of only `reject` getting a dialog, and only ever toward one route.
    String? routeOverride;
    if (viewLabel == 'reject' || viewLabel == 'health_only') {
      if (!mounted) return;
      final choice = await showViewChoiceDialog(
        context,
        isHealthOnly: viewLabel == 'health_only',
      );
      switch (choice) {
        case ViewChoice.retake:
          // Answered 2026-09-25 (fix-6.md open question 2): Retake on a `health_only`
          // photo marks the scan rejected too, the same as the existing Retake on
          // `reject`. No override is recorded for a Retake, either verdict.
          await _database!.updateScanStatus(id, ScanStatuses.rejected);
          if (mounted) setState(() => _reviewingPhoto = false);
          return;
        case ViewChoice.healthOnly:
          if (viewLabel == 'reject') {
            // A `health_only` verdict + "Check health only" is today's path with no
            // override recorded (fix-6.md's table) -- only a `reject` overridden toward
            // health-only needs a recorded override.
            routeOverride = 'health_only';
            await RunAndPersistPipelineUseCase.recordViewGateOverride(
              _database!,
              id,
              route: 'health_only',
              overriddenLabel: viewLabel!,
              overriddenConfidence: viewConfidence,
              imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
                imagePath!,
              ),
            );
          }
        case ViewChoice.weightAndHealth:
          routeOverride = 'dorsal_valid';
          await RunAndPersistPipelineUseCase.recordViewGateOverride(
            _database!,
            id,
            route: 'dorsal_valid',
            overriddenLabel: viewLabel!,
            overriddenConfidence: viewConfidence,
            imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
              imagePath!,
            ),
          );
      }
      // Falls through: the chosen route is routed exactly like that verdict below.
    }

    // health_only (verdict or override) skips reference marking entirely -- there is no
    // dorsal view to measure, so the reference-object step (which exists only to scale a
    // weight estimate) has nothing to serve. dorsal_valid (verdict or override), or an
    // unresolved gate (viewLabel == null), proceeds exactly as before this change.
    final effectiveRoute = routeOverride ?? viewLabel;
    final skipReference = effectiveRoute == 'health_only';

    if (!skipReference) {
      await _database!.updateScanStatus(id, ScanStatuses.referenceReview);
      if (mounted) context.push('/reference-marking', extra: args);
    } else {
      await _database!.updateScanStatus(id, ScanStatuses.analyzing);
      await _database!.addPipelineEvent(
        id,
        'analysis',
        'queued',
        message:
            'Photo classified as health-only — reference marking and weight estimation skipped.',
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
                  child: Center(
                    child: Text(
                      'Weight & Health Capture',
                      style: AppTextStyles.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Capture tips',
                  onPressed: _saving ? null : _showGuidance,
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraController != null &&
                    _cameraController!.value.isInitialized)
                  ClipRect(
                    child: Center(child: CameraPreview(_cameraController!)),
                  )
                else if (_isCameraInitializing)
                  Container(
                    color: const Color(0xFF171717),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white54),
                        SizedBox(height: 12),
                        Text(
                          'Starting camera...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  )
                else
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
                          _cameraError
                              ? 'Camera unavailable — tap shutter or choose from gallery'
                              : 'Tap shutter to capture or pick image',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.subtext.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _saving ? null : _pickFromGallery,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'Choose from gallery',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                CustomPaint(painter: _DorsalGuidePainter()),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 14,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                              : '${_reference!.name} · ${_unit.format(_reference!.lengthCm)} ${_unit.label}',
                        ),
                        onPressed: _saving ? null : _openReferenceConfig,
                        backgroundColor: Colors.white,
                        side: BorderSide.none,
                      ),
                    ],
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
                    tooltip: 'Choose from gallery',
                    onPressed: _saving ? null : _pickFromGallery,
                    icon: const Icon(
                      Icons.photo_library_outlined,
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
                  child: IconButton(
                    tooltip: 'Change reference',
                    onPressed: _saving ? null : _openReferenceConfig,
                    icon: const Icon(Icons.straighten, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// docs/fix-phase-4/6-capture-orientation.md point 3: an explicit, un-pre-ticked confirm
  /// step naming the rule for the captured orientation. The app cannot verify head direction
  /// itself, so "forced" means the user attests and the attestation is recorded, not that the
  /// app silently believes it -- `_usePhoto`'s button stays disabled until this is checked.
  Widget _buildAttestationCheckbox(CaptureOrientation orientation) {
    return Semantics(
      label: orientation.attestationLabel,
      checked: _orientationAttested,
      child: Material(
        color: AppColors.pinkTint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () =>
              setState(() => _orientationAttested = !_orientationAttested),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Checkbox(
                      value: _orientationAttested,
                      onChanged: (checked) => setState(
                        () => _orientationAttested = checked ?? false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      orientation.attestationLabel,
                      style: AppTextStyles.body,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReview() {
    final previewBytes =
        _capturedResult?.bytes ?? widget.initialArgs?.imageBytes;

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
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: previewBytes != null
                ? Image.memory(previewBytes, fit: BoxFit.contain)
                : Column(
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
                        style: AppTextStyles.label.copyWith(
                          color: Colors.white70,
                        ),
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
                      'Next, verify the app suggestion or mark both reference endpoints manually.',
                      style: AppTextStyles.subtext.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
              if (_capturedOrientation case final orientation?) ...[
                const SizedBox(height: 14),
                _buildAttestationCheckbox(orientation),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _reviewingPhoto = false),
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          !_saving &&
                              (_capturedOrientation == null ||
                                  _orientationAttested)
                          ? _usePhoto
                          : null,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Verify reference'),
                    ),
                  ),
                ],
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Checking the photo…',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtext.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// docs/fix-phase-6/2-dialog-and-routing.md: the three-way choice both a `reject` and a
/// `health_only` verdict now offer. Public (not nested in `_CaptureScreenState`) so
/// [showViewChoiceDialog] is directly widget-testable without spinning up the camera.
enum ViewChoice { retake, healthOnly, weightAndHealth }

/// docs/fix-phase-6/2-dialog-and-routing.md: one shared dialog for both `reject` and
/// `health_only` verdicts (F68) -- the photo check can be wrong in either direction, so
/// both offer the same three choices instead of only `reject` getting a dialog at all,
/// and only ever toward the full route. A dismissal (tap outside, back gesture) counts as
/// Retake photo, the same as round 9's two-button dialog did. Buttons are stacked
/// full-width rather than left to `AlertDialog`'s default row/overflow layout: three
/// labels this long do not fit on one row on a small phone, and each must stay at least
/// 44 px tall. A top-level function (not a `_CaptureScreenState` method) so it is directly
/// widget-testable: a test pumps a bare `MaterialApp` and calls this with its own
/// `BuildContext`, with no camera involved.
Future<ViewChoice> showViewChoiceDialog(
  BuildContext context, {
  required bool isHealthOnly,
}) async {
  final choice = await showDialog<ViewChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        isHealthOnly ? 'Weight may not be measurable' : 'Photo not recognized',
      ),
      content: Text(
        isHealthOnly
            ? "This photo looks right for a health check, but not for a weight "
                  "estimate, which needs the pig's whole back seen from above. The "
                  'check can be wrong, so you can choose how to continue.'
            : "This photo wasn't recognized as a clear pig photo. The check can be "
                  'wrong, so you can choose how to continue.',
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogChoiceButton(
              dialogContext,
              label: 'Retake photo',
              value: ViewChoice.retake,
              filled: false,
            ),
            const SizedBox(height: 8),
            _dialogChoiceButton(
              dialogContext,
              label: 'Check health only',
              value: ViewChoice.healthOnly,
              filled: false,
            ),
            const SizedBox(height: 8),
            _dialogChoiceButton(
              dialogContext,
              label: 'Check weight and health',
              value: ViewChoice.weightAndHealth,
              filled: true,
            ),
          ],
        ),
      ],
    ),
  );
  return choice ?? ViewChoice.retake;
}

Widget _dialogChoiceButton(
  BuildContext dialogContext, {
  required String label,
  required ViewChoice value,
  required bool filled,
}) {
  return Semantics(
    button: true,
    label: label,
    child: filled
        ? ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: () => Navigator.pop(dialogContext, value),
            child: Text(label),
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: () => Navigator.pop(dialogContext, value),
            child: Text(label),
          ),
  );
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
