// docs/plan-6.md (round 6, pig folders) step 4: the two delete choices, plus the second
// confirmation "Delete folder and records" requires because it cannot be undone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/records/presentation/widgets/delete_folder_dialog.dart';

void main() {
  testWidgets('shows both delete choices and Cancel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDeleteFolderDialog(context, 'Nursery'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete "Nursery"?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete folder only'), findsOneWidget);
    expect(find.text('Delete folder and records'), findsOneWidget);
  });

  testWidgets(
    'Cancel returns DeleteFolderChoice.cancelled with no second dialog',
    (tester) async {
      DeleteFolderChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDeleteFolderDialog(context, 'Nursery');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, DeleteFolderChoice.cancelled);
      expect(find.text('This cannot be undone'), findsNothing);
    },
  );

  testWidgets(
    'Delete folder only returns DeleteFolderChoice.folderOnly with no second dialog',
    (tester) async {
      DeleteFolderChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDeleteFolderDialog(context, 'Nursery');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder only'));
      await tester.pumpAndSettle();

      expect(result, DeleteFolderChoice.folderOnly);
      expect(find.text('This cannot be undone'), findsNothing);
    },
  );

  testWidgets(
    'Delete folder and records asks a second confirmation before returning that choice',
    (tester) async {
      DeleteFolderChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDeleteFolderDialog(context, 'Nursery');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder and records'));
      await tester.pumpAndSettle();

      // The first dialog's choice does not resolve the function yet -- a second,
      // plainly-worded confirmation is shown first.
      expect(result, isNull);
      expect(find.text('This cannot be undone'), findsOneWidget);
      expect(find.text('Delete everything'), findsOneWidget);

      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();

      expect(result, DeleteFolderChoice.folderAndRecords);
    },
  );

  testWidgets(
    'backing out of the second confirmation returns DeleteFolderChoice.cancelled, '
    'not folderAndRecords',
    (tester) async {
      final result = await pumpAndOpenDialogThenBackOut(tester);
      expect(result, DeleteFolderChoice.cancelled);
    },
  );
}

Future<DeleteFolderChoice> pumpAndOpenDialogThenBackOut(
  WidgetTester tester,
) async {
  late DeleteFolderChoice result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDeleteFolderDialog(context, 'Nursery');
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete folder and records'));
  await tester.pumpAndSettle();
  // Cancel the second confirmation.
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();
  return result;
}
