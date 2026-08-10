enum MeasurementMode { referenceObject, fixedHeight }

extension MeasurementModeLabel on MeasurementMode {
  String get label => switch (this) {
    MeasurementMode.referenceObject => 'Reference',
    MeasurementMode.fixedHeight => 'Height',
  };
}
