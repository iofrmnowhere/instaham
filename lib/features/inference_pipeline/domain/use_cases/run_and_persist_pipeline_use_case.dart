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
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/reference_annotation_dao.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../services/ml/pipeline_service.dart';
import '../../../../services/ml/view_model_service.dart';

const String kViewModelVersion = 'mobilenetv4-view-v2';
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
      final view = await resolveViewGate(
        db,
        scanId,
        imagePath,
        viewModelService: viewModelService,
      );
      final viewRejected = view.label == 'reject';
      // docs/fix-phase-6/2-dialog-and-routing.md (F68): the override lookup is no longer
      // gated on `reject` -- a `health_only` verdict can now also be overridden to the
      // full route. `routeOverride` is the chosen route ('dorsal_valid'/'health_only'),
      // or null when no override was recorded for this exact image.
      final routeOverride = await viewRouteOverride(db, scanId, imagePath);

      if (viewRejected && routeOverride == null) {
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
        viewRouteOverride: routeOverride,
      );
      if (status != MlStatus.ok || envelope['status'] == 'stopped') {
        throw StateError(
          'pipeline returned $status with envelope status '
          '${envelope['status'] ?? 'unknown'}',
        );
      }

      // TEMPORARY (docs/fix-phase-2/1.1-manifest-input-scale-regression.md, step "capture
      // the envelope, not just the message"): dump the whole section-9 envelope to logcat
      // so a device run can be diagnosed without pulling the SQLite file off a release
      // build. `construction.mask_diagonal_fraction` and `segmentation.rungs_tried` are the
      // values phase 1.1 and phase 2 are waiting on. Chunked because logcat truncates a
      // single long line. Remove this block once those numbers are recorded.
      _dumpEnvelopeToLog(scanId, envelope);

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
        // docs/plan-4.md / docs/plan-phase-4/3-app-surfacing.md: which stage produced this
        // result, read from the envelope's own `cascade.final_stage` -- never inferred from
        // the label. Absent `cascade` key (the manifest's cascade switch is off, or an
        // older native build) means this scan predates the cascade or ran single-pass;
        // `preprocessingVersion` stays null so old and new rows can be told apart.
        // Reuses an existing, previously-unwritten HealthResults column -- no schema change.
        final cascadeJson = healthJson['cascade'] as Map<String, dynamic>?;
        final finalStage = cascadeJson?['final_stage'] as String?;
        await db.saveHealthResult(
          scanId: scanId,
          eligible: true,
          className: healthJson['label'] as String? ?? 'Unknown',
          confidence: confidence,
          uncertain: confidence < kHealthUncertainBelow,
          modelVersion: kHealthModelVersion,
          preprocessingVersion: finalStage == null
              ? null
              : 'cascade_v1:$finalStage',
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

      // ref_fix.md F20: persist the WHOLE segmentation block (and construction's), not just
      // pig_count/confidence -- F15/F18/F19 put candidates_kept, ladder_rung, rungs_tried,
      // content_scale and mask_diagonal_fraction into the envelope specifically so a scan
      // could be diagnosed from a log read instead of a code read; throwing all of it away
      // except two fields is why round 3's fix had to be judged from three sentences of
      // user-visible text (ref_fix.md section 1.2/3, F20).
      final segmentationJson =
          envelope['segmentation'] as Map<String, dynamic>? ?? const {};
      if (segmentationJson.isNotEmpty) {
        final pigCount = segmentationJson['status'] == 'ok'
            ? ((segmentationJson['instances_found'] as num?)?.toInt() ?? 0)
            : 0;
        await db.addPipelineEvent(
          scanId,
          'segmentation',
          pigCount > 0 ? 'completed' : 'no_detection',
          message: jsonEncode(segmentationJson),
        );
      }
      final constructionJson =
          envelope['construction'] as Map<String, dynamic>? ?? const {};
      if (constructionJson.isNotEmpty) {
        await db.addPipelineEvent(
          scanId,
          'construction',
          constructionJson['status'] as String? ?? 'unknown',
          message: jsonEncode(constructionJson),
        );
      }

      final weightJson =
          envelope['weight'] as Map<String, dynamic>? ?? const {};
      final weightEligible = weightJson['status'] == 'ok';

      // ref_fix.md F6: the feature vector is recorded on EVERY run, success or failure --
      // previously a rejected scan left no 'features' pipeline event and null
      // ra/lc/bl/bw/e columns, which is why a `features_out_of_training_domain` rejection
      // was undiagnosable without a code read.
      final featuresJson =
          envelope['features'] as Map<String, dynamic>? ?? const {};
      if (featuresJson.isNotEmpty) {
        await db.addPipelineEvent(
          scanId,
          'features',
          featuresJson['status'] as String? ?? 'unknown',
          message: jsonEncode(featuresJson),
        );
      }
      // docs/plan-phase/4-dart-persistence-ui.md: the envelope's `features` block is now
      // family-tagged and arbitrary-width ({family, order, values:{name: value}}). Carry
      // the whole `values` map and its `family` through to persistence untouched -- the
      // Dart layer names no feature.
      final featuresRaw = featuresJson['values'] as Map<String, dynamic>?;
      final features = featuresRaw == null
          ? null
          : <String, double>{
              for (final entry in featuresRaw.entries)
                if (entry.value is num)
                  entry.key: (entry.value as num).toDouble(),
            };
      final featureFamily = featuresJson['family'] as String?;

      // Cutter telemetry (docs/plan-phase/3-manifest-pipeline.md). TELEMETRY ONLY -- no
      // branch reads it, it never reaches the UI; persisted so a bad cut is diagnosable.
      final cutterJson =
          envelope['cutter'] as Map<String, dynamic>? ?? const {};
      final cutterKeptFraction = (cutterJson['kept_fraction'] as num?)
          ?.toDouble();
      final cutterStatus = cutterJson['status'] as String?;

      if (weightEligible) {
        // ref_fix.md F22: the regressor is a gradient-boosted tree ensemble, so a feature
        // vector past its trained max/min is answered from the edge leaf -- a real,
        // pinned ceiling (measured empirically at ~182kg, floor ~83.5kg, ref_fix.md
        // section 1.6), not a genuine interpolated estimate. No Drift schema change for
        // this (ref_fix.md section 4): fold it into the same free-text note column the
        // TEST OVERRIDE caveat already uses, rather than adding a column for a temporary
        // caveat tied to the still-missing cutter.
        final extrapolated = weightJson['extrapolated'] == true;
        final extrapolatedFeatures =
            (weightJson['extrapolated_features'] as List?)
                ?.map((f) => f.toString())
                .join(',') ??
            '';
        final note = [
          weightJson['note'] as String?,
          if (extrapolated)
            'EXTRAPOLATED: feature(s) $extrapolatedFeatures past the trained range -- '
                'this value is a model ceiling/floor, not an interpolated estimate.',
        ].whereType<String>().join(' ');
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
          features: features,
          featureFamily: featureFamily,
          cutterKeptFraction: cutterKeptFraction,
          cutterStatus: cutterStatus,
          modelVersion: note.isEmpty
              ? kWeightModelVersion
              : '$kWeightModelVersion ($note)',
        );
      } else {
        // ref_fix.md F6: a rejected weight branch still stores whatever feature vector was
        // actually measured (null when the failure happened before feature extraction, e.g.
        // no reference marked) -- so a stored-but-ineligible scan can be re-derived and
        // audited exactly like a successful one.
        await db.addPipelineEvent(
          scanId,
          'weight',
          'unavailable',
          message: jsonEncode(weightJson),
        );
        await db.saveWeightResult(
          scanId: scanId,
          eligible: false,
          referenceLengthCm: annotation?.lengthCm,
          referencePixelLength: annotation?.pixelLength,
          cmPerPixel: cmPerPixel,
          features: features,
          featureFamily: featureFamily,
          cutterKeptFraction: cutterKeptFraction,
          cutterStatus: cutterStatus,
          failureReason: _weightFailureMessage(
            weightJson['reason'] as String?,
            weightJson['reason'] == 'mask_implausibly_small'
                ? _maskFractionDetail(weightJson)
                : _domainFeatureDetail(
                    features,
                    featuresJson['gated'] as List?,
                    weightJson['violations'] as List?,
                  ),
            cutterStatus,
          ),
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
  /// here. Falls back to running the classifier itself for a scan that predates this
  /// change, whose capture-time attempt never persisted an event, OR whose stored event
  /// describes a different image than [imagePath] (F66: `_sessionId` is reused across
  /// retakes within one capture screen, so the scan's identity alone cannot key the
  /// cache -- the image must). A stored event with no recorded identity is treated as a
  /// mismatch, never as a wildcard.
  static Future<ViewClassificationResult> resolveViewGate(
    AppDatabase db,
    String scanId,
    String imagePath, {
    IViewModelService viewModelService = const ViewModelServiceImpl(),
  }) async {
    final identity = await imageIdentityOf(imagePath);
    // Ordered by `id`, not `createdAt`: two view events from a fast retake within the
    // same capture session can land in the same createdAt second, and only the
    // autoincrement id is guaranteed to reflect actual insertion order.
    final existing =
        await (db.select(db.pipelineEvents)
              ..where(
                (row) => row.scanId.equals(scanId) & row.stage.equals('view'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.id)])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null &&
        existing.imageIdentity != null &&
        existing.imageIdentity == identity) {
      return ViewClassificationResult(
        label: existing.status,
        confidence: double.tryParse(existing.message ?? '') ?? 0.0,
      );
    }
    final view = await viewModelService.classify(imagePath);
    await recordViewGate(db, scanId, view, imageIdentity: identity);
    return view;
  }

  /// sha256 of the image's bytes, used to key a cached view-gate verdict to the image it
  /// classified rather than to the scan (F66). A content hash is preferred over the file
  /// path: `processCapture` writes unique-per-capture filenames, but a path match would
  /// still wrongly hit if a file were ever replaced in place, and a hash also survives the
  /// temp directory being relocated.
  static Future<String> imageIdentityOf(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    // plan-phase-2/2.1-capture-screen-guards.md finding 4: sha256 over a multi-MB JPEG is
    // real CPU-bound work; run it off the UI isolate the same way subphase 1.1 moved
    // decode/bake/encode. Uint8List in, String out -- both plainly sendable, so compute()
    // needs no isolate-context plumbing.
    return compute(_sha256Hex, bytes);
  }

  static String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Persists a view-gate decision as a `PipelineEvent` (`status` = label, `message` =
  /// confidence as a plain decimal string, `imageIdentity` = the classified image's
  /// sha256) so it can be reused by [resolveViewGate] -- for the same image only -- and
  /// rendered by ResultsScreen's view card (TASKS.md P2) without re-running the model.
  static Future<void> recordViewGate(
    AppDatabase db,
    String scanId,
    ViewClassificationResult view, {
    String? imageIdentity,
  }) {
    return db.addPipelineEvent(
      scanId,
      'view',
      view.label,
      message: view.confidence.toStringAsFixed(4),
      imageIdentity: imageIdentity,
    );
  }

  /// F67 (fix-phase-5/2-view-reject-override.md), widened by F68
  /// (fix-phase-6/2-dialog-and-routing.md) to carry which route was chosen: records that
  /// the user picked [route] ('dorsal_valid' or 'health_only') instead of the verdict the
  /// photo check gave for [imagePath]. Deliberately a **separate stage**,
  /// `'view_override'`, not `'view'` -- `resolveViewGate`'s cache lookup and
  /// `RecordsDao.loadLatestEvent(scanId, 'view')` (the results screen's view/weight/health
  /// cards) both select the latest row of stage `'view'` with no status filter, and an
  /// override row filed under that stage would be read back as if it were a verdict. A
  /// distinct stage keeps every existing 'view' reader untouched. The event's status is
  /// `'override:<route>'` (round 9's plain `'override'` is never written by this method
  /// again, only read back by [viewRouteOverride]).
  ///
  /// Keyed by the same content-hash `imageIdentity` as the cached verdict itself -- never
  /// the scan alone, for the exact reason F66 exists: `_sessionId` is reused across
  /// retakes, so a scan-scoped override would leak onto every later photo in the same
  /// capture-screen session. `message` carries the overridden label and confidence so the
  /// event is self-describing without a join back to the original 'view' row.
  ///
  /// Takes plain `overriddenLabel`/`overriddenConfidence` rather than a
  /// `ViewClassificationResult` so `capture_screen.dart` (a UI widget) does not need to
  /// import `services/ml/view_model_service.dart` (AGENTS.md: "keep UI widgets independent
  /// of ... ML runtime packages") just to call this method.
  static Future<void> recordViewGateOverride(
    AppDatabase db,
    String scanId, {
    required String route,
    required String overriddenLabel,
    required double overriddenConfidence,
    required String imageIdentity,
  }) {
    return db.addPipelineEvent(
      scanId,
      'view_override',
      'override:$route',
      message: '$overriddenLabel ${overriddenConfidence.toStringAsFixed(4)}',
      imageIdentity: imageIdentity,
    );
  }

  /// The chosen override route ('dorsal_valid' or 'health_only') for the exact image at
  /// [imagePath], or null when no override was recorded for it -- a null-identity row
  /// (legacy, or a different image) is a mismatch, never a wildcard, same rule as
  /// [resolveViewGate]. A legacy row with status `'override'` (no route, round 9's only
  /// possible meaning) reads as `'dorsal_valid'`. This replaces the old `bool`
  /// `hasViewGateOverride`.
  static Future<String?> viewRouteOverride(
    AppDatabase db,
    String scanId,
    String imagePath,
  ) async {
    final identity = await imageIdentityOf(imagePath);
    final existing =
        await (db.select(db.pipelineEvents)
              ..where(
                (row) =>
                    row.scanId.equals(scanId) &
                    row.stage.equals('view_override'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.id)])
              ..limit(1))
            .getSingleOrNull();
    if (existing == null ||
        existing.imageIdentity == null ||
        existing.imageIdentity != identity) {
      return null;
    }
    if (existing.status == 'override') return 'dorsal_valid';
    return existing.status.startsWith('override:')
        ? existing.status.substring('override:'.length)
        : null;
  }
}

