# Metrics plan phase 6 — redistribute the 6 device metrics

Status: **all seven tasks complete as of 2026-09-13.** Task 1 (file reduced/renamed,
metric 5 deleted), task 2 (metric 4, host test, passing), task 3 (implemented, fixed per
subphase 6.2), task 4 (**complete three-tier result set** for metrics 1, 2 and 3 — `tokay`
high, `oriole` mid, `lion` low; the low tier completed on 2026-09-13 at `--timeout 15m`, see
subphase 6.2 round 4 and Findings 4-6), task 5 (`docs/device-testing-plan.md` defects fixed,
stale inline test copy replaced with a pointer), task 6 (metric 6, host test, passing), task 7
(§16 traceability, host test, passing; threshold gap and metric 5's drop recorded). Two
product findings from task 4 remain open, unowned by design — recording results is not the
same as remediating: `lion` exceeds metric 1's 2000 ms working target at 5099 ms (this is a
target miss, not a code or pipeline defect — see `docs/device-metrics-results.md` §3.1), and
its metric 2 median is 70 898 ms, 6× the high tier.
Expands the phase 6 stub in `docs/metrics-plan.md` (lines ~687-739). Follows phases 4, 4.1 and
5. Subphases: `6.1-benchmark-fixture-asset.md`, `6.2-metric-measurement-defects.md`.

This phase carries two changes that arrived after phase 5 shipped:

1. **The parity workstream is deferred by team decision and will not be used.** See "Phase 5
   is deferred" below. Metric 6, which the original phase 6 table routed into phase 5's
   suite, is re-disposed here as a standalone host test.
2. **The device metrics get a real execution path via Firebase Test Lab**, per
   `docs/device-testing-plan.md`, plus four agreed targets. Metrics 1-3 are no longer
   "device-only and therefore unrunnable" — they run on three real phones on the free tier.

No `lib/` production change. No model change. No manifest change. No native/C++ change.

## Goal

Move each of the six device metrics in `test/device/device_benchmarks_test.dart` to the place
it can genuinely run, and give the four measurable ones an agreed basis so a run produces a
verdict rather than only a number. Three metrics become real device tests executed on
Firebase Test Lab, two become host tests that always run, and one stays an honest manual gap.

The six today are six empty `() async {}` bodies behind a single blanket skip reason,
"Manual device testing — run on physical target smartphone", which is wrong for at least two
of them (metrics 4 and 6 need no device at all).

## Agreed targets

**Provenance, and it matters: these four are a product decision made 2026-09-12, not §14
requirements.** §14's device list (line 536) says only "model file sizes" — it states no
number anywhere, for any metric. The "< 50 MB" figure previously appeared in
`test/device/device_benchmarks_test.dart:27`, `integration_test/benchmark_test.dart:105` and
`docs/device-testing-plan.md:239` with no stated source, and had begun to read as
authoritative. It is not. Every test written under this phase must name this document as the
origin of its threshold, so the next reader does not re-derive it as a spec requirement.

| # | metric | basis | gate? |
|---|---|---|---|
| 1 | time to first stable frame | **< 2 000 ms** | **yes** — assert |
| 2 | inference time | median and max (not P95 — see subphase 6.2), **reported** | no — no threshold set |
| 3 | memory use at startup | megabytes, **reported** | no — no threshold set |
| 4 | model file size | **< 50 MB per model** | **yes** — assert |

Metrics 2 and 3 stay report-only deliberately: no baseline has been measured on the reference
devices, and inventing a threshold would fabricate a requirement. They become gates once a
Test Lab run establishes what normal looks like across the three tiers.

Note metric 3 is **startup** memory, narrower than the metric's original name ("memory
footprint at peak inference"). That is the agreed reading; the existing test already measures
startup, so no change of measurement point is needed — but the test's name must say startup
so it does not overclaim.

## Phase 5 is deferred

**Decision (2026-09-12, team):** the parity workstream is not being used. Phase 5's
`test/parity/parity_test.dart` suite and its supporting `ML/parity/` scripts stay in the tree
as executed work, but parity is no longer a gate on anything downstream, and subphase 5.1
(native mask export), which existed to unblock segmentation parity, is not being taken.

What this deliberately gives up, recorded so it is not rediscovered as a surprise:

- **§14's "Model-parity testing" section is unmet in full**, not just in its segmentation
  bullet. The §18 readiness checklist item "Exported-model parity tests have passed" cannot
  be ticked from the test suite. A recorded deviation from
  `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md`, taken knowingly.
