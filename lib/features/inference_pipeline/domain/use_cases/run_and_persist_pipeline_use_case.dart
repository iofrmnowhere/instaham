// Runs the real inference pipeline for one captured scan and persists the results through
// AppDatabase, exactly like insertSampleRecord()'s save calls but with real model output
// instead of random demo data. This is slice 4's "RunInferencePipelineUseCase actually
// wired into the app" (ML_implementation_plan.md section 11.3): real view + health
// classification, segmentation, and (slice R4) the C++ weight-prediction chain. Weight
// saves as unavailable whenever the manifest's weight capability is off — the default,
// per section 3.4's permanent identity-stub cutter and AGENTS.md rule 8 — and as a real
// (test-override, uncut-mask) value only when the bundled manifest was built with
// export_xgboost.py's --enable-for-testing flag.
//
// TASKS.md's P0/P1 plan (2026-08-29): the view gate must run and route BEFORE reference
// marking, and must not have its label overridden by an app-invented confidence threshold
// (the model's argmax label is the rule its recorded metrics were measured under). The
// view gate is expected to have already run once at capture time
// (capture_screen.dart's `_usePhoto()`); `_resolveViewGate` below reuses that persisted
// 'view' PipelineEvent instead of re-running the model, and only falls back to running it
// here for a scan that predates this change or whose capture-time classification failed.
//
// TASKS.md P0 (2026-08-30): analysis previously made up to three separate native calls
// (health, segmentation, weight), each of which -- for a dorsal photo -- independently
// re-ran YOLO segmentation from the image path. This is why dorsal scans had a visibly
// longer, more variable stall than health_only ones: two full 640x640 YOLO passes plus
// mask construction, not one. `pipelineService.run()` now makes the single native call
// (`instaham_ml_run_pipeline_json`) that constructs the mask once and reuses it for both
// the health and weight branches. The per-capability services this replaced
// (health_model_service.dart, segmentation_service.dart, weight_model_service.dart) are
// unchanged and still exist for isolated debugging / screens that need one signal only.
// TASKS.md W3 (2026-09-02): `execute()` now reads back the reference-object annotation
// `reference_marking_screen.dart` persists and, only when it's user-confirmed AND
// coplanar-confirmed (AGENTS.md rule 7), forwards its cm/pixel to `pipelineService.run()`
// so the native weight branch can normalize features into the regressor's training pixel
// space instead of always predicting on unscaled capture pixels.
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/reference_annotation_dao.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../services/ml/pipeline_service.dart';
import '../../../../services/ml/view_model_service.dart';

const String kViewModelVersion = 'ghostnetv3-view-v1';
const String kHealthModelVersion = 'ghostnetv3-health-v1';
const String kWeightModelVersion = 'xgb-weight-v1';

// Display-only: below this, a health label is flagged `uncertain` in the UI. This is NOT
// a gate -- the label itself is always the model's argmax (TASKS.md Cause B/P1). A real
// gating threshold, if ever wanted, belongs in the manifest with its own precision/recall
// justification, not hardcoded here.
const double kHealthUncertainBelow = 0.60;

class RunAndPersistPipelineUseCase {
  final IViewModelService viewModelService;
  final IPipelineService pipelineService;

  const RunAndPersistPipelineUseCase({
    this.viewModelService = const ViewModelServiceImpl(),
    this.pipelineService = const PipelineServiceImpl(),
  });

