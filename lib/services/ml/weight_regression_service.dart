import '../../features/weight_estimation/domain/entities/weight_features.dart';

// Service for running the XGBoost weight regression model.
// Feature order is FIXED: [RA, LC, BL, BW, E]. Never reorder.
abstract interface class IWeightRegressionService {
  Future<void> loadModel();
  Future<double> predict(WeightFeatures features);
}
