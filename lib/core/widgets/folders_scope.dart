import 'package:flutter/widgets.dart';

import '../domain/repositories/i_folders_repository.dart';

/// docs/plan-6.md (round 6, pig folders): lives in `lib/core/` (like `DatabaseScope`)
/// rather than a single feature's presentation layer, because both the records feature
/// (folder screens) and the results feature (folder picker) consume it.
class FoldersScope extends InheritedWidget {
  final IFoldersRepository repository;

  const FoldersScope({
    super.key,
    required this.repository,
    required super.child,
  });

  static IFoldersRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FoldersScope>();
    assert(scope != null, 'FoldersScope is missing above this widget.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(FoldersScope oldWidget) =>
      repository != oldWidget.repository;
}
