// docs/plan-6.md (round 6, pig folders) step 4: the folder card's "—" fallback and its
// "N of M pigs weighed" count.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/models/folder_summary.dart';
import 'package:instaham/features/records/presentation/widgets/folder_summary_card.dart';

void main() {
  PigFolder folder({String id = 'folder-1', String name = 'Nursery'}) =>
      PigFolder(
        id: id,
        name: name,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  Future<void> pumpCard(WidgetTester tester, FolderSummary summary) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FolderSummaryCard(summary: summary)),
      ),
    );
  }

  testWidgets(
    'shows "—" for total and average when no pig in the folder has a weight',
    (tester) async {
      await pumpCard(
        tester,
        FolderSummary(
          folder: folder(),
          pigCount: 3,
          weighedCount: 0,
          totalKg: null,
          averageKg: null,
        ),
      );

      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0 of 3 pigs weighed'), findsOneWidget);
    },
  );

  testWidgets(
    'shows the total, average, and "N of M pigs weighed" when partly weighed',
    (tester) async {
      await pumpCard(
        tester,
        FolderSummary(
          folder: folder(),
          pigCount: 4,
          weighedCount: 2,
          totalKg: 100.0,
          averageKg: 50.0,
        ),
      );

      expect(find.text('100.0 kg'), findsOneWidget);
      expect(find.text('50.0 kg'), findsOneWidget);
      expect(find.text('2 of 4 pigs weighed'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    },
  );

  testWidgets('shows the folder name', (tester) async {
    await pumpCard(
      tester,
      FolderSummary(
        folder: folder(name: 'Finishing Pen'),
        pigCount: 0,
        weighedCount: 0,
        totalKg: null,
        averageKg: null,
      ),
    );

    expect(find.text('Finishing Pen'), findsOneWidget);
  });
}
