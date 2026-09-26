import '../database/app_database.dart';
import 'scan_display_status.dart';

class ScanWithPig {
  final ScanRecord scan;
  final Pig? pig;

  /// Whether this scan's `WeightResults` row carries a value. False for a scan with no
  /// weight row at all, matching `hasEligibleHealth` below.
  final bool hasWeightValue;

  /// Whether this scan's `HealthResults` row is eligible. False for a scan with no health
  /// row at all.
  final bool hasEligibleHealth;

  const ScanWithPig({
    required this.scan,
    this.pig,
    this.hasWeightValue = false,
    this.hasEligibleHealth = false,
  });

  /// docs/fix-7.md F73: the status to show the user, distinguishing "Health only" from
  /// "Blocked" without touching the stored `scan.status`.
  String get displayStatus => displayScanStatus(
    storedStatus: scan.status,
    hasWeightValue: hasWeightValue,
    hasEligibleHealth: hasEligibleHealth,
  );

  String pigLabel({bool disambiguate = false}) {
    if (pig == null) return 'Unassigned scan';
    final name = pig!.displayName?.trim();
    final tag = pig!.tag?.trim();
    final base = (name != null && name.isNotEmpty)
        ? name
        : (tag != null && tag.isNotEmpty ? tag : 'Pig ${scan.pigId}');
    if (disambiguate && tag != null && tag.isNotEmpty) {
      return '$base · #$tag';
    }
    return base;
  }

  String get displayPigName => pigLabel();
}
