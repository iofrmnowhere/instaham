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
  // docs/fix-phase-6/2-dialog-and-routing.md (F68, widens F67's bool): the chosen route
  // ('dorsal_valid' or 'health_only') when a recorded 'view_override' event's image
  // identity matches the scan's current image -- i.e. the user picked a route other than
  // the photo check's own verdict for THIS photo, not an earlier one in the same scan.
  // Null when no override applies. Computed by the caller
  // (RunAndPersistPipelineUseCase.viewRouteOverride), not by this model, since the check
  // needs to hash the image file.
  final String? viewRouteOverride;

  const LocalScanBundle({
    required this.scan,
    this.pig,
    this.reference,
    this.weight,
    this.health,
    this.viewEvent,
    this.viewRouteOverride,
  });

  // F70 (docs/fix-phase-6/2-dialog-and-routing.md): the route that actually ran -- the
  // override when present, otherwise the photo check's own verdict. Card labels (Skipped
  // vs. Unavailable) must read this, not the stored verdict alone, once a `health_only`
  // verdict can be overridden to the full route (the weight branch on such a scan then
  // genuinely failed rather than being skipped by the view gate).
  String? get effectiveRoute => viewRouteOverride ?? viewEvent?.status;
}
