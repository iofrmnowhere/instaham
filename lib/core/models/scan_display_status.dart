import 'scan_flow.dart';

/// Display-only status values that do not exist in the stored `ScanRecords.status` column.
/// docs/fix-7.md F73: a scan whose weight branch fails but whose health branch succeeds is
/// worked out at display time, not written back -- older rows keep reading correctly with no
/// migration.
abstract final class ScanDisplayStatuses {
  static const healthOnly = 'health_only';
}

/// Resolves the status shown to the user for a scan whose stored status is
/// [ScanStatuses.blocked]. Every other stored status is returned unchanged.
///
/// - Stored `blocked`, no weight value, but an eligible health result -> "Health only": the
///   health branch produced something usable even though weight did not.
/// - Stored `blocked`, neither a weight value nor an eligible health result -> "Blocked":
///   nothing usable came out of this scan.
///
/// [hasWeightValue] and [hasEligibleHealth] describe the scan's `WeightResults` and
/// `HealthResults` rows, not the stored status, so callers pass them from a join rather than
/// re-deriving them here.
String displayScanStatus({
  required String storedStatus,
  required bool hasWeightValue,
  required bool hasEligibleHealth,
}) {
  if (storedStatus != ScanStatuses.blocked) return storedStatus;
  if (!hasWeightValue && hasEligibleHealth) {
    return ScanDisplayStatuses.healthOnly;
  }
  return ScanStatuses.blocked;
}
