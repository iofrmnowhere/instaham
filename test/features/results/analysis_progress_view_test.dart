// docs/plan-phase-2/3-validation-docs.md phase 3: AnalysisProgressView (plan-phase-2/
// 2-progress-ui.md) must render the phase Dart is actually in and never fabricate a
// per-stage completed state (AGENTS.md "Never display invented model scores, predictions,
// or completed states").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/features/results/presentation/widgets/analysis_progress_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AnalysisProgressView', () {
    testWidgets('renders the given phase label and an animating indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const AnalysisProgressView(phase: AnalysisPhase.runningPipeline)),
      );

      expect(find.text('Analyzing the photo…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('updates its label when the phase prop changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const AnalysisProgressView(phase: AnalysisPhase.loadingBundle)),
      );
      expect(find.text('Loading the saved scan…'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const AnalysisProgressView(phase: AnalysisPhase.reloadingBundle)),
      );
      expect(find.text('Finishing up…'), findsOneWidget);
      expect(find.text('Loading the saved scan…'), findsNothing);
    });

    testWidgets('renders no fabricated stage-completion text', (tester) async {
      await tester.pumpWidget(
        _wrap(const AnalysisProgressView(phase: AnalysisPhase.runningPipeline)),
      );

      // AGENTS.md: no invented per-stage checklist (segmentation/measurement/weight are
      // opaque to Dart while the native call runs) and no cancel affordance.
      for (final fabricated in [
        'Segmentation',
        'Segmenting',
        'Measuring',
        'Weight estimated',
        'Complete',
        'Done',
        'Cancel',
      ]) {
        expect(find.textContaining(fabricated), findsNothing);
      }
    });

    testWidgets('elapsed counter is live-region accessible from the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const AnalysisProgressView(phase: AnalysisPhase.runningPipeline)),
      );

      // The counter reads from a real Stopwatch, not the test binding's fake Timer clock,
      // so `tester.pump(duration)` cannot fast-forward it -- this checks the accessible
      // wiring (live region, label text) rather than the wall-clock value.
      expect(find.text('0 s'), findsOneWidget);

      final semantics = tester.getSemantics(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      );
      expect(
        semantics.label,
        contains('Analyzing the photo… 0 seconds elapsed'),
      );

      // Let the 1s ticker fire at least once under the test binding's fake async clock so
      // pumpWidget's teardown doesn't trip a pending-timer failure, then let the widget
      // dispose its own Timer via pumpWidget's implicit unmount.
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
