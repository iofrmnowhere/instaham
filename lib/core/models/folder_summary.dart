import '../database/app_database.dart';

/// docs/plan-6.md (round 6, pig folders): one folder's card-level summary, built from each
/// of its pigs' latest eligible weight (see `lib/core/services/folder_weight_summary.dart`).
/// `totalKg`/`averageKg` are null, not zero, when none of the folder's pigs have a weight yet.
class FolderSummary {
  final PigFolder folder;
  final int pigCount;
  final int weighedCount;
  final double? totalKg;
  final double? averageKg;

  const FolderSummary({
    required this.folder,
    required this.pigCount,
    required this.weighedCount,
    required this.totalKg,
    required this.averageKg,
  });
}