- **No standing check that the C++ port still agrees with the Python original.** A future
  edit to the vendored native stages can change a number with nothing to catch it.
  `ML/parity/chen16_feature_port_gate.py` remains runnable by hand over the `MASK_3394`
  corpus and is the cheapest spot-check if that question returns; this phase does not wire it
  into any automated run.

**Metric 6 does not depend on any of that.** §14's device bullet 6, "accuracy after model
export or quantization", is checkpoint-versus-exported-ONNX — a different question from port
parity — and the manifest already records the export self-checks. Task 6 covers it directly.

## Disposition table (revised)

| metric | disposition | changed? |
|---|---|---|
| 1 — cold start | `integration_test/`, run on Test Lab; assert < 2 000 ms | target added |
| 2 — median/max inference latency | `integration_test/`, run on Test Lab; wire the real pipeline, report only | execution path added; P95 replaced with max per subphase 6.2 |
| 3 — memory at startup | `integration_test/`, run on Test Lab; report only | scope fixed to startup |
| 4 — model file size | **host test** — file stat; assert < 50 MB per model | target settled |
| 5 — battery/thermal over 50 scans | **dropped** by decision of 2026-09-13 — see "Metric 5 is dropped" below | was "no home, recorded as unowned" |
| 6 — export/quantization accuracy | **standalone host test** on the manifest's recorded export deltas | was "folded into phase 5's parity suite" |

## Metric 5 is dropped

**Decision (2026-09-13, user):** metric 5 — battery drain and thermal stability over 50
consecutive scans — is **dropped from the metrics workstream entirely**. It is not deferred,
not parked, and not awaiting an owner. No test is written for it, no execution path is sought,
and it is not carried forward as an open item in any later phase.

This replaces the earlier disposition, which recorded it as an unowned §14 item with no
execution path. That framing implied someone would eventually take it; this one says no one
will.

**What this gives up, recorded so it is not rediscovered as a surprise.**
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14 lists battery and thermal behaviour over
sustained use among its device-testing bullets. Dropping the metric does **not** remove that
requirement from §14 — it records a knowing deviation from it, in the same way phase 5's
deferral records a knowing deviation from §14's model-parity section. Specifically:

- **No evidence exists, or will exist from this workstream, about sustained-use behaviour.**
  Whether the app throttles, overheats, or drains the battery unacceptably across a long
  session is unmeasured and will stay unmeasured. The low tier's ~71-second median inference
  latency (`docs/device-metrics-results.md`, §3.1) makes 50 consecutive scans roughly an hour
  of continuous compute on that hardware, so this is not a hypothetical concern — it is simply
  one that is not being investigated.
- **Any §14 or §18 readiness review must show metric 5 as deviated, not as pending.** A
  reviewer reading a green phase 6 suite must not infer that battery and thermal behaviour
  passed; nothing tested it.

**Why it is a reasonable drop.** The measurement was never obtainable with the resources the
project has. Firebase Test Lab on the Spark free tier allows 5 physical device runs per day
with per-command instrumentation timeouts that 50 consecutive scans cannot fit — the low tier
alone needed a 15-minute timeout for 11 iterations. Closing the metric honestly would have
required a dedicated physical device held for an hour-plus run, or a Blaze-tier long-run
budget. Keeping it on the books as "unowned" cost real attention every round and produced
nothing. Dropping it makes the state of the work legible rather than hopeful.

## Design/Approach

`test/device/device_benchmarks_test.dart` is reduced to the two host metrics and renamed
host-honest. The three device metrics move into `integration_test/benchmark_test.dart`, which
already holds partial implementations of all three, and are executed through the Firebase
Test Lab runbook in `docs/device-testing-plan.md` — Spark free tier, three physical devices
(`lion` moto g04 / API 34, `oriole` Pixel 6 / API 33, `tokay` Pixel 9 / API 35), values
extracted from logcat via the existing `print('METRIC_NAME: value')` convention.

**§14's closing constraint governs the whole phase:** "GPU or desktop latency from the
notebooks must not be reported as phone latency." The phase 1 Windows host build must never
produce a latency or memory number that is then written down as a device result — not in a
test, not in a doc, not in a summary. Every metric 1-3 number in any report must carry the
Test Lab device it came from.

## Steps

### Task 1 — Reduce and rename the device file

- [x] Delete metrics 1, 2, 3 and 5 from `test/device/device_benchmarks_test.dart`. Metrics 1-3
      already live in `integration_test/benchmark_test.dart` (task 3); metric 5 was **deleted
      outright**, per "Metric 5 is dropped" above — it does not move anywhere.
