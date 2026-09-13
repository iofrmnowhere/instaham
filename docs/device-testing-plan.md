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

`integration_test/benchmark_test.dart` already exists and is the authority on what is
measured and what each value is called. **This document does not reproduce it.** An earlier
revision inlined a full copy here; it drifted out of date within two rounds — showing
`INFERENCE_P95_MS` after that key was removed, `MEMORY_RSS_MB` after it was split into startup
and post-inference readings, and a metric 4 stub that has since moved to a host test. Read the
file itself rather than anything pasted into a document.

What it does today, in declaration order (the order matters — see below):

| # | test | prints | asserts |
|---|---|---|---|
| 1 | time-to-first-stable-frame | `COLD_START_MS` | `< 2000 ms` |
| 3 | memory at startup | `MEMORY_STARTUP_RSS_BYTES` / `_MB` | nothing — reported |
| 2 | inference latency, 10 timed runs after one discarded warm-up | `INFERENCE_MEDIAN_MS`, `INFERENCE_MAX_MS`, `INFERENCE_RUNS`, `MEMORY_POST_INFERENCE_RSS_MB` | nothing — reported |

Four things about it are easy to break and expensive to rediscover:

- **Metric 3 is declared before metric 2 on purpose.** All three tests share one process, so if
  metric 2 runs first its four loaded ONNX models and ten pipeline runs are already resident
  when metric 3 reads RSS — which is exactly the mislabelling that
  `docs/metrics-phase/6.2-metric-measurement-defects.md` defect A records. Reordering them
  silently re-breaks the metric.
- **`INFERENCE_MAX_MS` is a maximum, not a percentile.** Ten samples cannot support a 95th
  percentile under any indexing scheme; the old `INFERENCE_P95_MS` key was the maximum wearing
  a percentile's name. Same document, defect B.
- **Metric 2 needs a fixture pushed to the device** at `/data/local/tmp/instaham_bench.jpg`.
  It is not bundled in the APK. See `--other-files` in Phase 4 — omitting it is the single
  easiest way to waste a Test Lab run.
- **Metrics 4 and 6 are not here.** Both are host tests in
  `test/assets/model_package_size_test.dart`, run by plain `flutter test`, no device involved.
  Metric 5 was dropped on 2026-09-13 (see the note at the end of this document).

The only reason to edit `benchmark_test.dart` from this runbook is to add a metric. If you do,
keep the `print('NAME: value')` shape — Phase 5's logcat extraction depends on it.

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
> Run from the repository root (the folder containing `pubspec.yaml`), not the `android` subfolder, since the APK paths are relative to the project root.

> [!CAUTION]
> **`--other-files` is mandatory and is the easiest argument to forget.** Metric 2 runs the
> pipeline against a fixture image that is *not* bundled in the APK; it must be pushed to the
> device separately. Omit the argument and metric 2 fails in about 15 seconds on its own guard
> ("Benchmark fixture not found at /data/local/tmp/instaham_bench.jpg"), consuming a full
> physical-device run for no metric 2 data. This has already cost one run
> (`matrix-25lcpovzspqkh`, 2026-09-13).

```powershell
gcloud firebase test android run --type instrumentation --app build/app/outputs/apk/debug/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk --other-files "/data/local/tmp/instaham_bench.jpg=test/fixtures/scenarios/01_valid_dorsal_100cm_reference/image.jpg" --device "model=lion,version=34,locale=en,orientation=portrait" --device "model=oriole,version=33,locale=en,orientation=portrait" --device "model=tokay,version=35,locale=en,orientation=portrait" --timeout 15m
```

**On `--timeout`.** The value above is 15 minutes, not the 5 minutes an earlier revision of
this document specified. Five minutes was measured to be too short: it killed `lion` mid-suite
after metric 1 and metric 3 had printed but before metric 2 produced anything
(`ANDROID_INSTRUMENTATION_COMMAND_EXEC_TIMEOUT`), wasting that device's slot in the matrix. At
15 minutes `lion` completes in 804 s, with 96 s of headroom. A longer timeout costs nothing
extra on the Spark quota — the cap is 5 physical *runs* per day regardless of duration — but a
timeout set too low costs the whole matrix. There is no reason to lower it.

