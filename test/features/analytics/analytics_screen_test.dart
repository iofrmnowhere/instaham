import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/analytics/data/repositories/mock_analytics_repository.dart';
import 'package:instaham/features/analytics/presentation/analytics_scope.dart';
import 'package:instaham/features/analytics/presentation/screens/analytics_screen.dart';

void main() {
  testWidgets(
    'AnalyticsScreen displays empty state when repository has no scans',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        AnalyticsScope(
          repository: MockAnalyticsRepository(),
          child: const MaterialApp(home: AnalyticsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Track trends and patterns for weight and health'),
        findsOneWidget,
      );
      expect(find.text('No analytics yet'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weight Analytics').last);
      await tester.pumpAndSettle();
      expect(find.text('No weight analytics yet'), findsOneWidget);
    },
  );
}