- [x] Renamed to `test/assets/model_package_size_test.dart` — metrics 4 and 6 are both
      asset/manifest assertions, so one host file holds them. `test/device/` is removed (now
      empty).
- [x] Top-of-file comment points at `integration_test/benchmark_test.dart` for metrics 1-3 and
      `docs/device-testing-plan.md` for how those are executed, and states that metric 5 was
      dropped by decision on 2026-09-13 with the reasoning in this document — so the gap in the
      numbering is explained where a reader meets it.
- [ ] **Not yet done:** metrics 4 and 6 are still empty `() async {}` stubs, now skipped with
      "Not yet implemented" reasons pointing at tasks 2 and 6 rather than the old blanket
      "Manual device testing" line, which was false for both. Wiring them is task 2 and task 6.

### Task 2 — Metric 4 as a host test

- [x] Stat the `.onnx` files under `assets/ml/` directly from disk — plain `flutter test`, so
      no `AssetBundle`, no `tester.runAsync`.
- [x] Derive the file list from `assets/ml/manifest.json` rather than hardcoding four paths,
      so a model added to the bundle is covered automatically.
- [x] Assert **each file** < 50 MB. Print every size so a failure names the offender.
- [x] Comment must state: the 50 MB is a product decision recorded in this document, **§14
      states no size target at all**, and the check is per-model — the `assets/ml` bundle
      totals ~68 MB and is deliberately not asserted against.

**Done 2026-09-13.** `test/assets/model_package_size_test.dart` — all four models pass; full
results and per-model margins in `docs/metric-4-results.md`.

Current sizes, all passing:

```
 9.50 MB  assets/ml/view/model.onnx
18.68 MB  assets/ml/health/model.onnx
38.46 MB  assets/ml/segmentation/yolo.onnx
 0.97 MB  assets/ml/weight/xgboost.onnx
```

### Task 3 — Metrics 1-3 in `integration_test/benchmark_test.dart`

- [x] **Metric 1** — implemented with a real `lessThan(2000)` assertion, matching the agreed
      target. Left alone.
- [x] **Metric 2** — replaced the `markTestSkipped('Inference pipeline not yet wired to
      integration test')` placeholder with a real run: 10 pipeline iterations against the
      pushed fixture, printing `INFERENCE_MEDIAN_MS` and `INFERENCE_RUNS`. No assertion.
      **Superseded by subphase 6.2:** a discarded warm-up call now precedes the timed loop,
      and the second statistic is `INFERENCE_MAX_MS`, not `INFERENCE_P95_MS` — 10 samples
      cannot support a real 95th-percentile index. See
      `docs/metrics-phase/6.2-metric-measurement-defects.md`, defect B.
- [x] **Metric 3** — keeps the startup measurement point, now enforced by declaration order
      (metric 3 is declared before metric 2 in the file). Test title says "at startup".
      **Superseded by subphase 6.2:** printed key renamed `MEMORY_STARTUP_RSS_MB` (was
      `MEMORY_RSS_MB`), and metric 2 now also prints `MEMORY_POST_INFERENCE_RSS_MB` at the end
      of its loop so the peak-usage figure that used to leak into metric 3 is kept under its
      own honest name. See `docs/metrics-phase/6.2-metric-measurement-defects.md`, defect A.
- [x] Delete the duplicated metric 4 stub — its `modelAssets` list is empty and it
      self-skips; task 2 supersedes it on the host.
- [x] Every printed key keeps the `NAME: value` shape the runbook's logcat filter relies on.

### Task 4 — Execute on Firebase Test Lab

Follow `docs/device-testing-plan.md`. This is the step that makes metrics 1-3 real.

- [x] Build both APKs together with the `-Ptarget` flag — without it the test file is not
      compiled in and the run silently measures nothing.
- [x] Run against all three device tiers in one invocation.
- [x] Extract the five printed values per device from logcat. **`lion` incomplete** — see below.
- [x] Record results using the runbook's template, **one row per device**. A single number
      with no device attached is not a device result.
- [x] `lion` fails its 2 000 ms cold-start target outright (4799 ms) — reported, not
      accommodated. See `docs/metrics-phase/6.2-metric-measurement-defects.md`, Finding 1.

