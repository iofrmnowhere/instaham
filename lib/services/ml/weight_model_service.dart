// Service for running the C++ weight-prediction chain (segmentation -> construction ->
// cutter -> feature_calculation -> weight_prediction, instaham_ml.cpp's
// instaham_ml_predict_weight_json) via [MlRuntime].
//
// ML_implementation_plan.md revision 7, section 3.4: the cutter is a permanent C++
// identity dummy, so weight.available is false in every manifest this build ships by
// default and this service returns `eligible: false`. It only produces a real value when
// the bundled manifest was built with ML/export/export_xgboost.py's opt-in
// `--enable-for-testing` flag -- a deliberate, documented override to verify the C++
// weight stage end-to-end, never the shipped default. When it does, the number is real
// inference, not fabricated, but reads heavy because the head/neck were never removed
// from the mask (AGENTS.md rule 8 is about never inventing a number, not about hiding a
// real, biased one -- `note` below states the bias plainly).
import 'ml_runtime.dart';

abstract interface class IWeightModelService {
  Future<void> loadModel();
  Future<WeightPredictionResult> predict(String imagePath);
}

class WeightPredictionResult {
  final bool eligible;
  final double? valueKg;

  /// The envelope's `features.values` block, passed through untouched -- the service does
  /// not know feature names (docs/plan-phase/4-dart-persistence-ui.md).
  final Map<String, double>? features;
  final String? featureFamily;
  final String? failureReason;
  final String? note;

  const WeightPredictionResult({
    required this.eligible,
    this.valueKg,
    this.features,
    this.featureFamily,
    this.failureReason,
    this.note,
  });
}

class WeightModelServiceImpl implements IWeightModelService {
  const WeightModelServiceImpl();

  @override
  Future<void> loadModel() async {
    await MlRuntime.instance();
  }

  @override
  Future<WeightPredictionResult> predict(String imagePath) async {
    final runtime = await MlRuntime.instance();
    final (status, json) = runtime.predictWeight(imagePath);
    if (status != MlStatus.ok || json['status'] != 'ok') {
      final reason = json['reason'] as String? ?? json['message'] as String?;
      return WeightPredictionResult(
        eligible: false,
        failureReason: reason ?? 'Weight branch unavailable in this build.',
      );
    }
    // The standalone predict payload carries `features` as a flat {name: value} map and
    // `feature_family` at the top level; the pipeline envelope nests the same values under
    // `features.values` with `features.family`. Accept either without knowing any names.
    final featuresBlock = json['features'] as Map<String, dynamic>?;
    final values =
        (featuresBlock?['values'] as Map<String, dynamic>?) ?? featuresBlock;
    return WeightPredictionResult(
      eligible: true,
      valueKg: (json['estimated_kg'] as num?)?.toDouble(),
      features: values == null
          ? null
          : {
              for (final entry in values.entries)
                if (entry.value is num)
                  entry.key: (entry.value as num).toDouble(),
            },
      featureFamily:
          (json['feature_family'] ?? featuresBlock?['family']) as String?,
      note: json['note'] as String?,
    );
  }
}