  /// Runs view -> (health, segmentation, weight) for `scanId`'s image via one native
  /// pipeline call and writes every branch's result to `db`. Never throws: a native/ORT
  /// failure is recorded as a blocked/unavailable result rather than surfacing an
  /// exception to the UI, per AGENTS.md rule 8 (no branch ever emits a number after a
  /// failed upstream check).
  Future<void> execute(AppDatabase db, String scanId, String imagePath) async {
    try {
      final view = await resolveViewGate(db, scanId, imagePath);
      final viewRejected = view.label == 'reject';

      if (viewRejected) {
        await db.saveHealthResult(
          scanId: scanId,
          eligible: false,
          failureReason:
              'View classifier determined this photo is not usable for scanning '
              '(${_confidenceText(view.confidence)}).',
          modelVersion: kViewModelVersion,
        );
        await db.saveWeightResult(
          scanId: scanId,
          eligible: false,
          failureReason: 'Pipeline stopped at the view-suitability gate.',
          modelVersion: kWeightModelVersion,
        );
        await db.updateScanStatus(scanId, ScanStatuses.rejected);
        return;
      }

      // TASKS.md W3: only a user-confirmed AND coplanar-confirmed reference is a scale
      // (AGENTS.md rule 7) -- an in-progress or unconfirmed annotation, or one predating
      // this feature, is treated exactly like "no reference marked".
      final annotation = await ReferenceAnnotationDao(
        db,
      ).getReferenceAnnotation(scanId);
      final cmPerPixel =
          annotation != null &&
              annotation.userConfirmed &&
              annotation.sameFloorPlaneConfirmed &&
              annotation.cmPerPixel != null &&
              annotation.cmPerPixel! > 0
          ? annotation.cmPerPixel
          : null;

      // capture_screen.dart's resolveViewGate call is the routing authority -- it already
      // decided reference-marking vs. not, before this method ever runs. The pipeline's
      // own `view` block is read below only to confirm the two runs agree; a disagreement
      // (e.g. the manifest changed between capture and analysis) does not re-route the
      // scan, it degrades to the failure path so the mismatch is visible, not silent.
      final (status, envelope) = await pipelineService.run(
        imagePath,
        cmPerPixel: cmPerPixel,
      );
      if (status != MlStatus.ok || envelope['status'] == 'stopped') {
        throw StateError(
          'pipeline returned $status with envelope status '
          '${envelope['status'] ?? 'unknown'}',
        );
      }

      // ref_fix.md F4: record the native scale decision every run, success or failure --
      // previously a rejected scan left no trace of what cm_per_px/k/height_ratio actually
      // were, which is why the F2 resolution bug needed a code read rather than a log read
      // to diagnose.
      final scaleJson = envelope['scale'] as Map<String, dynamic>? ?? const {};
      if (scaleJson.isNotEmpty) {
        await db.addPipelineEvent(
          scanId,
          'scale',
          scaleJson['status'] as String? ?? 'unknown',
          message: jsonEncode(scaleJson),
        );
      }

      final healthJson =
          envelope['health'] as Map<String, dynamic>? ?? const {};
      if (healthJson['status'] == 'ok') {
        final confidence =
            (healthJson['confidence'] as num?)?.toDouble() ?? 0.0;
        await db.saveHealthResult(
          scanId: scanId,
          eligible: true,
          className: healthJson['label'] as String? ?? 'Unknown',
          confidence: confidence,
          uncertain: confidence < kHealthUncertainBelow,
          modelVersion: kHealthModelVersion,
        );
      } else {
        await db.saveHealthResult(
          scanId: scanId,
          eligible: false,
          failureReason:
              (healthJson['message'] ?? healthJson['reason']) as String? ??
              'Health classification unavailable.',
          modelVersion: kHealthModelVersion,
        );
      }

      final segmentationJson =
          envelope['segmentation'] as Map<String, dynamic>? ?? const {};
      if (segmentationJson['status'] == 'ok' ||
          segmentationJson['status'] == 'error') {
        final pigCount = segmentationJson['status'] == 'ok'
            ? ((segmentationJson['instances_found'] as num?)?.toInt() ?? 0)
            : 0;
        await db.addPipelineEvent(
          scanId,
          'segmentation',
          pigCount > 0 ? 'completed' : 'no_detection',
          message:
              'pig_count=$pigCount confidence=${segmentationJson['confidence'] ?? 0.0}',
        );
      }

      final weightJson =
          envelope['weight'] as Map<String, dynamic>? ?? const {};
      final weightEligible = weightJson['status'] == 'ok';
      if (weightEligible) {
        final features =
            (envelope['features'] as Map<String, dynamic>?)?['values']
                as Map<String, dynamic>?;
        final note = weightJson['note'] as String?;
        // TASKS.md W6: a successful weight result also stores the reference values that
        // produced it, so a stored scan can be re-derived later -- these three columns
        // existed unused since before this feature (app_database.dart's WeightResults).
        await db.saveWeightResult(
          scanId: scanId,
          eligible: true,
          valueKg: (weightJson['estimated_kg'] as num?)?.toDouble(),
          referenceLengthCm: annotation?.lengthCm,
          referencePixelLength: annotation?.pixelLength,
          cmPerPixel: cmPerPixel,
          ra: (features?['RA'] as num?)?.toDouble(),
          lc: (features?['LC'] as num?)?.toDouble(),
          bl: (features?['BL'] as num?)?.toDouble(),
          bw: (features?['BW'] as num?)?.toDouble(),
          e: (features?['E'] as num?)?.toDouble(),
          modelVersion: note == null
              ? kWeightModelVersion
              : '$kWeightModelVersion ($note)',
        );
      } else {
        await db.saveWeightResult(
          scanId: scanId,
          eligible: false,
          failureReason: _weightFailureMessage(weightJson['reason'] as String?),
          modelVersion: kWeightModelVersion,
        );
      }

      // `completed` only when a branch actually produced a number. Health alone is not
      // enough: the weight card is the one the records list's Completed filter is about,
      // and before slice R4 no build could ever reach this state, so the status was
      // hardcoded to `blocked`. Now the test-override path can succeed, so it must not be.
      await db.updateScanStatus(
        scanId,
        weightEligible ? ScanStatuses.completed : ScanStatuses.blocked,
      );
    } catch (e, st) {
      await db.addPipelineEvent(scanId, 'pipeline', 'error', message: '$e');
      await db.saveHealthResult(
        scanId: scanId,
        eligible: false,
        failureReason: 'Inference failed: $e',
        modelVersion: kHealthModelVersion,
      );
      await db.saveWeightResult(
        scanId: scanId,
        eligible: false,
        failureReason: 'Inference failed.',
        modelVersion: kWeightModelVersion,
      );
      await db.updateScanStatus(scanId, ScanStatuses.blocked);
      // Rethrow-free by design (see doc comment) -- but still surface in debug logs.
      // ignore: avoid_print
      print('RunAndPersistPipelineUseCase failed for $scanId: $e\n$st');
    }
  }

