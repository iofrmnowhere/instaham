// docs/plan-4.md / docs/plan-phase-4/3-app-surfacing.md: `RunAndPersistPipelineUseCase.execute()`
// must write which stage produced the final health result into the existing, previously-unused
// `HealthResults.preprocessingVersion` column, read from the envelope's own
// `health.cascade.final_stage` -- never inferred from the label -- and leave it null when the
// envelope carries no `cascade` key at all (the manifest's cascade switch off, or an older
// native build), so old and new rows can be told apart.
import 'dart:io';

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

class _StubPipelineService implements IPipelineService {
  final Map<String, dynamic> healthJson;

  _StubPipelineService(this.healthJson);

  @override
  Future<void> loadModel() async {}

  @override
  Future<(MlStatus, Map<String, dynamic>)> run(
    String imagePath, {
    double? cmPerPixel,
    String? viewRouteOverride,
  }) async {
    return (
      MlStatus.ok,
      <String, dynamic>{
        'status': 'ok',
        'health': healthJson,
        'weight': {'status': 'unavailable', 'reason': 'cutter_identity_stub'},
      },
    );
  }
}

void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('instaham_cascade_persist');
    imagePath = '${tempDir.path}/image.jpg';
    await File(imagePath).writeAsBytes([1, 2, 3, 4]);
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  Future<String> runWithHealthJson(Map<String, dynamic> healthJson) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    await RunAndPersistPipelineUseCase.recordViewGate(
      database,
      scanId,
      const ViewClassificationResult(label: 'health_only', confidence: 0.9),
      imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
        imagePath,
      ),
    );
    final useCase = RunAndPersistPipelineUseCase(
      viewModelService: _FakeViewModelService(),
      pipelineService: _StubPipelineService(healthJson),
    );
    await useCase.execute(database, scanId, imagePath);
    return scanId;
  }

  test(
    'final stage full_frame (cascade did not need to run) records cascade_v1:full_frame',
    () async {
      final scanId = await runWithHealthJson({
        'status': 'ok',
        'label': 'Healthy',
        'confidence': 0.9,
        'cascade': {
          'second_stage': 'not_needed_healthy',
          'final_stage': 'full_frame',
        },
      });

      final result = await database.recordsDao.loadScanBundle(scanId);
      expect(result?.health?.preprocessingVersion, 'cascade_v1:full_frame');
    },
  );

  test(
    'final stage segmentation_masked (second pass ran) records cascade_v1:segmentation_masked',
    () async {
      final scanId = await runWithHealthJson({
        'status': 'ok',
        'label': 'Infected_Environmental_Sunburn',
        'confidence': 0.5,
        'cascade': {
          'second_stage': 'ran',
          'final_stage': 'segmentation_masked',
        },
      });

      final result = await database.recordsDao.loadScanBundle(scanId);
      expect(
        result?.health?.preprocessingVersion,
        'cascade_v1:segmentation_masked',
      );
    },
  );

  test(
    'no cascade key in the envelope (cascade off, or older native build) leaves it null',
    () async {
      final scanId = await runWithHealthJson({
        'status': 'ok',
        'label': 'Healthy',
        'confidence': 0.9,
      });

      final result = await database.recordsDao.loadScanBundle(scanId);
      expect(result?.health?.preprocessingVersion, isNull);
    },
  );
}
