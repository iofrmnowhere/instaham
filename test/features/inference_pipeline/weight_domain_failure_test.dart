// ref_fix.md F6/F7/F16/F17: a weight-branch rejection must be diagnosable from what gets
// persisted, not just from a generic message -- the feature vector that was measured is
// stored even on the ineligible path, a `features` pipeline event is written on every run,
// each of pipeline.cpp's classify_domain_violation() reasons maps to its own,
// correctly-targeted user-facing message, and the rendered detail always shows all five
// RA/LC/BL/BW/E values (marking which violated) rather than only the violating ones.
//
// docs/plan-phase/4-dart-persistence-ui.md: the rendered detail now shows the GATED
// features only, by plain-language label ("relative area", "body outline shape", ...),
// driven by the envelope's own `features.gated` list; the measured vector is persisted as
// a family-tagged JSON blob in `feature_vector`, not the five deprecated columns.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
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
      label: 'dorsal_valid',
      confidence: 0.95,
    );
  }
}

class _StubPipelineService implements IPipelineService {
  final Map<String, dynamic> envelope;

  _StubPipelineService(this.envelope);

  @override
  Future<void> loadModel() async {}

  @override
  Future<(MlStatus, Map<String, dynamic>)> run(
    String imagePath, {
    double? cmPerPixel,
    String? viewRouteOverride,
  }) async {
    return (MlStatus.ok, envelope);
  }
}

/// Builds an envelope shaped like pipeline.cpp's domain-gate rejection: `features.values`
/// carries all five measurements, `weight.violations` is the structured
/// feature/value/allowed_min/allowed_max/direction list `feature_in_domain()` builds.
Map<String, dynamic> _envelopeWithWeightReason(
  String reason, {
  Map<String, dynamic>? features,
  List<Map<String, dynamic>>? violations,
  Map<String, dynamic>? extraWeightFields,
  List<String> gated = const ['RA', 'LC', 'BL', 'BW', 'E'],
}) {
  final weight = <String, dynamic>{'status': 'unavailable', 'reason': reason};
  if (violations != null) weight['violations'] = violations;
  if (extraWeightFields != null) weight.addAll(extraWeightFields);
  return <String, dynamic>{
    'status': 'ok',
    'health': {'status': 'ok', 'label': 'Healthy', 'confidence': 0.8},
    'features': {
      'status': 'provisional',
      'family': 'baseline5',
      'order': ['RA', 'LC', 'BL', 'BW', 'E'],
      'gated': gated,
      'values':
          features ??
          {'RA': 0.03, 'LC': 500.0, 'BL': 200.0, 'BW': 90.0, 'E': 0.7},
      'measured_on': 'training_normalized_mask',
    },
    'weight': weight,
  };
}