String _confidenceText(double confidence) =>
    '${(confidence * 100).round()}% confidence';

/// Maps pipeline.cpp's `weight.reason` machine strings (pipeline.cpp's `unavailable()` /
/// `skipped()` helpers) to the human-readable sentences the weight card has always shown.
/// `detail` (ref_fix.md F6) is pipeline.cpp's `domain_violations_detail` -- the raw
/// "NAME=value " list of whichever RA/LC/BL/BW/E features fell outside the trained
/// domain -- appended to the three domain-gate reasons so the message names exactly what
/// was measured, not just that something was out of range.
String _weightFailureMessage(
  String? reason, [
  String? detail,
  String? cutterStatus,
]) {
  // docs/plan-phase/4-dart-persistence-ui.md: the V176/V144 cutter can now decline for
  // reasons of its own. In the shipped build weight.available is false, so weight.reason
  // is the generic `weight_pending_field_validation` and the real cause sits in
  // envelope['cutter']['status'] -- surface that here rather than the pending-validation
  // boilerplate. All four mean "the pig's outline could not be resolved well enough to
  // find the shoulder"; the corrective action is the same (retake from the side), and it
  // is deliberately distinct from the domain-gate message (animal outside the trained
  // size range).
  const cutterDeclineStatuses = {
    'jiduan_failed',
    'no_terminal_balls',
    'break1_unfit',
    'shoulder_undecided',
  };
  if (reason == 'weight_pending_field_validation' &&
      cutterStatus != null &&
      cutterDeclineStatuses.contains(cutterStatus)) {
    return 'Weight branch unavailable: the pig outline in this photo could not be '
        'resolved well enough to remove the head and neck. Retake the photo from '
        'directly above, with the pig standing straight and fully in frame.';
  }
  // ref_fix.md F7: these three reasons are pipeline.cpp's classify_domain_violation()
  // result -- which feature(s) actually violated the trained domain decides which message
  // the user sees, since "re-check the reference object" is only correct advice for one of
  // the three ways this gate can fire (ref_fix.md section 1.3).
  const domainReasons = {
    'mask_shape_out_of_domain',
    'subject_smaller_than_trained',
    'features_out_of_training_domain',
    'mask_implausibly_small',
  };
  final base = switch (reason) {
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
    // docs/plan-phase/4: phase 5 still owes the field re-derivation of cm_per_px_target
    // from post-cut masks. The cutter is real (phase 2); the calibration is not yet
    // confirmed, so no estimate ships even though nothing failed.
    'weight_pending_field_validation' =>
      'Weight estimation is not available in this build yet -- the measurement scale is '
          'still being validated against field data. Health screening is unaffected.',
    // docs/plan-phase/4 / README_AI_INTEGRATION.md section 7: the two pre-cutter quality
    // gates (ship dark today). Each names its own corrective retake.
    'truncation_gate_rejected' =>
      'Weight branch stopped: the pig is cut off at the edge of the photo. Retake it '
          'with the whole body inside the frame.',
    'posture_gate_rejected' =>
      'Weight branch stopped: the pig is too curved in this photo for a reliable '
          'estimate. Retake it with the pig standing straight.',
    // TASKS.md W5/W6: the reference-object scale is a §7 eligibility check, not just a
    // display value -- these three reasons name why it failed rather than the generic
    // cutter-stub message, which would be misleading here.
    'scale_unavailable' || 'reference_object_not_confirmed' =>
      'Mark a reference object to estimate weight.',
    'scale_out_of_range' =>
      'The reference object suggests a camera distance too far outside training range for a reliable estimate.',
    'scale_resample_failed' =>
      'Weight branch unavailable: could not normalize the mask using the reference object.',
    // ref_fix.md F16: the constructed mask's bounding box is an implausibly small
    // fraction of the photo -- not a scale or reference-object problem, the detected
    // outline itself isn't big enough to be a pig (this is what F12's mask-selection bug
    // produced before that fix: a real pig's mask reduced to a few dozen pixels).
    'mask_implausibly_small' =>
      'Weight branch unavailable: the pig outline could not be detected properly in this '
          'photo -- only a small fragment was found. Retake the photo with the whole pig in frame.',
    // ref_fix.md F7: only an E (shape) violation, with no size feature involved -- the
    // mask itself is the wrong shape, not the reference object.
    'mask_shape_out_of_domain' =>
      "Weight branch unavailable: the detected outline doesn't look like a usable dorsal "
          'pig mask. Retake the photo with the pig standing straight and fully in frame.',
    // ref_fix.md F7: only size features violated, all below the trained minimum -- the
    // regressor's eval set was 87-192kg pigs only, so a smaller subject is a genuine
    // extrapolation, not a mis-marked reference.
    'subject_smaller_than_trained' =>
      'Weight branch unavailable: this pig measures smaller than any animal this model was '
          'trained on (87-192kg). A weight estimate would be an extrapolation, so none is shown.',
    // ref_fix.md F3: the normalized feature vector fell outside the range the regressor
    // was actually trained on -- a mis-marked reference, a wrong cm_per_px_target, or a
    // genuinely out-of-distribution animal will all land here rather than as a silent,
    // extrapolated number.
    'features_out_of_training_domain' =>
      'Weight branch unavailable: the measurements from this photo and reference object are '
          'outside the range this model was trained on. Re-check the reference object placement.',
    // ref_fix.md F6: an unmapped reason is surfaced verbatim rather than disguised as the
    // cutter-stub message, so a future reason pipeline.cpp adds shows up as "unhandled"
    // instead of silently misattributed to a stub that isn't what actually happened.
    _ => 'Weight branch unavailable (${reason ?? "unknown reason"}).',
  };
  if (domainReasons.contains(reason) &&
      detail != null &&
      detail.trim().isNotEmpty) {
    return '$base (${detail.trim()})';
  }
  return base;
}

