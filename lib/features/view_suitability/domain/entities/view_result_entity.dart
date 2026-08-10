/// Result from the view-suitability classifier.
/// Label is one of: 'dorsal_valid', 'reject'.
class ViewResultEntity {
  final String label;
  final double confidence;

  const ViewResultEntity({required this.label, required this.confidence});

  bool get isDorsalValid => label == 'dorsal_valid';
  bool get isReject => label == 'reject';
}