> [!TIP]
> On Git Bash, prefix the command with `MSYS2_ARG_CONV_EXCL="/data"` so the shell does not
> rewrite the device-side path in `--other-files` into a Windows path. Do **not** use
> `MSYS_NO_PATHCONV=1` with `gcloud` — it breaks other arguments. This does not apply to
> PowerShell.

> [!NOTE]
> **`--async` does not skip the upload,** only the post-submission poll. `app-debug.apk` is
> ~300 MB and its upload usually outlasts a two-minute command timeout, so the call may appear
> to hang or get backgrounded; the `matrix-xxxxx` ID still appears in the command's own output
> once the upload finishes. Read status from the Tool Results step rather than the matrix's
> outer `state`, which has been observed reporting `PENDING` with a non-retryable error message
> while the underlying step had already completed successfully.

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

Metrics recorded (one row per device — a number with no device attached is not a device result).
Keys below match integration_test/benchmark_test.dart's current print output; see
docs/metrics-phase/6.2-metric-measurement-defects.md for why P95 was replaced with a maximum
and why startup memory is read before, not after, metric 2's inference loop:
  - COLD_START_MS:                [value] ms  (target: <2000 ms)
  - INFERENCE_MEDIAN_MS:          [value] ms  (no target — reported, warm-up run discarded)
  - INFERENCE_MAX_MS:             [value] ms  (no target — reported; 10 samples, not a real P95)
  - MEMORY_STARTUP_RSS_MB:        [value] MB  (no target — reported; read before any model loads)
  - MEMORY_POST_INFERENCE_RSS_MB: [value] MB  (no target — reported; read after metric 2's 10 runs)
  - Model file size, per model:   [value] MB  (target: <50 MB, host test — not measured here)
  - Export self-check deltas:     (metric 6, host test — not measured here)

Note: All latency figures are from real on-device execution.
GPU/desktop notebook latency is not reported as phone latency.
```

> [!IMPORTANT]
> **Where the two targets come from.** The `<2000 ms` and `<50 MB` figures are a product
> decision recorded in `docs/metrics-phase/6-device-metrics.md` ("Agreed targets"), dated
> 2026-09-12. `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14 states **no numeric target for
> any device metric** — its list says only "model file sizes". Do not cite either figure as a
> requirement. Median/max latency and startup memory have no target at all yet: they are
> recorded so a baseline exists across the three device tiers, and can become gates once it
> does.

> [!NOTE]
> Metric 5 (battery and thermal over 50 consecutive scans) was **dropped by decision on
> 2026-09-13** and is not covered by this runbook or by any other. It is not pending work: no
> test exists, no execution path is being sought, and it will not appear in a later phase. The
> measurement was never obtainable here — runs are submitted with a per-command instrumentation
> timeout and Spark allows 5 physical runs/day, so 50 consecutive scans do not fit. The decision
> and the §14 deviation it creates are recorded under "Metric 5 is dropped" in
> `docs/metrics-phase/6-device-metrics.md`.

---

## Checklist

- [ ] Firebase project created (Spark plan — no billing account needed)
- [ ] `gcloud` CLI installed and authenticated
- [ ] `integration_test` added to `pubspec.yaml` (no `flutter_driver`)
- [ ] `integration_test/benchmark_test.dart` written with metric instrumentation
- [ ] `flutter build apk --debug` succeeded
- [ ] `gradlew assembleDebug assembleDebugAndroidTest -Ptarget=...` succeeded
- [ ] `--other-files` fixture push included in the run command (metric 2 fails without it)
- [ ] `--timeout` set to 15m, not 5m (5m killed `lion` mid-suite)
- [ ] `gcloud firebase test android run ...` submitted and completed
- [ ] Logcat values extracted for each metric
- [ ] Results documented using the template above, one row per device
- [ ] Metric 5 (battery/thermal) noted as dropped, not pending — see the note above