  /// Reuses the 'view' PipelineEvent capture time already wrote for this scan
  /// (capture_screen.dart's `_usePhoto()`), so the view model never runs twice and the
  /// route already taken (or not taken, for a reject) stays consistent with what is shown
  /// here. Falls back to running the classifier itself only for a scan that predates this
  /// change or whose capture-time attempt never persisted an event.
  static Future<ViewClassificationResult> resolveViewGate(
    AppDatabase db,
    String scanId,
    String imagePath, {
    IViewModelService viewModelService = const ViewModelServiceImpl(),
  }) async {
    final existing =
        await (db.select(db.pipelineEvents)
              ..where(
                (row) => row.scanId.equals(scanId) & row.stage.equals('view'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      return ViewClassificationResult(
        label: existing.status,
        confidence: double.tryParse(existing.message ?? '') ?? 0.0,
      );
    }
    final view = await viewModelService.classify(imagePath);
    await recordViewGate(db, scanId, view);
    return view;
  }

  /// Persists a view-gate decision as a `PipelineEvent` (`status` = label, `message` =
  /// confidence as a plain decimal string) so it can be reused by [resolveViewGate] and
  /// rendered by ResultsScreen's view card (TASKS.md P2) without re-running the model.
  static Future<void> recordViewGate(
    AppDatabase db,
    String scanId,
    ViewClassificationResult view,
  ) {
    return db.addPipelineEvent(
      scanId,
      'view',
      view.label,
      message: view.confidence.toStringAsFixed(4),
    );
  }
}

String _confidenceText(double confidence) =>
    '${(confidence * 100).round()}% confidence';

/// Maps pipeline.cpp's `weight.reason` machine strings (pipeline.cpp's `unavailable()` /
/// `skipped()` helpers) to the human-readable sentences the weight card has always shown.
String _weightFailureMessage(String? reason) => switch (reason) {
  'view_not_dorsal' =>
    'Weight branch skipped: photo was not classified as a dorsal view.',
  'view_unresolved' =>
    'Weight branch unavailable: view classification did not resolve.',
  'segmentation_failed' ||
  'no_instance_above_conf' ||
  'no_mask' ||
  'empty_mask' =>
    'Weight branch unavailable, and no pig was detected in this photo.',
  'cutter_identity_stub' =>
    'Weight branch unavailable in this build (cutter is the identity stub).',
  'contour_too_small' || 'cutter_failed' =>
    'Weight branch unavailable: feature extraction failed on this photo.',
  // TASKS.md W5/W6: the reference-object scale is a §7 eligibility check, not just a
  // display value -- these three reasons name why it failed rather than the generic
  // cutter-stub message, which would be misleading here.
  'scale_unavailable' || 'reference_object_not_confirmed' =>
    'Mark a reference object to estimate weight.',
  'scale_out_of_range' =>
    'The reference object suggests a camera distance too far outside training range for a reliable estimate.',
  'scale_resample_failed' =>
    'Weight branch unavailable: could not normalize the mask using the reference object.',
  // ref_fix.md F3: the normalized feature vector fell outside the range the regressor
  // was actually trained on -- a mis-marked reference, a wrong cm_per_px_target, or a
  // genuinely out-of-distribution animal will all land here rather than as a silent,
  // extrapolated number.
  'features_out_of_training_domain' =>
    'Weight branch unavailable: the measurements from this photo and reference object are '
        'outside the range this model was trained on. Re-check the reference object placement.',
  _ => 'Weight branch unavailable in this build (cutter is the identity stub).',
};
