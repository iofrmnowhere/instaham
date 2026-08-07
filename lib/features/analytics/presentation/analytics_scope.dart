import 'package:flutter/widgets.dart';

import '../domain/repositories/i_analytics_repository.dart';

class AnalyticsScope extends InheritedWidget {
  final IAnalyticsRepository repository;

  const AnalyticsScope({
    super.key,
    required this.repository,
    required super.child,
  });

  static IAnalyticsRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AnalyticsScope>();
    assert(scope != null, 'AnalyticsScope is missing above this widget.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(AnalyticsScope oldWidget) =>
      repository != oldWidget.repository;
}
