// Runs the real inference pipeline for one captured scan and persists the results through
// AppDatabase, exactly like insertSampleRecord()'s save calls but with real model output
// instead of random demo data. This is slice 4's "RunInferencePipelineUseCase actually
// wired into the app" (ML_implementation_plan.md section 11.3): real view + health
// classification, segmentation, and (slice R4) the C++ weight-prediction chain. Weight
// saves as unavailable whenever the manifest's weight capability is off — the default,
// per section 3.4's permanent identity-stub cutter and AGENTS.md rule 8 — and as a real
// (test-override, uncut-mask) value only when the bundled manifest was built with
// export_xgboost.py's --enable-for-testing flag; see weight_model_service.dart.
//
// TASKS.md's P0/P1 plan (2026-08-29): the view gate must run and route BEFORE reference
// marking, and must not have its label overridden by an app-invented confidence threshold
// (the model's argmax label is the rule its recorded metrics were measured under). The
// view gate is expected to have already run once at capture time
// (capture_screen.dart's `_usePhoto()`); `_resolveViewGate` below reuses that persisted
// 'view' PipelineEvent instead of re-running the model, and only falls back to running it
// here for a scan that predates this change or whose capture-time classification failed.
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/models/scan_flow.dart';
import '../../../../services/ml/health_model_service.dart';
import '../../../../services/ml/segmentation_service.dart';
import '../../../../services/ml/view_model_service.dart';
import '../../../../services/ml/weight_model_service.dart';

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
  final IHealthModelService healthModelService;
  final ISegmentationService segmentationService;
  final IWeightModelService weightModelService;

  const RunAndPersistPipelineUseCase({
    this.viewModelService = const ViewModelServiceImpl(),
    this.healthModelService = const HealthModelServiceImpl(),
    this.segmentationService = const SegmentationServiceImpl(),
    this.weightModelService = const WeightModelServiceImpl(),
  });

  /// Runs view -> (health, segmentation) -> weight(unavailable) for `scanId`'s image and
  /// writes every branch's result to `db`. Never throws: a native/ORT failure is recorded
  /// as a blocked/unavailable result rather than surfacing an exception to the UI, per
  /// AGENTS.md rule 8 (no branch ever emits a number after a failed upstream check).
  Future<void> execute(AppDatabase db, String scanId, String imagePath) async {
    try {
      final view = await resolveViewGate(db, scanId, imagePath);
      final isDorsal = view.label == 'dorsal_valid';
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

      // Both branches run regardless of each other (AGENTS.md rule 4: weight and health
      // are independent) -- a segmentation failure below degrades weight, never health.
      final health = await healthModelService.classify(imagePath);
      final healthUncertain = health.confidence < kHealthUncertainBelow;
      await db.saveHealthResult(
        scanId: scanId,
        eligible: true,
        className: health.className,
        confidence: health.confidence,
        uncertain: healthUncertain,
        modelVersion: kHealthModelVersion,
      );

      // Segmentation only serves the weight branch this pass (health runs full_frame, see
      // ML_implementation_plan.md section 1.1(c)), and weight only applies to a dorsal
      // photo (TASKS.md's pipeline) -- skip the ~40 MB YOLO pass entirely otherwise.
      int pigCount = 0;
      if (isDorsal) {
        final segmentation = await segmentationService.segment(imagePath);
        pigCount = segmentation.pigCount;
        await db.addPipelineEvent(
          scanId,
          'segmentation',
          pigCount > 0 ? 'completed' : 'no_detection',
          message: 'pig_count=$pigCount confidence=${segmentation.confidence}',
        );
      }

      // Weight: the C++ chain (mask -> construction -> cutter -> five features ->
      // XGBoost) always runs for a dorsal photo with a detected pig, but the manifest's
      // weight capability stays unavailable by default (section 3.4 of the plan; the
      // cutter is a permanent identity dummy) -- so this normally still saves as
      // unavailable. It only produces a real (test-override, uncut-mask) value when the
      // bundled manifest was built with export_xgboost.py's --enable-for-testing flag.
      var weightEligible = false;
      if (!isDorsal) {
        await db.saveWeightResult(
          scanId: scanId,
          eligible: false,
          failureReason:
              'Weight branch skipped: photo was not classified as a dorsal view.',
          modelVersion: kWeightModelVersion,
        );
      } else if (pigCount == 0) {
        await db.saveWeightResult(
          scanId: scanId,
          eligible: false,
          failureReason:
              'Weight branch unavailable, and no pig was detected in this photo.',
          modelVersion: kWeightModelVersion,
        );
      } else {
        final weight = await weightModelService.predict(imagePath);
        weightEligible = weight.eligible;
        if (weight.eligible) {
          await db.saveWeightResult(
            scanId: scanId,
            eligible: true,
            valueKg: weight.valueKg,
            ra: weight.ra,
            lc: weight.lc,
            bl: weight.bl,
            bw: weight.bw,
            e: weight.e,
            modelVersion: weight.note == null
                ? kWeightModelVersion
                : '$kWeightModelVersion (${weight.note})',
          );
        } else {
          await db.saveWeightResult(
            scanId: scanId,
            eligible: false,
            failureReason:
                weight.failureReason ??
                'Weight branch unavailable in this build (cutter is the identity stub).',
            modelVersion: kWeightModelVersion,
          );
        }
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
