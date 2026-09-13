import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:instaham/app.dart';
import 'package:instaham/services/ml/ml_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Metric 1 — Time-to-first-stable-frame
  //
  // Measures how long the test harness takes to pump App() to a settled state.
  // This is the in-process equivalent of cold-start: it includes Drift DB init,
  // router setup, and first-frame rendering. True OS-level cold-start (Zygote
  // fork → first frame) cannot be measured from inside the app process.
  // Target: < 2 000 ms on the lowest-end device under test.
  // ---------------------------------------------------------------------------
  testWidgets('Metric 1 — Time-to-first-stable-frame (<2 000 ms target)', (
    tester,
  ) async {
    final sw = Stopwatch()..start();

    await tester.pumpWidget(const App());

    // Settle with a generous timeout; if the app hangs the test fails clearly.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    sw.stop();

    // ignore: avoid_print
    print('COLD_START_MS: ${sw.elapsedMilliseconds}');

    expect(
      sw.elapsedMilliseconds,
      lessThan(2000),
      reason: 'Time-to-first-stable-frame must be < 2 000 ms on target device',
    );
  });

  // ---------------------------------------------------------------------------
  // Metric 3 — Memory footprint at startup
  //
  // Declared BEFORE metric 2 deliberately -- see
  // docs/metrics-phase/6.2-metric-measurement-defects.md, defect A. All three
  // testWidgets bodies in this file share one process, and integration_test
  // runs them in declaration order. Metric 2 loads every ONNX model and runs
  // ten full pipelines; if metric 3 ran after it, MEMORY_RSS_MB would be
  // post-inference memory wearing a startup label, not startup memory. This
  // ordering is the measurement contract for this metric: do not move metric
  // 3 below metric 2 again without re-reading subphase 6.2.
  // ---------------------------------------------------------------------------
  testWidgets('Metric 3 — Memory footprint at startup', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    final rssBytes = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('MEMORY_STARTUP_RSS_BYTES: $rssBytes');
    // ignore: avoid_print
    print(
      'MEMORY_STARTUP_RSS_MB: ${(rssBytes / 1024 / 1024).toStringAsFixed(1)}',
    );

    // No hard assertion — captured for reporting purposes.
  });

  // ---------------------------------------------------------------------------
  // Metric 2 — Median inference latency (and post-inference memory)
  //
  // Requires the benchmark fixture already present on the device filesystem
  // before this test runs -- see docs/metrics-phase/6.1-benchmark-fixture-asset.md
  // (option A). The image is deliberately NOT a Flutter asset, so it does not
  // ship in the production APK; it is pushed onto the device out of band:
  //   - Locally over USB:
  //     adb push <fixture image> /data/local/tmp/instaham_bench.jpg
  //   - On Firebase Test Lab, via the run command's --other-files flag
  //     (see docs/device-testing-plan.md phase 4).
  // Fixture used: test/fixtures/scenarios/01_valid_dorsal_100cm_reference/image.jpg
  // -- a fully valid dorsal capture so the pipeline runs to completion
  // (segmentation, health, and weight branches all execute); a fixture that
  // trips a gate would under-report the real cost.
  //
  // One discarded warm-up call runs before the timed loop -- see
  // docs/metrics-phase/6.2-metric-measurement-defects.md, defect B. Without
  // it, MlRuntime staging and native ORT session creation land inside
  // iteration 0 of the timed sample. inferenceRuns stays at 10 (stated here
  // per docs/metrics-phase/6-device-metrics.md task 3): that is too few
  // samples to support a real 95th-percentile index, so this reports median
  // and maximum instead of a fabricated "P95". Raising N for a real
  // percentile is deferred until metric 2 gates something (subphase 6.2,
  // option B2) -- ten timed runs plus the other two metrics already
  // approaches the Test Lab run timeout on the low-end tier.
  //
  // No cmPerPixel is passed -- this measures inference cost, not the weight
  // branch's scale-dependent behavior. No assertion: no baseline yet exists
  // across the three device tiers (docs/metrics-phase/6-device-metrics.md,
  // "Agreed targets").
  // ---------------------------------------------------------------------------
  const benchmarkImagePath = '/data/local/tmp/instaham_bench.jpg';
  const inferenceRuns = 10;

  testWidgets('Metric 2 — Median inference latency', (tester) async {
    final fixture = File(benchmarkImagePath);
    if (!await fixture.exists()) {
      fail(
        'Benchmark fixture not found at $benchmarkImagePath. It must be '
        'pushed onto the device before this test runs -- see '
        'docs/metrics-phase/6.1-benchmark-fixture-asset.md.',
      );
    }

    final runtime = await MlRuntime.instance();

    // Warm-up run, discarded: absorbs MlRuntime staging and native session
    // creation so they do not land inside the timed sample below.
    runtime.runPipeline(benchmarkImagePath);

    final elapsedMs = <int>[];
    for (var i = 0; i < inferenceRuns; i++) {
      final sw = Stopwatch()..start();
      runtime.runPipeline(benchmarkImagePath);
      sw.stop();
      elapsedMs.add(sw.elapsedMilliseconds);
    }

    elapsedMs.sort();
    final median = elapsedMs[elapsedMs.length ~/ 2];
    final max = elapsedMs.last;

    // ignore: avoid_print
    print('INFERENCE_MEDIAN_MS: $median');
    // ignore: avoid_print
    print('INFERENCE_MAX_MS: $max');
    // ignore: avoid_print
    print('INFERENCE_RUNS: $inferenceRuns');

    // Post-inference memory, kept under its own key rather than discarded --
    // this is the number that used to be mislabelled MEMORY_RSS_MB under
    // metric 3. See docs/metrics-phase/6.2-metric-measurement-defects.md,
    // defect A.
    final postInferenceRssBytes = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('MEMORY_POST_INFERENCE_RSS_BYTES: $postInferenceRssBytes');
    // ignore: avoid_print
    print(
      'MEMORY_POST_INFERENCE_RSS_MB: '
      '${(postInferenceRssBytes / 1024 / 1024).toStringAsFixed(1)}',
    );
  });

  // ---------------------------------------------------------------------------
  // Metric 4 — moved off this file. It needs no device at all: it is a plain
  // file-size stat against assets/ml/manifest.json, so it runs as a host test
  // under `flutter test` -- see docs/metrics-phase/6-device-metrics.md task 2
  // and test/assets/model_package_size_test.dart.
  //
  // Metric 5 (battery/thermal over 50 scans) has no home here or anywhere on
  // the Spark free tier -- Test Lab's 5-minute run timeout does not fit 50
  // consecutive scans. Recorded as an open, unowned §14 item; see
  // docs/metrics-phase/6-device-metrics.md task 7.
  //
  // Metric 6 (export/quantization accuracy) also needs no device: it is a
  // host test asserting the manifest's own recorded export self-check
  // deltas. See docs/metrics-phase/6-device-metrics.md task 6.
  // ---------------------------------------------------------------------------
}
