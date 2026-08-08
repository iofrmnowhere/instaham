import '../database/app_database.dart';

class ScanWithPig {
  final ScanRecord scan;
  final Pig? pig;

  const ScanWithPig({required this.scan, this.pig});

  String get displayPigName {
    if (pig == null) return 'Unassigned scan';
    final name = pig!.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final tag = pig!.tag?.trim();
    if (tag != null && tag.isNotEmpty) return tag;
    return 'Pig ${scan.pigId}';
  }
}
