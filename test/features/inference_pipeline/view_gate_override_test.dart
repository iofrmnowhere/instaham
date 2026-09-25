// docs/fix-phase-5/2-view-reject-override.md (F67), widened by
// docs/fix-phase-6/2-dialog-and-routing.md (F68): recordViewGateOverride/viewRouteOverride
// let a `reject` or `health_only` verdict be overridden toward either route ("Check health
// only" / "Check weight and health"), keyed to the exact image the override was granted
// for -- never the scan alone, for the same reason phase 1 (F66) keys the cached verdict
// itself: `_sessionId` in capture_screen.dart is reused across retakes, so a scan-scoped
// override would silently apply to every later photo in the same session.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart';
import 'package:instaham/services/ml/pipeline_service.dart';
import 'package:instaham/services/ml/view_model_service.dart';

void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String pathA;
  late String pathB;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('instaham_view_override');
    pathA = '${tempDir.path}/photo_a.jpg';
    pathB = '${tempDir.path}/photo_b.jpg';
    await File(pathA).writeAsBytes([1, 2, 3, 4]);
    await File(pathB).writeAsBytes([9, 8, 7, 6, 5]);
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'viewRouteOverride is null when no override was ever recorded',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      expect(
        await RunAndPersistPipelineUseCase.viewRouteOverride(
          database,
          scanId,
          pathA,
        ),
        isNull,
      );
    },
  );

  test(
    'viewRouteOverride round-trips dorsal_valid for the exact image an override was '
    'recorded for',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      final identity = await RunAndPersistPipelineUseCase.imageIdentityOf(
        pathA,
      );
      await RunAndPersistPipelineUseCase.recordViewGateOverride(
        database,
        scanId,
        route: 'dorsal_valid',
        overriddenLabel: 'reject',
        overriddenConfidence: 0.46,
        imageIdentity: identity,
      );

      expect(
        await RunAndPersistPipelineUseCase.viewRouteOverride(
          database,
          scanId,
          pathA,
        ),
        'dorsal_valid',
      );
    },
  );

  test(
    'viewRouteOverride round-trips health_only for the exact image an override was '
    'recorded for',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      final identity = await RunAndPersistPipelineUseCase.imageIdentityOf(
        pathA,
      );
      await RunAndPersistPipelineUseCase.recordViewGateOverride(
        database,
        scanId,
        route: 'health_only',
        overriddenLabel: 'reject',
        overriddenConfidence: 0.46,
        imageIdentity: identity,
      );

      expect(
        await RunAndPersistPipelineUseCase.viewRouteOverride(
          database,
          scanId,
          pathA,
        ),
        'health_only',
      );
    },
  );

  test(
    'a legacy status "override" row (round 9, no route) reads as dorsal_valid -- that was '
    'all it could mean before this round',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      final identity = await RunAndPersistPipelineUseCase.imageIdentityOf(
        pathA,
      );
      // Bypasses recordViewGateOverride (which never writes the bare 'override' status
      // any more) to simulate a row a round-9 build actually wrote.
      await database.addPipelineEvent(
        scanId,
        'view_override',
        'override',
        message: 'reject 0.4600',
        imageIdentity: identity,
      );

      expect(
        await RunAndPersistPipelineUseCase.viewRouteOverride(
          database,
          scanId,
          pathA,
        ),
        'dorsal_valid',
      );
    },
  );

  test(
    'viewRouteOverride does NOT leak an override recorded for a different image in the '
    'same scan (the F66-class regression this design avoids)',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      final identityA = await RunAndPersistPipelineUseCase.imageIdentityOf(
        pathA,
      );
      await RunAndPersistPipelineUseCase.recordViewGateOverride(
        database,
        scanId,
        route: 'dorsal_valid',
        overriddenLabel: 'reject',
        overriddenConfidence: 0.46,
        imageIdentity: identityA,
      );

      // Same scan (same _sessionId-derived id), a different photo: must not inherit A's
      // override.
      expect(
        await RunAndPersistPipelineUseCase.viewRouteOverride(
          database,
          scanId,
          pathB,
        ),
        isNull,
      );
    },
  );

  test('a view_override event never satisfies resolveViewGate\'s own "view" stage cache '
      '(the two must stay on separate stages)', () async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    final identity = await RunAndPersistPipelineUseCase.imageIdentityOf(pathA);
    await RunAndPersistPipelineUseCase.recordViewGateOverride(
      database,
      scanId,
      route: 'dorsal_valid',
      overriddenLabel: 'reject',
      overriddenConfidence: 0.46,
      imageIdentity: identity,
    );

    // No 'view' stage event exists yet -- only 'view_override'. resolveViewGate must
    // find nothing cached and fall through to actually classifying, not read the
    // override row as a stale 'view' verdict.
    final result = await RunAndPersistPipelineUseCase.resolveViewGate(
      database,
      scanId,
      pathA,
      viewModelService: _FixedViewModelService(
        const ViewClassificationResult(label: 'dorsal_valid', confidence: 0.9),
      ),
    );
    expect(result.label, 'dorsal_valid');
  });

  // docs/fix-phase-6/2-dialog-and-routing.md verification: execute() forwards the right
  // route for each of the five non-retake choices in fix-6.md's table (a fake pipeline
  // service records the argument it was called with).
  group('execute() forwards the chosen route to pipelineService.run()', () {
    Future<String> newScanWithView(
      AppDatabase db,
      String imagePath, {
      required String label,
    }) async {
      final scanId = await db.createDraftScan(goal: ScanGoal.weightAndHealth);
      await RunAndPersistPipelineUseCase.recordViewGate(
        db,
        scanId,
        ViewClassificationResult(label: label, confidence: 0.7),
        imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
          imagePath,
        ),
      );
      return scanId;
    }

    test(
      'reject with no override forwards null and stops at the view gate',
      () async {
        final scanId = await newScanWithView(database, pathA, label: 'reject');
        final pipelineService = _RecordingPipelineService();
        final useCase = RunAndPersistPipelineUseCase(
          viewModelService: _FixedViewModelService(
            const ViewClassificationResult(label: 'reject', confidence: 0.7),
          ),
          pipelineService: pipelineService,
        );

        await useCase.execute(database, scanId, pathA);

        expect(pipelineService.called, isFalse);
      },
    );

    test('reject overridden to health_only forwards health_only', () async {
      final scanId = await newScanWithView(database, pathA, label: 'reject');
      await RunAndPersistPipelineUseCase.recordViewGateOverride(
        database,
        scanId,
        route: 'health_only',
        overriddenLabel: 'reject',
        overriddenConfidence: 0.7,
        imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
          pathA,
        ),
      );
      final pipelineService = _RecordingPipelineService();
      final useCase = RunAndPersistPipelineUseCase(
        viewModelService: _FixedViewModelService(
          const ViewClassificationResult(label: 'reject', confidence: 0.7),
        ),
        pipelineService: pipelineService,
      );

      await useCase.execute(database, scanId, pathA);

      expect(pipelineService.lastViewRouteOverride, 'health_only');
    });

    test('reject overridden to dorsal_valid forwards dorsal_valid', () async {
      final scanId = await newScanWithView(database, pathA, label: 'reject');
      await RunAndPersistPipelineUseCase.recordViewGateOverride(
        database,
        scanId,
        route: 'dorsal_valid',
        overriddenLabel: 'reject',
        overriddenConfidence: 0.7,
        imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
          pathA,
        ),
      );
      final pipelineService = _RecordingPipelineService();
      final useCase = RunAndPersistPipelineUseCase(
        viewModelService: _FixedViewModelService(
          const ViewClassificationResult(label: 'reject', confidence: 0.7),
        ),
        pipelineService: pipelineService,
      );

      await useCase.execute(database, scanId, pathA);

      expect(pipelineService.lastViewRouteOverride, 'dorsal_valid');
    });

    test('health_only with no override forwards null', () async {
      final scanId = await newScanWithView(
        database,
        pathA,
        label: 'health_only',
      );
      final pipelineService = _RecordingPipelineService();
      final useCase = RunAndPersistPipelineUseCase(
        viewModelService: _FixedViewModelService(
          const ViewClassificationResult(label: 'health_only', confidence: 0.7),
        ),
        pipelineService: pipelineService,
      );

      await useCase.execute(database, scanId, pathA);

      expect(pipelineService.called, isTrue);
      expect(pipelineService.lastViewRouteOverride, isNull);
    });

    test(
      'health_only overridden to dorsal_valid forwards dorsal_valid',
      () async {
        final scanId = await newScanWithView(
          database,
          pathA,
          label: 'health_only',
        );
        await RunAndPersistPipelineUseCase.recordViewGateOverride(
          database,
          scanId,
          route: 'dorsal_valid',
          overriddenLabel: 'health_only',
          overriddenConfidence: 0.7,
          imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
            pathA,
          ),
        );
        final pipelineService = _RecordingPipelineService();
        final useCase = RunAndPersistPipelineUseCase(
          viewModelService: _FixedViewModelService(
            const ViewClassificationResult(
              label: 'health_only',
              confidence: 0.7,
            ),
          ),
          pipelineService: pipelineService,
        );

        await useCase.execute(database, scanId, pathA);

        expect(pipelineService.lastViewRouteOverride, 'dorsal_valid');
      },
    );
  });
}

class _FixedViewModelService implements IViewModelService {
  final ViewClassificationResult result;
  const _FixedViewModelService(this.result);

  @override
  Future<void> loadModel() async {}

  @override
  Future<ViewClassificationResult> classify(String imagePath) async => result;
}

class _RecordingPipelineService implements IPipelineService {
  bool called = false;
  String? lastViewRouteOverride;

  @override
  Future<void> loadModel() async {}

  @override
  Future<(MlStatus, Map<String, dynamic>)> run(
    String imagePath, {
    double? cmPerPixel,
    String? viewRouteOverride,
  }) async {
    called = true;
    lastViewRouteOverride = viewRouteOverride;
    return (
      MlStatus.ok,
      <String, dynamic>{
        'status': 'ok',
        'health': {'status': 'ok', 'label': 'Healthy', 'confidence': 0.8},
        'weight': {'status': 'unavailable', 'reason': 'cutter_identity_stub'},
      },
    );
  }
}
