// docs/fix-phase-6/3-remove-view-cards.md (F69): the "Photo framing" card and the "Photo
// check overridden" banner are removed from the results screen. Neither belongs on the
// user side -- both duplicated what the weight and health cards already say (Skipped, with
// a reason) or exposed internal routing. This test guards against either reappearing, for
// a dorsal_valid scan and a health_only scan, while the weight and health cards must still
// render.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/database/database_scope.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/results/presentation/screens/results_screen.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> seedScan({required String viewStatus}) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    await database.addPipelineEvent(scanId, 'view', viewStatus, message: '0.9');
    await database.saveWeightResult(
      scanId: scanId,
      eligible: viewStatus == 'dorsal_valid',
      valueKg: viewStatus == 'dorsal_valid' ? 82.5 : null,
      failureReason: viewStatus == 'dorsal_valid' ? null : 'Not a dorsal view.',
    );
    await database.saveHealthResult(
      scanId: scanId,
      eligible: true,
      className: 'Healthy',
      confidence: 0.85,
      uncertain: false,
      modelVersion: 'ghostnetv3-health-v1',
    );
    return scanId;
  }

  Future<void> pumpResults(WidgetTester tester, String scanId) async {
    // Same sizing workaround as health_card_cascade_test.dart: the default test surface
    // plus cacheExtent is too short for the cards below the fold to build.
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseScope(
          database: database,
          child: ResultsScreen(args: ScanFlowArgs(sessionId: scanId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final status in ['dorsal_valid', 'health_only']) {
    testWidgets(
      'a $status scan shows no "Photo framing" card and no override banner, '
      'but still shows the weight and health cards',
      (tester) async {
        final scanId = await seedScan(viewStatus: status);

        await pumpResults(tester, scanId);

        expect(find.textContaining('Photo framing'), findsNothing);
        expect(find.textContaining('Photo check overridden'), findsNothing);
        expect(find.byIcon(Icons.monitor_weight_outlined), findsOneWidget);
        expect(find.byIcon(Icons.health_and_safety_outlined), findsOneWidget);
      },
    );
  }
}
