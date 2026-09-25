// docs/fix-phase-6/2-dialog-and-routing.md: showViewChoiceDialog() -- the shared
// three-option dialog both a `reject` and a `health_only` verdict now show. A top-level
// function (not a CaptureScreen State method), so this is pumped as a bare button/dialog
// pair with no camera involved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/capture/presentation/screens/capture_screen.dart';

void main() {
  Future<ViewChoice?> pumpAndOpenDialog(
    WidgetTester tester, {
    required bool isHealthOnly,
  }) async {
    ViewChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showViewChoiceDialog(
                  context,
                  isHealthOnly: isHealthOnly,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets(
    'reject verdict: all three buttons and the reject-specific title/body are shown',
    (tester) async {
      await pumpAndOpenDialog(tester, isHealthOnly: false);

      expect(find.text('Photo not recognized'), findsOneWidget);
      expect(find.text('Retake photo'), findsOneWidget);
      expect(find.text('Check health only'), findsOneWidget);
      expect(find.text('Check weight and health'), findsOneWidget);
    },
  );

  testWidgets(
    'health_only verdict: all three buttons and the health_only-specific title/body are '
    'shown',
    (tester) async {
      await pumpAndOpenDialog(tester, isHealthOnly: true);

      expect(find.text('Weight may not be measurable'), findsOneWidget);
      expect(find.text('Retake photo'), findsOneWidget);
      expect(find.text('Check health only'), findsOneWidget);
      expect(find.text('Check weight and health'), findsOneWidget);
    },
  );

  testWidgets('tapping Retake photo returns ViewChoice.retake', (tester) async {
    ViewChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showViewChoiceDialog(
                  context,
                  isHealthOnly: false,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake photo'));
    await tester.pumpAndSettle();

    expect(result, ViewChoice.retake);
  });

  testWidgets('tapping Check health only returns ViewChoice.healthOnly', (
    tester,
  ) async {
    ViewChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showViewChoiceDialog(
                  context,
                  isHealthOnly: false,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check health only'));
    await tester.pumpAndSettle();

    expect(result, ViewChoice.healthOnly);
  });

  testWidgets(
    'tapping Check weight and health returns ViewChoice.weightAndHealth',
    (tester) async {
      ViewChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showViewChoiceDialog(
                    context,
                    isHealthOnly: false,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check weight and health'));
      await tester.pumpAndSettle();

      expect(result, ViewChoice.weightAndHealth);
    },
  );

  testWidgets(
    'dismissing the dialog (tap outside, the barrier) is treated as Retake photo',
    (tester) async {
      ViewChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showViewChoiceDialog(
                    context,
                    isHealthOnly: false,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Tap the modal barrier, well outside the dialog card, to dismiss without choosing.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, ViewChoice.retake);
    },
  );
}
