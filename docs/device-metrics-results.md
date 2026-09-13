# Device metrics results — metrics 1, 2 and 3 across three device tiers

Status: **observed results, complete three-tier set.** Compiled 2026-09-13.

Purpose: a single, self-contained record of every device measurement taken for metrics 1, 2
and 3, assembled for thesis interpretation. Every number below was printed by
`integration_test/benchmark_test.dart` running on a physical phone in Firebase Test Lab and
read back from that run's `logcat`. Nothing here is a prediction, a target, or a host-machine
figure.

Source of record: `docs/metrics-phase/6.2-metric-measurement-defects.md` (rounds 1-4) and
`docs/metrics-phase/6-device-metrics.md` (disposition and targets). This document restates
those results in one place and adds the derived comparisons; it does not supersede them.

## 1. What was measured

| # | metric | printed logcat key(s) | unit | gate |
|---|---|---|---|---|
| 1 | time to first stable frame (cold start proxy) | `COLD_START_MS` | ms | asserted `< 2000 ms` |
| 2 | inference latency, full pipeline, per run | `INFERENCE_MEDIAN_MS`, `INFERENCE_MAX_MS`, `INFERENCE_RUNS` | ms | report-only, no threshold |
| 3 | memory footprint at startup | `MEMORY_STARTUP_RSS_BYTES` / `_MB` | MB | report-only, no threshold |
| — | memory after the inference loop (companion reading) | `MEMORY_POST_INFERENCE_RSS_BYTES` / `_MB` | MB | report-only, no threshold |