**Executed on all three tiers; `lion` incomplete.** Round 1 (`oriole` only, 2026-09-12,
matrix `matrix-2n75lkxeh3jw4`) is superseded. Round 2 (2026-09-13, matrix
`matrix-1g02uzwhacb93`) ran all three tiers after the defect A/B fixes: `oriole` and `tokay`
both passed, 3 test cases each, with results in `docs/metrics-phase/6.2-metric-measurement-defects.md`.
`lion` **failed — instrumentation timed out** after printing metric 1 and metric 3 but before
metric 2; its cold-start figure (4799 ms) also fails the 2 000 ms target outright. This is not
yet a complete tier result set: `lion`'s metric 2/post-inference-memory figures do not exist,
and the timeout itself is a new, unremediated finding (subphase 6.2, Finding 2). Quota spent:
3 of 2026-09-13's 5 physical runs.

### Task 5 — Update `docs/device-testing-plan.md`

Three defects found while folding it in:

- [x] Its reporting template says "Memory peak (RSS)"; the agreed metric and the actual
      measurement are **startup**. Fix the label. — **Already fixed by subphase 6.2**, which
      rewrote the template to the five keys the test now prints. Verified current.
- [x] The Phase 4 run note says to run from `c:\src\instaham`. That is not this repository's
      path. Fix or generalise it. — **Already fixed**; the note now says "the repository root
      (the folder containing `pubspec.yaml`)". Verified current.
- [x] Its template lists `<2000 ms` and `<50 MB` with no source. Point both at this
      document's "Agreed targets" section so their provenance travels with them. — **Already
      fixed by subphase 6.2.** One stale word corrected this round: the note said "Median/P95
      latency", and P95 no longer exists.

**Done 2026-09-13.** The three defects above were already closed by subphase 6.2. Four that
were still live were fixed this round, all of them traps that had already cost or nearly cost
a physical-device run:

- [x] **The inline copy of `benchmark_test.dart` in Phase 2 was deleted**, not updated. It had
      drifted within two rounds — it showed `INFERENCE_P95_MS`, `MEMORY_RSS_MB`, a metric 4
      stub that is now a host test, and a claim that metrics 5 and 6 need manual video review.
      Phase 2 now points at the real file and documents only what a reader cannot get from it:
      the declaration-order contract, why max is not a percentile, the fixture requirement, and
      where metrics 4 and 6 actually live. A runbook that duplicates a test file will drift
      again; one that points at it cannot.
- [x] **`--other-files` is now in the documented command**, with a CAUTION block naming the
      exact failure and the run it already cost (`matrix-25lcpovzspqkh`). Its absence was the
      single documented cause of a wasted run.
- [x] **`--timeout` raised from `5m` to `15m` in the documented command**, with the measurement
      behind it: 5m killed `lion` mid-suite, 15m completes in 804 s. The old value was not
      merely stale, it was a documented instruction to reproduce a known failure.
- [x] **Two checklist lines added** for the fixture push and the timeout, plus the Git Bash
      `MSYS2_ARG_CONV_EXCL` note and the `--async`/matrix-state caveat, which were live in
      `docs/handoff.md` but absent from the runbook that outlives it.

### Task 6 — Metric 6 as a standalone host test

§14 device bullet 6. The manifest records the export self-checks already:

| field | value |
|---|---|
| `capabilities.view.model.onnx_max_abs_diff` | 5.7220458984375e-06 |
| `capabilities.health.model.onnx_max_abs_diff` | 3.337860107421875e-06 |
| `capabilities.health.model.fusion_max_abs_diff` | 4.231929779052734e-06 |
| `capabilities.segmentation.model.onnx_self_check.proto_max_abs_diff` | 8.821487426757812e-06 |
| `capabilities.segmentation.model.onnx_self_check.box_mask_max_abs_diff` | 0.001434326171875 |

- [x] Assert each recorded delta is present and within a stated tolerance.
- [x] The four ~1e-6 values are float32 round-trip noise; `box_mask_max_abs_diff` at 1.4e-3
      is three orders larger and needs its own bound, not the same one.
- [x] **State the limit in the test's own comment.** This asserts the *recorded* export check,
      not a freshly computed one. It catches a model swapped into the bundle without its
      self-check re-run, and a delta that grows across re-exports. It does not independently
      re-verify the export, and a green run must not be read as "export verified today".

**Done 2026-09-13.** `test/assets/model_package_size_test.dart` — all five deltas present and
within tolerance (`1e-4` for the four noise-level values, `5e-3` for `box_mask_max_abs_diff`).
Full results in `docs/metric-6-results.md`.

### Task 7 — §16 traceability, and record metric 5 as dropped

