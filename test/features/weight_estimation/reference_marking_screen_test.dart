// TASKS.md W0: `AGENTS.md` rule 9 requires pin coordinates to map to the actually-displayed
// image rect, not the whole widget box. Before this fix, `reference_marking_screen.dart`
// normalized taps against the `LayoutBuilder` constraints while the photo rendered with
// `BoxFit.contain` -- wrong in whichever axis the image and widget aspect ratios disagree
// on. `computeContainedImageRect()` is the extracted, pure form of that fix.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/database/database_scope.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/weight_estimation/presentation/screens/reference_marking_screen.dart';

void main() {
  group('computeContainedImageRect (§ AGENTS.md rule 9)', () {
    test('returns null without known image dimensions', () {
      expect(
        computeContainedImageRect(
          widgetSize: const Size(300, 300),
          imageWidthPx: null,
          imageHeightPx: 400,
        ),
        isNull,
      );
    });

    test('wide image in a taller widget letterboxes top/bottom', () {
      // A 4:3 photo (1200x900 px) in a portrait 300x400 widget box: the widget is taller
      // than the image needs, so the image fills the width and is centered vertically.
      final rect = computeContainedImageRect(
        widgetSize: const Size(300, 400),
        imageWidthPx: 1200,
        imageHeightPx: 900,
      );
      expect(rect, isNotNull);
      expect(rect!.width, closeTo(300, 0.01));
      expect(rect.height, closeTo(225, 0.01)); // 300 / (4/3)
      expect(rect.left, closeTo(0, 0.01));
      expect(rect.top, closeTo(87.5, 0.01)); // (400 - 225) / 2
    });

    test('tall image in a wider widget letterboxes left/right', () {
      // A portrait 900x1200 photo in a landscape 400x300 widget box.
      final rect = computeContainedImageRect(
        widgetSize: const Size(400, 300),
        imageWidthPx: 900,
        imageHeightPx: 1200,
      );
      expect(rect, isNotNull);
      expect(rect!.height, closeTo(300, 0.01));
      expect(rect.width, closeTo(225, 0.01)); // 300 / (4/3)
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.left, closeTo(87.5, 0.01)); // (400 - 225) / 2
    });

    test('matching aspect ratio fills the widget with no letterbox', () {
      final rect = computeContainedImageRect(
        widgetSize: const Size(200, 100),
        imageWidthPx: 800,
        imageHeightPx: 400,
      );
      expect(rect, const Rect.fromLTWH(0, 0, 200, 100));
    });
  });

  group('ReferenceMarkingScreen pin placement (widget)', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => database.close());

    testWidgets('a tap in the letterbox is ignored; taps on the photo map through the '
        'displayed image rect, not the raw widget box', (tester) async {
      final scanId = await database.createDraftScan(
        goal: ScanGoal.weightAndHealth,
      );

      // A deliberately, sharply mismatched image (a tall 1:4 portrait) so it letterboxes
      // heavily left/right inside the necessarily-landscape-ish photo pane the 800x600
      // test surface leaves once the header/banner/footer chrome is laid out.
      final router = GoRouter(
        initialLocation: '/reference',
        routes: [
          GoRoute(
            path: '/reference',
            builder: (context, state) => ReferenceMarkingScreen(
              args: ScanFlowArgs(
                sessionId: scanId,
                imageWidthPx: 200,
                imageHeightPx: 800,
              ),
            ),
          ),
          GoRoute(
            path: '/analysis',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              DatabaseScope(database: database, child: child!),
        ),
      );
      await tester.pumpAndSettle();

      final photoAreaFinder = find.byKey(const Key('referencePhotoArea'));
      final photoAreaBox = tester.renderObject(photoAreaFinder) as RenderBox;
      final widgetSize = photoAreaBox.size;
      final topLeft = tester.getTopLeft(photoAreaFinder);

      final rect = computeContainedImageRect(
        widgetSize: widgetSize,
        imageWidthPx: 200,
        imageHeightPx: 800,
      )!;
      // This test is only meaningful if the photo pane's aspect ratio actually
      // disagrees with the image's -- otherwise there is no letterbox to get wrong.
      expect(rect.width, lessThan(widgetSize.width - 1));

      // Tap two points a known distance apart ALONG the letterboxed axis, at the
      // displayed rect's fractional (0.1, 0.5) and (0.9, 0.5) -- inside the photo, away
      // from its edges so the tap unambiguously lands there.
      final p1 =
          topLeft + rect.topLeft + Offset(rect.width * 0.1, rect.height * 0.5);
      final p2 =
          topLeft + rect.topLeft + Offset(rect.width * 0.9, rect.height * 0.5);
      await tester.tapAt(p1);
      await tester.pump();
      await tester.tapAt(p2);
      await tester.pump();

      // A tap inside the letterbox (well outside the displayed rect, but still inside
      // the widget) must be ignored -- both pins already placed, so this also exercises
      // the "already have 2 pins" early return, not just the letterbox rejection.
      final letterboxPoint = topLeft + const Offset(2, 2);
      await tester.tapAt(letterboxPoint);
      await tester.pump();

      await tester.tap(
        find.text('Reference is flat on the same floor plane as the pig'),
      );
      await tester.pump();
      await tester.tap(find.text('Confirm & analyze'));
      await tester.pumpAndSettle();

      final saved = await (database.select(
        database.referenceAnnotations,
      )..where((row) => row.scanId.equals(scanId))).getSingleOrNull();
      expect(saved, isNotNull);

      // The two pins are 0.8 * rect.width apart in widget pixels, which maps to
      // 0.8 * imageWidthPx (200) original-image pixels, since the rect IS the full
      // displayed image at whatever scale factor the test surface uses.
      expect(saved!.pixelLength, closeTo(0.8 * 200, 200 * 0.02));
      // Before the D1 fix, the same taps -- normalized against the full widget box
      // instead of the displayed rect -- would have UNDER-reported this distance,
      // because rect.width < widgetSize.width whenever a letterbox exists.
      final buggyPixelLength = (p2.dx - p1.dx) / widgetSize.width * 200;
      expect(saved.pixelLength, isNot(closeTo(buggyPixelLength, 1.0)));
    });
  });
}
