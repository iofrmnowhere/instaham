import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:instaham/app.dart';

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
  // Metric 2 — Inference latency (placeholder — implement when model is wired)
  // ---------------------------------------------------------------------------
  testWidgets('Metric 2 — Median and P95 inference latency (placeholder)', (
    tester,
  ) async {
    // TODO: Load a known test image, run the full inference pipeline N times,
    // compute median and P95 of elapsed times, then:
    //   print('INFERENCE_MEDIAN_MS: $median');
    //   print('INFERENCE_P95_MS: $p95');
    markTestSkipped('Inference pipeline not yet wired to integration test');
  });

  // ---------------------------------------------------------------------------
  // Metric 3 — Memory footprint
  // ---------------------------------------------------------------------------
  testWidgets('Metric 3 — Memory footprint during app startup', (
    tester,
  ) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    final rssBytes = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('MEMORY_RSS_BYTES: $rssBytes');
    // ignore: avoid_print
    print('MEMORY_RSS_MB: ${(rssBytes / 1024 / 1024).toStringAsFixed(1)}');

    // No hard assertion — captured for reporting purposes.
  });

  // ---------------------------------------------------------------------------
  // Metric 4 — Model asset file sizes
  // ---------------------------------------------------------------------------
  testWidgets('Metric 4 — Model asset sizes (<50 MB target each)', (
    tester,
  ) async {
    // List asset paths that are known model files. Adjust paths as needed.
    const modelAssets = <String>[
      // e.g. 'assets/models/weight_model.tflite',
      //      'assets/models/health_model.tflite',
    ];

    for (final assetPath in modelAssets) {
      final bytes = await tester.runAsync(
        () async => (await tester.binding.defaultBinaryMessenger
                .send(
                  'flutter/assets',
                  null, // triggers AssetBundle load
                ))!
            .lengthInBytes,
      );
      // ignore: avoid_print
      print('MODEL_SIZE_BYTES[$assetPath]: $bytes');
      expect(
        bytes,
        lessThan(50 * 1024 * 1024),
        reason: '$assetPath must be < 50 MB',
      );
    }

    if (modelAssets.isEmpty) {
      markTestSkipped('No model asset paths configured yet');
    }
  });

  // ---------------------------------------------------------------------------
  // Metrics 5 & 6 — Battery/thermal and quantization parity
  //
  // These require manual review of Firebase Test Lab session video/logcat.
  // They are not automatable from inside the integration test process.
  // ---------------------------------------------------------------------------
}

