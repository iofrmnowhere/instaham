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
  final double? ra;
  final double? lc;
  final double? bl;
  final double? bw;
  final double? e;
  final String? failureReason;
  final String? note;

  const WeightPredictionResult({
    required this.eligible,
    this.valueKg,
    this.ra,
    this.lc,
    this.bl,
    this.bw,
    this.e,
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
    final features = json['features'] as Map<String, dynamic>?;
    return WeightPredictionResult(
      eligible: true,
      valueKg: (json['estimated_kg'] as num?)?.toDouble(),
      ra: (features?['RA'] as num?)?.toDouble(),
      lc: (features?['LC'] as num?)?.toDouble(),
      bl: (features?['BL'] as num?)?.toDouble(),
      bw: (features?['BW'] as num?)?.toDouble(),
      e: (features?['E'] as num?)?.toDouble(),
      note: json['note'] as String?,
    );
  }
}
