import 'package:flutter/widgets.dart';

import 'app_database.dart';

class DatabaseScope extends InheritedWidget {
  final AppDatabase database;

  const DatabaseScope({
    super.key,
    required this.database,
    required super.child,
  });

  static AppDatabase of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DatabaseScope>();
    assert(scope != null, 'DatabaseScope is missing above this widget.');
    return scope!.database;
  }

  @override
  bool updateShouldNotify(DatabaseScope oldWidget) =>
      database != oldWidget.database;
}