void main() {
  late AppDatabase database;
  late RunAndPersistPipelineUseCase useCase;
  late Directory tempDir;
  late String imagePath;

  Future<String> newScan(Map<String, dynamic> envelope) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    // resolveViewGate (F66 fix) hashes `imagePath` to key this cached 'view' event, so
    // it must match the real file execute() below is given.
    await RunAndPersistPipelineUseCase.recordViewGate(
      database,
      scanId,
      const ViewClassificationResult(label: 'dorsal_valid', confidence: 0.95),
      imageIdentity: await RunAndPersistPipelineUseCase.imageIdentityOf(
        imagePath,
      ),
    );
    useCase = RunAndPersistPipelineUseCase(
      viewModelService: _FakeViewModelService(),
      pipelineService: _StubPipelineService(envelope),
    );
    return scanId;
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('instaham_weight_domain');
    imagePath = '${tempDir.path}/image.jpg';
    await File(imagePath).writeAsBytes([1, 2, 3, 4]);
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'a domain-rejected run persists the measured feature vector, not nulls',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason(
          'subject_smaller_than_trained',
          features: {
            'RA': 0.03,
            'LC': 500.0,
            'BL': 200.0,
            'BW': 90.0,
            'E': 0.7,
          },
        ),
      );

      await useCase.execute(database, scanId, imagePath);

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.eligible, isFalse);
      // docs/plan-phase/4: the measured vector now lands in the family-tagged blob, not
      // the five deprecated columns.
      expect(row.featureRa, isNull);
      final vector = jsonDecode(row.featureVector!) as Map<String, dynamic>;
      expect(vector['family'], 'baseline5');
      expect((vector['values'] as Map)['RA'], 0.03);
      expect((vector['values'] as Map)['LC'], 500.0);
      expect((vector['values'] as Map)['E'], 0.7);
      expect(row.featureFamily, 'baseline5');
    },
  );

  test(
    'a `features` pipeline event is written on every run, success or failure',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason('mask_shape_out_of_domain'),
      );

      await useCase.execute(database, scanId, imagePath);

      final events =
          await (database.select(database.pipelineEvents)..where(
                (row) =>
                    row.scanId.equals(scanId) & row.stage.equals('features'),
              ))
              .get();

      expect(events, hasLength(1));
      expect(events.single.message, contains('"RA"'));
    },
  );

  test(
    'mask_shape_out_of_domain gets its own message, pointing at the photo not the reference',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason(
          'mask_shape_out_of_domain',
          violations: [
            {
              'feature': 'E',
              'value': 0.6,
              'allowed_min': 0.86,
              'allowed_max': 1.03,
              'direction': 'low',
            },
          ],
        ),
      );

      await useCase.execute(database, scanId, imagePath);

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.failureReason, contains('Retake the photo'));
      expect(row.failureReason, isNot(contains('reference object')));
      // ref_fix.md F17 + docs/plan-phase/4: only the violating feature carries the '*'
      // marker, and features are labelled in plain language.
      expect(row.failureReason, contains('body outline shape=0.7000*'));
      expect(row.failureReason, contains('relative area=0.0300'));
      expect(row.failureReason, isNot(contains('relative area=0.0300*')));
    },
  );

  test(
    'subject_smaller_than_trained gets its own message, not the reference-object advice',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason('subject_smaller_than_trained'),
      );

      await useCase.execute(database, scanId, imagePath);

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.failureReason, contains('smaller than any animal'));
      expect(row.failureReason, isNot(contains('Re-check the reference')));
    },
  );

  test('features_out_of_training_domain keeps the reference-object advice and marks the '
      'violating feature while still showing all five', () async {
    final scanId = await newScan(
      _envelopeWithWeightReason(
        'features_out_of_training_domain',
        violations: [
          {
            'feature': 'RA',
            'value': 0.03,
            'allowed_min': 0.06,
            'allowed_max': 0.2,
            'direction': 'low',
          },
        ],
      ),
    );

    await useCase.execute(database, scanId, imagePath);

    final row = await (database.select(
      database.weightResults,
    )..where((row) => row.scanId.equals(scanId))).getSingle();

    expect(
      row.failureReason,
      contains('Re-check the reference object placement'),
    );
    // ref_fix.md F17: the violating feature is marked...
    expect(row.failureReason, contains('relative area=0.0300*'));
    // ...but every other GATED feature still appears, unmarked -- round 2 omitted them
    // entirely, which hid whether a feature was in-range or simply never reported.
    expect(row.failureReason, contains('outline length=500.0000'));
    expect(row.failureReason, contains('body length=200.0000'));
    expect(row.failureReason, contains('body width=90.0000'));
    expect(row.failureReason, contains('body outline shape=0.7000'));
    expect(row.failureReason, isNot(contains('body outline shape=0.7000*')));
  });

  test(
    'mask_implausibly_small (F16) reports the measured/required frame fraction, not '
    'a domain violation',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason(
          'mask_implausibly_small',
          extraWeightFields: {
            'mask_diagonal_fraction': 0.08,
            'min_required_fraction': 0.15,
          },
        ),
      );

      await useCase.execute(database, scanId, imagePath);

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.failureReason, contains('only a small fragment was found'));
      expect(row.failureReason, contains('Retake the photo'));
      expect(row.failureReason, contains('8.0% of frame diagonal'));
      expect(row.failureReason, contains('15% required'));
    },
  );

  test(
    'an unmapped reason is surfaced verbatim, never disguised as the cutter-stub message',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason('some_future_reason'),
      );

      await useCase.execute(database, scanId, imagePath);

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.failureReason, contains('some_future_reason'));
      expect(row.failureReason, isNot(contains('identity stub')));
    },
  );
}
