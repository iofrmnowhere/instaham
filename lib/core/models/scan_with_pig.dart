import '../database/app_database.dart';

class ScanWithPig {
  final ScanRecord scan;
  final Pig? pig;

  const ScanWithPig({required this.scan, this.pig});

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