/// ref_fix.md F17: renders ALL FIVE of RA/LC/BL/BW/E, marking the ones pipeline.cpp's
/// `violations` array named -- round 2 only listed the violating features, which is why an
/// earlier report showed no `BW` and a later one showed no `E`: a value's ABSENCE from the
/// message was silently indistinguishable from "this feature wasn't out of range" and "this
/// feature wasn't measured at all", and it hid the single most diagnostic fact in one of
/// ref_log.md's three samples -- a 14x3px sliver mask PASSED the `E` (eccentricity) check
/// (a thin sliver scores HIGH on eccentricity, not low), so the omitted `E` value looked
/// like confirmation nothing was wrong with the mask's shape rather than a check that
/// simply can't catch a degenerate mask on its own (see F16, which catches it instead).
/// `values` is `envelope['features']['values']` (null when the failure happened before
/// feature extraction, e.g. no reference marked -- callers only invoke this for the
/// domain-gate reasons, where it is always present). `gated` is
/// `envelope['features']['gated']`, the subset of feature names whose domain is an actual
/// eligibility check (six on chen16_noheight; "Do not gate on all sixteen",
/// docs/plan-phase/3). Rendering all sixteen -- signed Hu moments included -- would be
/// unreadable and is internal jargon, so only the gated features are shown, by their
/// plain-language label, driven by the envelope's own list rather than a second hardcoded
/// Dart order. `violations` is `envelope['weight']['violations']`, pipeline.cpp's
/// structured feature/value/allowed_min/allowed_max/direction list; a violating feature is
/// marked with `*`.
String _domainFeatureDetail(
  Map<String, double>? values,
  List<dynamic>? gated,
  List<dynamic>? violations,
) {
  if (values == null || values.isEmpty) return '';
  final violatingFeatures = <String>{
    for (final v in violations ?? const [])
      if (v is Map && v['feature'] is String) v['feature'] as String,
  };
  // Fall back to the features named in `violations` if the envelope carried no `gated`
  // list (older native build), and to nothing sensible only if both are absent.
  final names = <String>[
    for (final g in gated ?? const [])
      if (g is String) g,
  ];
  final order = names.isNotEmpty
      ? names
      : violatingFeatures.toList(growable: false);
  if (order.isEmpty) return '';
  final parts = order.map((name) {
    final raw = values[name];
    final text = raw != null ? raw.toStringAsFixed(4) : '?';
    final label = _featureLabel(name);
    return violatingFeatures.contains(name) ? '$label=$text*' : '$label=$text';
  });
  return parts.join(' ');
}

