// TASKS.md W3/§7.4: `RunAndPersistPipelineUseCase.execute()` must forward the confirmed
// reference object's cm/pixel to `pipelineService.run()` ONLY when the annotation is both
// user-confirmed and coplanar-confirmed (AGENTS.md rule 7) -- never a guess, and never an
// in-progress or predates-this-feature annotation.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart';
import 'package:instaham/services/ml/pipeline_service.dart';
import 'package:instaham/services/ml/view_model_service.dart';

class _FakeViewModelService implements IViewModelService {
  @override
  Future<void> loadModel() async {}

  @override
  Future<ViewClassificationResult> classify(String imagePath) async {
    return const ViewClassificationResult(
      label: 'health_only',
      confidence: 0.9,
    );
  }
}

class _RecordingPipelineService implements IPipelineService {
  double? lastCmPerPixel;
  bool called = false;

  @override
  Future<void> loadModel() async {}

  @override
  Future<(MlStatus, Map<String, dynamic>)> run(
    String imagePath, {
    double? cmPerPixel,
  }) async {
    called = true;
    lastCmPerPixel = cmPerPixel;
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

void main() {
  late AppDatabase database;
  late _RecordingPipelineService pipelineService;
  late RunAndPersistPipelineUseCase useCase;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    pipelineService = _RecordingPipelineService();
    useCase = RunAndPersistPipelineUseCase(
      viewModelService: _FakeViewModelService(),
      pipelineService: pipelineService,
    );
  });

  tearDown(() => database.close());

  Future<String> newScanWithAnnotation({
    required bool userConfirmed,
    required bool sameFloorPlaneConfirmed,
    double? cmPerPixel,
  }) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    // execute() -> resolveViewGate() reuses an existing 'view' PipelineEvent instead of
    // calling viewModelService.classify() again (see the class doc comment) -- pre-seed
    // one so this test never needs a real MlRuntime/native library to resolve the view
    // gate; unrelated to the scale-forwarding behaviour under test.
    await RunAndPersistPipelineUseCase.recordViewGate(
      database,
      scanId,
      const ViewClassificationResult(label: 'health_only', confidence: 0.9),
    );
    await database.saveReferenceAnnotation(
      scanId: scanId,
      reference: ReferenceSelection.meterStick,
      startX: 0.1,
      startY: 0.5,
      endX: 0.9,
      endY: 0.5,
      pixelLength: 400,
      cmPerPixel: cmPerPixel,
      source: 'manual',
      sameFloorPlaneConfirmed: sameFloorPlaneConfirmed,
    );
    if (!userConfirmed) {
      // saveReferenceAnnotation always sets userConfirmed: true (reference_marking_screen
      // only calls it on confirm) -- simulate a pre-confirmation / legacy row directly.
      await (database.update(
        database.referenceAnnotations,
      )..where((row) => row.scanId.equals(scanId))).write(
        const ReferenceAnnotationsCompanion(userConfirmed: Value(false)),
      );
    }
    return scanId;
  }

  test(
    'forwards cmPerPixel when the annotation is confirmed and coplanar',
    () async {
      final scanId = await newScanWithAnnotation(
        userConfirmed: true,
        sameFloorPlaneConfirmed: true,
        cmPerPixel: 0.2319,
      );

      await useCase.execute(database, scanId, '/fake/image.jpg');

      expect(pipelineService.called, isTrue);
      expect(pipelineService.lastCmPerPixel, 0.2319);
    },
  );

  test(
    'withholds cmPerPixel when the annotation is not user-confirmed',
    () async {
      final scanId = await newScanWithAnnotation(
        userConfirmed: false,
        sameFloorPlaneConfirmed: true,
        cmPerPixel: 0.2319,
      );

      await useCase.execute(database, scanId, '/fake/image.jpg');

      expect(pipelineService.called, isTrue);
      expect(pipelineService.lastCmPerPixel, isNull);
    },
  );

  test(
    'withholds cmPerPixel when the reference is not confirmed coplanar with the pig',
    () async {
      final scanId = await newScanWithAnnotation(
        userConfirmed: true,
        sameFloorPlaneConfirmed: false,
        cmPerPixel: 0.2319,
      );

      await useCase.execute(database, scanId, '/fake/image.jpg');

      expect(pipelineService.called, isTrue);
      expect(pipelineService.lastCmPerPixel, isNull);
    },
  );

  test(
    'withholds cmPerPixel when no reference annotation exists at all',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      await RunAndPersistPipelineUseCase.recordViewGate(
        database,
        scanId,
        const ViewClassificationResult(label: 'health_only', confidence: 0.9),
      );

      await useCase.execute(database, scanId, '/fake/image.jpg');

      expect(pipelineService.called, isTrue);
      expect(pipelineService.lastCmPerPixel, isNull);
    },
  );
}
