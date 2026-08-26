# INSTAHAM Device Testing Plan — Firebase Test Lab

## Overview

Device testing for INSTAHAM is conducted using **Firebase Test Lab** (Google LLC), which provides access to real physical Android devices in a cloud-hosted environment. This satisfies §14 of the app requirements without needing access to personal hardware.

> [!NOTE]
> All benchmark results reported in this project were obtained from real physical devices via Firebase Test Lab, **not** from GPU/desktop notebook latency.

---

## Cost

### Spark plan (no-cost) — what this project uses

| Resource | Free Quota |
|---|---|
| Physical devices | **5 test runs/day** |
| Virtual devices | **10 test runs/day** |

No billing account or credit card required on Spark. Running on 2 physical devices = 2 of your 5 daily runs — well within the free quota.

### Blaze plan (if you ever upgrade)

| Resource | No-cost time included | Overage rate |
|---|---|---|
| Physical devices | 30 minutes/day | $5/hour (billed per minute) |
| Virtual devices | 60 minutes/day | $1/hour (billed per minute) |

Blaze requires a linked billing account. The 30/60-minute time budgets apply to Blaze only — they are not part of Spark.

---

## Prerequisites (One-time Setup)

### 1. Create a Firebase Project
- Go to [console.firebase.google.com](https://console.firebase.google.com)
- Create a new project (Spark plan is the default — no billing account needed)
- No Firebase SDK needs to be added to the app — Test Lab works with plain APKs

### 2. Install and Authenticate the Google Cloud CLI
```powershell
# Download from: https://cloud.google.com/sdk/docs/install-sdk#windows
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

---

## Phase 1 — Add `integration_test` Dependency

Add to `pubspec.yaml` under `dev_dependencies`:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

> [!IMPORTANT]
> Do **not** add `flutter_driver` — it is the deprecated legacy approach. `integration_test` alone is sufficient.

Run:
```powershell
flutter pub get
```

---

## Phase 2 — Write the Integration Test

Create `integration_test/benchmark_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:instaham/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Metric 1 — Time-to-first-stable-frame
  //
  // Uses tester.pumpWidget(App()) — NOT app.main().
  // Calling app.main() inside a test causes a double-init crash because
  // IntegrationTestWidgetsFlutterBinding is already active. pumpWidget is
  // the correct API. Measures Drift DB init + router setup + first frame.
  // True OS cold-start (Zygote fork → first frame) cannot be measured from
  // inside the app process and is not reported here.
  testWidgets('Metric 1 — Time-to-first-stable-frame (<2 000 ms target)', (
    tester,
  ) async {
    final sw = Stopwatch()..start();
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    sw.stop();
    print('COLD_START_MS: \${sw.elapsedMilliseconds}');
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'Time-to-first-stable-frame must be < 2 000 ms on target device');
  });

  // Metric 2 — Inference latency (placeholder)
  testWidgets('Metric 2 — Median and P95 inference latency (placeholder)', (
    tester,
  ) async {
    // TODO: wire inference pipeline, then:
    //   print('INFERENCE_MEDIAN_MS: \$median');
    //   print('INFERENCE_P95_MS: \$p95');
    markTestSkipped('Inference pipeline not yet wired to integration test');
  });

  // Metric 3 — Memory footprint at startup
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
    print('MEMORY_RSS_BYTES: \$rssBytes');
    print('MEMORY_RSS_MB: \${(rssBytes / 1024 / 1024).toStringAsFixed(1)}');
  });

  // Metric 4 — Model asset file sizes
  testWidgets('Metric 4 — Model asset sizes (<50 MB target each)', (
    tester,
  ) async {
    const modelAssets = <String>[
      // Add bundled model asset paths here when available.
    ];
    if (modelAssets.isEmpty) {
      markTestSkipped('No model asset paths configured yet');
    }
  });

  // Metrics 5 & 6 require manual review of Firebase Test Lab
  // session video and logcat — not automatable from inside the process.
}
```

---

## Phase 3 — Build the APKs

**One command builds both the app APK and the test APK**, scoped to the integration test file:

```powershell
# From the android subfolder — builds both the app APK and test APK in one step
cd android
.\gradlew.bat app:assembleDebug app:assembleDebugAndroidTest -Ptarget=integration_test/benchmark_test.dart
```

> [!IMPORTANT]
> The Dart test code (`benchmark_test.dart`) is compiled **into the app APK** via the `-Ptarget` flag, not into the test APK. Always rebuild both `assembleDebug` and `assembleDebugAndroidTest` together after changing the test file.

This produces:
| File | Path |
|---|---|
| App APK | `build/app/outputs/apk/debug/app-debug.apk` |
| Test APK | `build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` |

> [!WARNING]
> Running `assembleDebugAndroidTest` **without** `-Ptarget` will not include `benchmark_test.dart`. Always use the `-Ptarget` flag.

---

## Phase 4 — Run on Firebase Test Lab

Three real physical devices are used — one per performance tier — to demonstrate behavior across the range of likely target hardware.

| Tier | Model ID | Device | Android |
|---|---|---|---|
| 🔻 Low-end | `lion` | Motorola moto g04 | 34 |
| 🔶 Mid-range | `oriole` | Google Pixel 6 | 33 |
| 🔺 High-end | `tokay` | Google Pixel 9 | 35 |

> [!NOTE]
> Run from `c:\src\instaham` (project root), not the `android` subfolder, since the APK paths are relative to the project root.

```powershell
gcloud firebase test android run --type instrumentation --app build/app/outputs/apk/debug/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk --device "model=lion,version=34,locale=en,orientation=portrait" --device "model=oriole,version=33,locale=en,orientation=portrait" --device "model=tokay,version=35,locale=en,orientation=portrait" --timeout 5m
```

For a quick **Robo test** (no integration test code needed, good for smoke/crash checking):

```powershell
gcloud firebase test android run --type robo --app build/app/outputs/apk/debug/app-debug.apk --device "model=oriole,version=33,locale=en,orientation=portrait" --timeout 3m
```

---

## Phase 5 — Collect and Report Results

Firebase Test Lab produces per-run:
- ✅ Pass/fail per test per device
- 📊 **Logcat output** — where `print('COLD_START_MS: ...')` values appear
- 📸 Screenshots of every screen state
- 🎥 Video recording of the test session
- 🐞 Crash reports with full stack traces

Results are available in the Firebase Console under **Test Lab → Test history**.

### How to Extract Metric Values

From the logcat tab in the Firebase Console, filter by your tag prefix (e.g., `COLD_START_MS`) to pull the numeric results for your report.

---

## Phase 6 — Documentation Template

Use this template when reporting results:

```
Device Testing — Firebase Test Lab