- [x] Assert the manifest's traceability fields: `bundle_id` (`instaham-ml-e13b1f4`),
      `reference_commit` (`e13b1f4`), `schema_version`, per-model `sha256`,
      `protocol_version`. **Found along the way:** `weight`'s `protocol_version` is nested one
      level deeper than the other three capabilities (`capabilities.weight.feature_extractor
      .protocol_version`, not `capabilities.weight.protocol_version`) — a genuine manifest
      structural asymmetry, not a test bug; the test now searches each capability's subtree
      generically rather than assuming a fixed depth. Per-model `sha256` is verified against
      the actual file on disk, not just checked for presence. Full results and the finding's
      detail in `docs/metric-16-traceability-results.md`.
- [x] **Record the threshold gap rather than inventing a version.** There is no
      `thresholds.json`; `kHealthUncertainBelow = 0.60` is a bare constant at
      `lib/features/inference_pipeline/domain/use_cases/run_and_persist_pipeline_use_case.dart:51`,
      and the view classifier has no confidence threshold at all (finding 8). Recorded in
      `docs/metric-16-traceability-results.md`, "The threshold gap — recorded, not invented".
      Neither gap is closed by this task.
- [x] **Metric 5 (battery/thermal over 50 consecutive scans) is dropped, not deferred.** The
      decision and its full cost are recorded under "Metric 5 is dropped" above. This task's
      job is only to make the deviation visible where §14 coverage is summarised: record it as
      a **knowing deviation from §14**, not as an open or pending item, so no readiness review
      reads it as work still queued. No test, no skip, and no placeholder is left behind. —
      **Done**: recorded above, in `docs/metrics-plan.md`, and in `docs/device-testing-plan.md`.

**Done 2026-09-13.** All three checklist items above are closed; full write-up in
`docs/metric-16-traceability-results.md`.

## Validation

1. `dart format` on every changed Dart file.
2. `flutter analyze` — must be clean.
3. `flutter test test/assets/model_package_size_test.dart` — metrics 4, 6, §16.
4. Full `flutter test --reporter=compact` at the end, reporting the `+N ~M` line so the skip
   count stays visible.
5. `integration_test/` does **not** run under `flutter test`. Its validation is task 4's Test
   Lab run, reported per device. If task 4 has not been run, say so — do not substitute a
   Windows host run for it.
6. No native change in this phase, so the `packages/instaham_ml_ffi/src/test/` ctest suite is
   unaffected.

## Open questions

1. **Do metrics 2 and 3 get thresholds after the first Test Lab run?** They ship report-only.
   Once three tiers of real numbers exist, someone can set an honest gate.
2. ~~**Who owns metric 5?**~~ **Answered 2026-09-13: no one.** The metric is dropped, not
   awaiting an owner — see "Metric 5 is dropped". The §14 deviation it creates is recorded
   there and surfaced by task 7.
3. **Does anything replace parity as a port-fidelity check?** Deferring phase 5 leaves the
   C++-versus-Python question unowned. Out of scope here; recorded so it stays visible.

## Plan rating: 8/10

Revised up from 7 after the Firebase runbook was folded in. The phase's largest weakness was
that half its metrics could not be executed by whoever wrote them; three real devices on a
free tier removes that, and four agreed targets turn two of the metrics from recordings into
verdicts.

**Pros.** Small, touches no production code, no models, no native code, and every task traces
to a named §14 or §16 item or to a recorded product decision. It corrects a real mislabelling
— four of six metrics sat behind a "run on physical smartphone" skip reason that was false for
two of them — and converts two permanent skips into tests that always run. Metric 6's
re-disposition is an improvement on the original table rather than damage control: a
manifest-reading host test is the better home, since export accuracy and port parity are
different questions and the manifest values exist regardless. The 50 MB figure is now sourced
honestly instead of circulating as a phantom requirement, and every threshold-bearing test is
required to name its origin. Metric 5's drop and the parity deferral are both recorded as explicit
gaps with their costs stated rather than left as hopeful skips.

**Cons.** Task 4 depends on Firebase project setup and `gcloud` auth that this environment
does not have, so the phase cannot be closed from here — metrics 1-3 will sit written but
unexecuted until someone runs the runbook, and a written-but-never-run device test is only
marginally better than a skip. Two of the four agreed targets are not gates at all, so metrics
2 and 3 can pass while measuring something useless; that is honest but weak, and it defers the
real work. Metric 3's scope was narrowed to startup, which is easier to measure and a weaker
signal than the peak-inference figure the metric was originally named for — a green number
there says less than it appears to. Metric 5 is dropped outright, which is honest but leaves
§14's battery and thermal bullet with no evidence behind it at all. And the
phase-5 deferral means a green suite at the end of phase 6 is further from a release gate than
the original plan intended: §14's entire model-parity section is now unmet, so "all phase 6
tests pass" and "ready to ship" remain a long way apart.
