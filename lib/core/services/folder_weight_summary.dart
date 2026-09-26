// docs/plan-6.md (round 6, pig folders) step 2: pure functions for a folder's weight
// summary. Kept free of Drift and any database access so the latest-weight rule and the
// total/average arithmetic can be unit-tested without a database.

/// One scan's weight-relevant fields, enough to pick a pig's newest eligible weight.
class ScanWeightSample {
  final DateTime? capturedAt;
  final DateTime createdAt;
  final bool eligible;
  final double? valueKg;

  const ScanWeightSample({
    this.capturedAt,
    required this.createdAt,
    required this.eligible,
    this.valueKg,
  });

  /// docs/plan-6.md: "latest" means the newest scan by `capturedAt`, falling back to
  /// `createdAt` for scans with no capture time.
  DateTime get _sortKey => capturedAt ?? createdAt;
}

/// A pig's latest eligible weight (docs/plan-6.md): the newest scan, by [ScanWeightSample]
/// ordering, that is eligible and carries a value. Returns null when no such scan exists --
/// including when the pig's newest scan by date is ineligible but an older one is eligible,
/// since "latest" here means latest among the eligible scans, not the pig's latest scan.
double? latestEligibleWeightKg(Iterable<ScanWeightSample> scans) {
  ScanWeightSample? latest;
  for (final scan in scans) {
    if (!scan.eligible || scan.valueKg == null) continue;
    if (latest == null || scan._sortKey.isAfter(latest._sortKey)) {
      latest = scan;
    }
  }
  return latest?.valueKg;
}

/// A folder's total weight, average weight, and weighed/total pig counts, computed purely
/// from each pig's latest eligible weight.
class FolderWeightSummary {
  final double? totalKg;
  final double? averageKg;
  final int weighedCount;
  final int totalCount;

  const FolderWeightSummary({
    required this.totalKg,
    required this.averageKg,
    required this.weighedCount,
    required this.totalCount,
  });
}

/// Builds a folder's summary from each pig's latest eligible weight (`null` for a pig with
/// none). `latestWeightsKg` holds one entry per pig in the folder, in any order. Pigs with
/// no weight are left out of both `totalKg` and `averageKg` (docs/plan-6.md); when none of
/// the folder's pigs have a weight, both are `null` rather than an invented `0`.
FolderWeightSummary summarizeFolderWeights(Iterable<double?> latestWeightsKg) {
  var total = 0.0;
  var weighedCount = 0;
  var totalCount = 0;
  for (final weightKg in latestWeightsKg) {
    totalCount++;
    if (weightKg != null) {
      total += weightKg;
      weighedCount++;
    }
  }
  return FolderWeightSummary(
    totalKg: weighedCount == 0 ? null : total,
    averageKg: weighedCount == 0 ? null : total / weighedCount,
    weighedCount: weighedCount,
    totalCount: totalCount,
  );
}