Platform:    Firebase Test Lab (Google LLC)
Test type:   Instrumentation (Flutter integration_test package)
Date:        [date from Firebase report]

Devices tested:
  - Motorola moto g04 (lion), Android 14 (API 34) — [PASS/FAIL]
  - Google Pixel 6 (oriole), Android 13 (API 33) — [PASS/FAIL]
  - Google Pixel 9 (tokay), Android 15 (API 35) — [PASS/FAIL]

Metrics recorded:
  - Cold-start time:         [value] ms  (target: <2000 ms)
  - Median inference latency:[value] ms
  - P95 inference latency:   [value] ms
  - Memory peak (RSS):       [value] MB
  - Model file size:         [value] MB  (target: <50 MB)

Note: All latency figures are from real on-device execution.
GPU/desktop notebook latency is not reported as phone latency.
```

---

## Checklist

- [ ] Firebase project created (Spark plan — no billing account needed)
- [ ] `gcloud` CLI installed and authenticated
- [ ] `integration_test` added to `pubspec.yaml` (no `flutter_driver`)
- [ ] `integration_test/benchmark_test.dart` written with metric instrumentation
- [ ] `flutter build apk --debug` succeeded
- [ ] `gradlew assembleDebug assembleDebugAndroidTest -Ptarget=...` succeeded
- [ ] `gcloud firebase test android run ...` submitted and completed
- [ ] Logcat values extracted for each metric
- [ ] Results documented using the template above