**Provenance of the 2000 ms target.** It is a product decision recorded in
`docs/metrics-phase/6-device-metrics.md` under "Agreed targets", dated 2026-09-12. The
requirements document `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14 states **no numeric
target** for any of these three metrics. Metrics 2 and 3 are deliberately report-only because
no baseline existed before these runs; inventing a threshold would have fabricated a
requirement. Any threshold set from here on should cite this data as its basis.

## 2. Devices

| tier | Test Lab model ID | device | Android API | role |
|---|---|---|---|---|
| high | `tokay` | Google Pixel 9 | 35 | current flagship |
| mid | `oriole` | Google Pixel 6 | 33 | mainstream, three years old |
| low | `lion` | Motorola moto g04 | 34 | entry-level budget hardware |

All three are physical devices, not emulators. §14's closing constraint — GPU or desktop
latency from the notebooks must never be reported as phone latency — is satisfied: every
figure in this document carries the device it came from.

## 3. Results

### 3.1 Headline table — the three-tier set

| tier | device | metric 1 cold start | metric 2 median latency | metric 2 max latency | metric 3 startup RSS | post-inference RSS |
|---|---|---|---|---|---|---|
| high | `tokay` | **1392 ms** — within target | **11 705 ms** | 11 824 ms | **498.5 MB** | 1500.4 MB |
| mid | `oriole` | **1856 ms** — within target | **16 992 ms** | 18 408 ms | **466.4 MB** | 1461.8 MB |
| low | `lion` | **5099 ms** — exceeds target | **70 898 ms** | 71 963 ms | **460.5 MB** | 682.6 MB |

**On `lion`'s cold-start row.** "Exceeds target" means the measurement is above the 2000 ms
figure the team chose for itself on 2026-09-12; it does **not** mean the app, the pipeline or
the code failed. `lion`'s run was healthy in every other respect — all three test cases
executed, metrics 2 and 3 both produced values, and the full suite completed in 804 s of a
900 s budget. No requirement in
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14 was violated, because §14 states no
cold-start number at all. The target itself remains open to revision against this data.

Metric 2 used 10 timed iterations per device, preceded by one discarded warm-up iteration.
Metric 3 is read after the app is pumped and settled but before any model is loaded; the
post-inference reading is taken at the end of metric 2's loop. The two readings are separated
precisely so the startup figure is not contaminated by loaded model weights.

### 3.2 Derived comparisons

Ratios normalised to the high tier (`tokay` = 1.00):

| quantity | `tokay` | `oriole` | `lion` |
|---|---|---|---|
| cold start | 1.00x (1392 ms) | 1.33x (1856 ms) | 3.66x (5099 ms) |
| median inference latency | 1.00x (11 705 ms) | 1.45x (16 992 ms) | 6.06x (70 898 ms) |
| startup RSS | 1.00x (498.5 MB) | 0.94x (466.4 MB) | 0.92x (460.5 MB) |
| post-inference RSS | 1.00x (1500.4 MB) | 0.97x (1461.8 MB) | 0.45x (682.6 MB) |

Memory added by the inference loop (post-inference RSS minus startup RSS):

| device | startup | post-inference | added by inference |
|---|---|---|---|
| `tokay` | 498.5 MB | 1500.4 MB | **+1001.9 MB** |
| `oriole` | 466.4 MB | 1461.8 MB | **+995.4 MB** |
| `lion` | 460.5 MB | 682.6 MB | **+222.1 MB** |

Dispersion within metric 2, as max divided by median over the 10 timed runs:

| device | median | max | max / median |
|---|---|---|---|
| `tokay` | 11 705 ms | 11 824 ms | 1.010 |
| `oriole` | 16 992 ms | 18 408 ms | 1.083 |
| `lion` | 70 898 ms | 71 963 ms | 1.015 |

### 3.3 Provenance of each figure

| device | Test Lab matrix | project | date | outcome |
|---|---|---|---|---|
| `tokay`, `oriole` | `matrix-1g02uzwhacb93` | `instaham-test-lab` | 2026-09-13 | passed, 3 test cases each |
| `lion` | `matrix-ofqgnxmd2vkna` | `instaham-test-lab-2` | 2026-09-13 | all 3 test cases ran and produced values; metric 1's assertion tripped on the 2000 ms target (not an infrastructure or pipeline error); 804 s of a 900 s budget |

Both runs used the same `app-debug.apk`, built 2026-09-13 14:09 with
`-Ptarget=integration_test/benchmark_test.dart`, and the same `app-debug-androidTest.apk` from
2026-09-12 23:57. Both used the same input: fixture scenario
`01_valid_dorsal_100cm_reference` (873 461 bytes), pushed to
`/data/local/tmp/instaham_bench.jpg`. The three devices therefore differ only in hardware and
Android version, not in build or input.

**Device-clock caveat.** Each device's own logcat timestamps read `09-12`, one day behind the
actual submission date. The dates above come from the `gcloud` CLI's wall clock, which is
authoritative.

## 4. Observations for interpretation

These are read off the data above. Each is an observation, not a decision — none of them has
been acted on in code.

**4.1 Cold start exceeds the working target on entry-level hardware, and not marginally.**
`lion` is 3099 ms above the 2000 ms target, 2.55x over. Both other devices are inside it,
`tokay` with a 608 ms margin and `oriole` with 144 ms. The overshoot is confined to the low
tier, but within that tier it is large. This says the low tier is slow to start, not that the
code is defective — the same build starts inside target on both other tiers.

**4.2 Cold start is not stable enough to quote to three digits.** `lion` was measured twice on
identical hardware and an identical APK: 4799 ms (matrix `matrix-1g02uzwhacb93`) and 5099 ms
(matrix `matrix-ofqgnxmd2vkna`), a 300 ms / 6% spread. A single cold-start reading should be
treated as having at least that much uncertainty. Metric 1 was measured once per device on the
other two tiers, so the same uncertainty must be assumed for them.

**4.3 Latency scales far worse than cold start across tiers.** Cold start degrades 3.66x from
high to low tier; median inference latency degrades 6.06x. The two do not track each other, so
cold start cannot be used as a proxy for inference cost when reasoning about an untested
device.

**4.4 A roughly 71-second median on entry-level hardware is the headline product figure.**
`lion`'s 70 898 ms median is the cost of one complete pipeline run on a moto g04. Nothing in
§14 sets a latency target, so this fails no assertion, but it is the number any future target
must be set against, and it is the number that describes the low-tier user's actual wait.

**4.5 Latency is highly repeatable within a device.** Max divided by median is 1.01-1.08 on all
three devices across 10 runs. Run-to-run variance in inference is small; the cross-device
spread in 4.3 is therefore a hardware effect, not measurement noise.

**4.6 Startup memory is essentially device-independent.** 460.5-498.5 MB across all three
tiers, an 8% spread with no tier ordering — `tokay`, the fastest device, uses the most. Startup
RSS is dominated by the Flutter engine and app, not by the hardware.

**4.7 Post-inference memory on the low tier is less than half the other two, and this is
unexplained.** Inference adds roughly 1002 MB on `tokay` and 995 MB on `oriole` but only
222 MB on `lion`, from the same pipeline, same models and same fixture. Candidate explanations
— a different ONNX Runtime execution provider or thread count being selected on the low-end
SoC, or memory reclaimed under pressure between the inference loop and the reading — have
**not** been investigated or confirmed. The low tier currently looks *better* on this metric
while being 6x slower, which is the kind of inversion that usually indicates a different
execution path rather than a genuine efficiency win. This should be resolved before any memory
target is set.

**4.8 Memory is a single end-of-loop reading, so residency and growth cannot be separated.**
Whether the roughly 1000 MB added on `tokay` and `oriole` is steady-state session and arena
residency or accumulation across the 10 iterations cannot be told from one reading. A
per-iteration RSS print would settle it at no measurable device cost; it has not been taken.

## 5. Supporting runs that did not produce a complete set

Recorded so the three-tier set is not read as three clean attempts. Five further
physical-device runs were spent reaching it.

| device | matrix | outcome | usable figures |
|---|---|---|---|
| `oriole` (round 1) | `matrix-2n75lkxeh3jw4` | passed, superseded | superseded by round 2 — measured before the metric 2 and 3 fixes |
| `lion` (round 2) | `matrix-1g02uzwhacb93` | instrumentation timed out at 5 min | `COLD_START_MS` 4799 ms, `MEMORY_STARTUP_RSS_MB` 423.6 MB; metric 2 never printed |
| `fogorow` (moto g24, API 34) | `matrix-2jeo2oosy1ne7` | never scheduled — `DEVICE_CAPACITY_NONE`, sat `PENDING` 40+ min | none |
| `a04s` (Galaxy A04s, API 34) | `matrix-346vr148gzyam` | instrumentation timed out at 15 min | `COLD_START_MS` 8558 ms, `MEMORY_STARTUP_RSS_MB` 457.8 MB; metric 2 never printed |
| `lion` (round 4, attempt 1) | `matrix-25lcpovzspqkh` | fixture not pushed — metric 2 failed its guard in 15 s | `COLD_START_MS` 5099 ms, metric 3 passed; metric 2 produced nothing |

Two points follow from this table and matter for interpretation:

- **Metric 2 on the low tier is expensive to obtain, not merely slow.** `lion` needed a
  15-minute instrumentation timeout to finish at all (it used 804 s of 900 s). `a04s`, a device
  in the same class, still timed out at that same 15-minute budget, so its latency remains
  unmeasured. The three-tier set is complete for the devices in it, but the entry-level tier
  should be understood as "measured on one representative device", not "characterised".
- **`a04s`'s 8558 ms cold start, 4.28x the working target, is a second low-tier data point for metric
  1** even though its latency is missing. It is 1.68x `lion`'s figure, which suggests
  entry-level cold start varies widely across the tier rather than sitting at a fixed multiple
  of the mid-tier figure.

## 6. Known limitations of this data

State these alongside any thesis claim built on the table in 3.1.

1. **One fixture.** Every number comes from a single input image, scenario 01. Latency for
   other images — different pig size, different segmentation difficulty — is not measured, and
   the pipeline's cost is not known to be input-independent.
2. **N = 10 per device for latency, N = 1 for cold start and startup memory.** The latency
   figures have real within-device statistics behind them; the cold start and memory figures
   are single readings, and 4.2 shows cold start alone varies 6% between runs.
3. **Median and max only.** No true 95th percentile exists: 10 samples cannot support one under
   any indexing scheme. An earlier `INFERENCE_P95_MS` key in round 1 was the maximum
   mislabelled, and has been removed; do not quote a P95 for this pipeline from this data.
4. **Metric 1 is an in-process proxy**, measured from inside the Flutter app, not an OS-level
   Zygote-to-first-frame measurement. It is consistent across devices and therefore valid for
   comparison, but it is not directly comparable to platform cold-start figures reported by
   Android tooling.
5. **Three device models.** The tiers are represented, not sampled. Two of the three are Google
   Pixels, so the high and mid tiers share a vendor, an SoC family and a near-stock Android
   build; a non-Pixel mid-tier device is not measured.
6. **Round 1's `oriole` numbers must not be mixed in.** They were taken before the measurement
   fixes and are superseded; in particular round 1's `MEMORY_RSS_MB` of 1446.6 MB was a
   post-inference reading carrying a startup label.

## 7. Where the numbers live

- `docs/metrics-phase/6.2-metric-measurement-defects.md` — the primary record, rounds 1-4,
  Findings 1-6, and the two measurement defects that were fixed between rounds 1 and 2.
- `docs/metrics-phase/6-device-metrics.md` — metric disposition, the agreed targets and their
  provenance.
- `docs/device-testing-plan.md` — the Firebase Test Lab runbook used to execute these runs.
- `integration_test/benchmark_test.dart` — the test that printed every value above.
