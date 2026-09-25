// docs/fix-phase-5/1-view-verdict-cache.md (F66): resolveViewGate must key its cached
// 'view' PipelineEvent to the image it classified, not to the scan alone. capture_screen.dart
// reuses one `_sessionId` across every photo a capture screen handles (retakes), so a scan-only
// key lets a stale verdict from a previous photo answer for a new one.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart';
import 'package:instaham/services/ml/view_model_service.dart';

/// Returns a fixed verdict per image path and counts how many times it was asked to
/// classify, so a test can assert the cache was (or was not) bypassed.
class _CountingViewModelService implements IViewModelService {
  final Map<String, ViewClassificationResult> resultsByPath;
  int callCount = 0;

  _CountingViewModelService(this.resultsByPath);

  @override
  Future<void> loadModel() async {}

  @override
  Future<ViewClassificationResult> classify(String imagePath) async {
    callCount++;
    return resultsByPath[imagePath]!;
  }
}

void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String pathA;
  late String pathB;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('instaham_view_cache');
    pathA = '${tempDir.path}/photo_a.jpg';
    pathB = '${tempDir.path}/photo_b.jpg';
    // Distinct bytes -- imageIdentityOf hashes content, so these must differ from each
    // other to exercise a real mismatch, not just a different file name.
    await File(pathA).writeAsBytes([1, 2, 3, 4]);
    await File(pathB).writeAsBytes([9, 8, 7, 6, 5]);
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('resolveViewGate re-classifies and re-records when the scan\'s cached event '
      'describes a different image (F66 core fix)', () async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    final viewModelService = _CountingViewModelService({
      pathA: const ViewClassificationResult(
        label: 'dorsal_valid',
        confidence: 0.95,
      ),
      pathB: const ViewClassificationResult(label: 'reject', confidence: 0.6),
    });

    // First resolve, against image A: no stored event yet, model runs once and A's
    // verdict is recorded.
    final first = await RunAndPersistPipelineUseCase.resolveViewGate(
      database,
      scanId,
      pathA,
      viewModelService: viewModelService,
    );
    expect(first.label, 'dorsal_valid');
    expect(viewModelService.callCount, 1);

    // Same scan, a DIFFERENT image (the retake case): must not inherit A's verdict.
    final second = await RunAndPersistPipelineUseCase.resolveViewGate(
      database,
      scanId,
      pathB,
      viewModelService: viewModelService,
    );
    expect(second.label, 'reject');
    expect(viewModelService.callCount, 2);

    // Inverse: resolving against image A again returns the ORIGINAL stored verdict
    // without a model call -- pins that the caching behaviour survives the fix.
    final third = await RunAndPersistPipelineUseCase.resolveViewGate(
      database,
      scanId,
      pathA,
      viewModelService: viewModelService,
    );
    expect(third.label, 'dorsal_valid');
    expect(viewModelService.callCount, 3);
  });

  test(
    'resolveViewGate reuses a stored verdict without a model call when resolved '
    'against the same image twice in a row',
    () async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );
      final viewModelService = _CountingViewModelService({
        pathA: const ViewClassificationResult(
          label: 'health_only',
          confidence: 0.8,
        ),
      });

      final first = await RunAndPersistPipelineUseCase.resolveViewGate(
        database,
        scanId,
        pathA,
        viewModelService: viewModelService,
      );
      final second = await RunAndPersistPipelineUseCase.resolveViewGate(
        database,
        scanId,
        pathA,
        viewModelService: viewModelService,
      );

      expect(first.label, 'health_only');
      expect(second.label, 'health_only');
      expect(viewModelService.callCount, 1);
    },
  );

  test('resolveViewGate re-classifies a legacy stored event with no recorded image identity '
      '(missing identity is a mismatch, never a wildcard)', () async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    // Simulate a row written before this column existed: recordViewGate with no
    // imageIdentity, exactly what a pre-fix build or the schemaVersion 6 migration
    // leaves behind.
    await RunAndPersistPipelineUseCase.recordViewGate(
      database,
      scanId,
      const ViewClassificationResult(label: 'dorsal_valid', confidence: 0.99),
    );

    final viewModelService = _CountingViewModelService({
      pathA: const ViewClassificationResult(
        label: 'health_only',
        confidence: 0.7,
      ),
    });

    final resolved = await RunAndPersistPipelineUseCase.resolveViewGate(
      database,
      scanId,
      pathA,
      viewModelService: viewModelService,
    );

    expect(resolved.label, 'health_only');
    expect(viewModelService.callCount, 1);
  });
}
