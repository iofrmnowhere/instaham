import 'package:flutter/material.dart';
import 'core/database/app_database.dart';
import 'core/database/database_scope.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/analytics/data/repositories/drift_analytics_repository.dart';
import 'features/analytics/presentation/analytics_scope.dart';

class App extends StatefulWidget {
  final AppDatabase? database;

  const App({super.key, this.database});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AppDatabase _database = widget.database ?? AppDatabase();
  late final bool _ownsDatabase = widget.database == null;

  @override
  void dispose() {
    if (_ownsDatabase) {
      _database.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DatabaseScope(
      database: _database,
      child: AnalyticsScope(
        repository: DriftAnalyticsRepository(_database.analyticsDao),
        child: MaterialApp.router(
          title: 'INSTAHAM',
          theme: AppTheme.light,
          routerConfig: AppRouter.router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
