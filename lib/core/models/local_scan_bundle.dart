import '../database/app_database.dart';

class LocalScanBundle {
  final ScanRecord scan;
  final Pig? pig;
  final ReferenceAnnotation? reference;
  final WeightResult? weight;
  final HealthResult? health;

  const LocalScanBundle({
    required this.scan,
    this.pig,
    this.reference,
    this.weight,
    this.health,
  });
}
