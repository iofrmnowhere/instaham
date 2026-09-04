// ref_fix.md F6/F7/F16/F17: a weight-branch rejection must be diagnosable from what gets
// persisted, not just from a generic message -- the feature vector that was measured is
// stored even on the ineligible path, a `features` pipeline event is written on every run,
// each of pipeline.cpp's classify_domain_violation() reasons maps to its own,
// correctly-targeted user-facing message, and the rendered detail always shows all five
// RA/LC/BL/BW/E values (marking which violated) rather than only the violating ones.
import 'package:drift/drift.dart';
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

  Future<String> newScan(Map<String, dynamic> envelope) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    await RunAndPersistPipelineUseCase.recordViewGate(
      database,
      scanId,
      const ViewClassificationResult(label: 'dorsal_valid', confidence: 0.95),
    );
    useCase = RunAndPersistPipelineUseCase(
      viewModelService: _FakeViewModelService(),
      pipelineService: _StubPipelineService(envelope),
    );
    return scanId;
  }

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

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

      await useCase.execute(database, scanId, '/fake/image.jpg');

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.eligible, isFalse);
      expect(row.featureRa, 0.03);
      expect(row.featureLc, 500.0);
      expect(row.featureBl, 200.0);
      expect(row.featureBw, 90.0);
      expect(row.featureE, 0.7);
    },
  );

  test(
    'a `features` pipeline event is written on every run, success or failure',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason('mask_shape_out_of_domain'),
      );

      await useCase.execute(database, scanId, '/fake/image.jpg');

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

      await useCase.execute(database, scanId, '/fake/image.jpg');

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.failureReason, contains('Retake the photo'));
      expect(row.failureReason, isNot(contains('reference object')));
      // ref_fix.md F17: only the violating feature (E, the default features map's 0.7)
      // carries the '*' marker.
      expect(row.failureReason, contains('E=0.7000*'));
      expect(row.failureReason, contains('RA=0.0300'));
      expect(row.failureReason, isNot(contains('RA=0.0300*')));
    },
  );

  test(
    'subject_smaller_than_trained gets its own message, not the reference-object advice',
    () async {
      final scanId = await newScan(
        _envelopeWithWeightReason('subject_smaller_than_trained'),
      );

      await useCase.execute(database, scanId, '/fake/image.jpg');

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

    await useCase.execute(database, scanId, '/fake/image.jpg');

    final row = await (database.select(
      database.weightResults,
    )..where((row) => row.scanId.equals(scanId))).getSingle();

    expect(
      row.failureReason,
      contains('Re-check the reference object placement'),
    );
    // ref_fix.md F17: the violating feature is marked...
    expect(row.failureReason, contains('RA=0.0300*'));
    // ...but every other feature still appears, unmarked -- round 2 omitted them
    // entirely, which hid whether a feature was in-range or simply never reported.
    expect(row.failureReason, contains('LC=500.0000'));
    expect(row.failureReason, contains('BL=200.0000'));
    expect(row.failureReason, contains('BW=90.0000'));
    expect(row.failureReason, contains('E=0.7000'));
    expect(row.failureReason, isNot(contains('E=0.7000*')));
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

      await useCase.execute(database, scanId, '/fake/image.jpg');

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

      await useCase.execute(database, scanId, '/fake/image.jpg');

      final row = await (database.select(
        database.weightResults,
      )..where((row) => row.scanId.equals(scanId))).getSingle();

      expect(row.failureReason, contains('some_future_reason'));
      expect(row.failureReason, isNot(contains('identity stub')));
    },
  );
}
