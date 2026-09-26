import '../database/app_database.dart';

/// docs/plan-6.md (round 6, pig folders): a pig as shown in a folder detail screen, with
/// its latest eligible weight, or null if it has none yet.
class FolderPig {
  final Pig pig;
  final double? latestWeightKg;

  const FolderPig({required this.pig, this.latestWeightKg});
}
