// docs/plan-4.md / docs/plan-phase-4/3-app-surfacing.md: ResultsScreen's health card must
// say when a result came from the cascade's second pass (re-checked on the isolated pig,
// after the whole photo did not read Healthy) and must never call it a confirmed diagnosis
// (AGENTS.md: never display invented model state). A result from the whole photo alone, and
// an older row with no stored stage, must read exactly as before this plan.
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

  Future<String> seedScanWithHealth({
    required double confidence,
    String? preprocessingVersion,
  }) async {
    final scanId = await database.createDraftScan(
      goal: ScanGoal.weightAndHealth,
    );
    await database.saveHealthResult(
      scanId: scanId,
      eligible: true,
      className: 'Infected_Environmental_Sunburn',
      confidence: confidence,
      uncertain: confidence < 0.60,
      modelVersion: 'ghostnetv3-health-v1',
      preprocessingVersion: preprocessingVersion,
    );
    return scanId;
  }

  Future<void> pumpResults(WidgetTester tester, String scanId) async {
    // The health card sits below the photo preview, pig-assignment card and
    // (goal.requiresReference) weight card -- taller than flutter_test's default surface
    // plus its default cacheExtent, so the health card's own widgets are never built
    // without a taller surface. This is a test-harness sizing detail, not app behaviour.
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

  testWidgets(
    'second pass (cascade_v1:segmentation_masked) shows the re-check wording, '
    'never "confirmed"',
    (tester) async {
      final scanId = await seedScanWithHealth(
        confidence: 0.72,
        preprocessingVersion: 'cascade_v1:segmentation_masked',
      );

      await pumpResults(tester, scanId);

      expect(
        find.textContaining(
          'Flagged on the whole photo, then re-checked on the pig alone',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('possible indicator, not a confirmed diagnosis'),
        findsOneWidget,
      );
      // "confirmed" only appears negated ("not a confirmed diagnosis") -- never affirming
      // the second pass, and never "verified" either.
      expect(find.textContaining('is confirmed'), findsNothing);
      expect(find.textContaining('verified'), findsNothing);
    },
  );

  testWidgets(
    'second pass result that is also uncertain keeps the review/retake advice',
    (tester) async {
      final scanId = await seedScanWithHealth(
        confidence: 0.40,
        preprocessingVersion: 'cascade_v1:segmentation_masked',
      );

      await pumpResults(tester, scanId);

      expect(
        find.textContaining(
          'This is a possible indicator, not a confirmed diagnosis. '
          'Review or retake recommended.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'first-pass-only result (cascade_v1:full_frame) reads exactly as before this plan',
    (tester) async {
      final scanId = await seedScanWithHealth(
        confidence: 0.72,
        preprocessingVersion: 'cascade_v1:full_frame',
      );

      await pumpResults(tester, scanId);

      expect(find.text('72% confidence'), findsOneWidget);
      expect(find.textContaining('re-checked on the pig alone'), findsNothing);
      expect(find.textContaining('confirmed diagnosis'), findsNothing);
    },
  );

  testWidgets(
    'a row with no stored stage (cascade off, or predates this plan) reads unchanged',
    (tester) async {
      final scanId = await seedScanWithHealth(
        confidence: 0.72,
        preprocessingVersion: null,
      );

      await pumpResults(tester, scanId);

      expect(find.text('72% confidence'), findsOneWidget);
      expect(find.textContaining('re-checked on the pig alone'), findsNothing);
    },
  );
}