/// docs/plan-phase/4-dart-persistence-ui.md: the Chen16 feature names are internal jargon.
/// The gated ones get a plain-language label for the rejection sentence; the raw name
/// stays in the persisted `featureVector` blob for diagnostics. Never surface a Hu moment.
String _featureLabel(String feature) => switch (feature) {
  'mask_area' => 'body area',
  'convex_hull_area' => 'body area (outline hull)',
  'difference' => 'area gap',
  'perimeter' => 'outline length',
  'longest' => 'body length',
  'shortest' => 'body width',
  // baseline5 fallbacks, for a manifest still on the old family.
  'RA' => 'relative area',
  'LC' => 'outline length',
  'BL' => 'body length',
  'BW' => 'body width',
  'E' => 'body outline shape',
  _ => feature,
};

/// ref_fix.md F16: renders the measured/required mask-diagonal fraction for a
/// `mask_implausibly_small` rejection, e.g. "8% of frame diagonal, 15% required".
String _maskFractionDetail(Map<String, dynamic> weightJson) {
  final measured = (weightJson['mask_diagonal_fraction'] as num?)?.toDouble();
  final required = (weightJson['min_required_fraction'] as num?)?.toDouble();
  if (measured == null || required == null) return '';
  return '${(measured * 100).toStringAsFixed(1)}% of frame diagonal, '
      '${(required * 100).toStringAsFixed(0)}% required';
}

/// TEMPORARY diagnostic (docs/fix-phase-2/1.1-manifest-input-scale-regression.md).
///
/// Prints the full pipeline envelope to the platform log in fixed-size chunks, tagged so a
/// device run can be filtered with `adb logcat -s flutter | grep INSTAHAM_ENVELOPE`. logcat
/// drops the tail of a very long single line, and the envelope's `segmentation.rungs_tried`
/// array makes it long, so the JSON is split rather than emitted whole. Delete this function
/// and its call site once phase 1.1's `mask_diagonal_fraction` reading is recorded.
void _dumpEnvelopeToLog(String scanId, Map<String, dynamic> envelope) {
  const int chunkSize = 800;
  final String encoded = jsonEncode(envelope);
  final int total = (encoded.length + chunkSize - 1) ~/ chunkSize;
  for (int i = 0; i < total; i++) {
    final int start = i * chunkSize;
    final int end = start + chunkSize < encoded.length
        ? start + chunkSize
        : encoded.length;
    // ignore: avoid_print
    print(
      'INSTAHAM_ENVELOPE $scanId ${i + 1}/$total ${encoded.substring(start, end)}',
    );
  }
}
