import '../database/app_database.dart';

class LocalScanBundle {
  final ScanRecord scan;
  final Pig? pig;
  final ReferenceAnnotation? reference;
  final WeightResult? weight;
  final HealthResult? health;
  // The most recent 'view' PipelineEvent for this scan, if the view gate has run.
  // `status` holds the decided label ('dorsal_valid' | 'health_only' | 'reject'),
  // `message` the confidence text. See TASKS.md's P0/P2 plan.
  final PipelineEvent? viewEvent;

  const LocalScanBundle({
    required this.scan,
    this.pig,
    this.reference,
    this.weight,
    this.health,
    this.viewEvent,
  });
}
