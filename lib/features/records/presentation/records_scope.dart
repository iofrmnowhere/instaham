import 'package:flutter/widgets.dart';

import '../domain/repositories/i_records_repository.dart';

class RecordsScope extends InheritedWidget {
  final IRecordsRepository repository;

  const RecordsScope({
    super.key,
    required this.repository,
    required super.child,
  });

  static IRecordsRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RecordsScope>();
    assert(scope != null, 'RecordsScope is missing above this widget.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(RecordsScope oldWidget) =>
      repository != oldWidget.repository;
}
