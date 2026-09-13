# Metrics plan: activating the 21 skipped tests

## Goal

Turn the 21 skipped tests in `test/` into tests that actually assert something, and place
each one where it can genuinely run. Today the suite reports:

```
flutter test --reporter=compact
# 00:38 +93 ~21: 21 skipped tests.  All other tests passed!
```

93 passing, 21 skipped, 0 failing. The 21 are:

| file | count | current skip reason |
|---|---|---|
| `test/scenarios/functional_scenarios_test.dart` | 11 | "Needs concrete ML service" |
| `test/parity/parity_test.dart` | 4 | "Needs concrete ML service" |
| `test/device/device_benchmarks_test.dart` | 6 | "Manual device testing — run on physical target smartphone" |

Every one of these has an empty or placeholder body, so un-skipping without writing the body
first would only convert 21 skips into 21 vacuous passes. The plan below writes the bodies.

**Two of the eleven scenarios are removed by finding 9, so the working total is 19, not 21.**
Scenarios 4 and 10 -- the two no-reference cases -- are deleted rather than written, because the
capture flow now requires a reference object. Their test slots are removed from
`test/scenarios/functional_scenarios_test.dart` rather than left as skips.

## Findings that change the shape of the work

**1. The "needs concrete ML service" reason is stale.** All four capability services now have
real implementations backed by the native runtime: `lib/services/ml/view_model_service.dart`
(`ViewModelServiceImpl`), `health_model_service.dart`, `segmentation_service.dart`,
`weight_model_service.dart`, and the whole-graph `pipeline_service.dart`
(`PipelineServiceImpl` calling `MlRuntime.runPipeline`, i.e.
`instaham_ml_run_pipeline_json`). The 15 scenario and parity tests are blocked on a *host
build*, not on a missing service.

**2. `flutter test` runs on the Windows Dart VM, and there was no Windows
`instaham_ml.dll`.** `packages/instaham_ml_ffi/lib/instaham_ml_ffi.dart` already resolved a
`.dll` name on Windows, so the Dart side was ready; the C++ side hard-failed off Android with
`INSTAHAM_ML_WITH_ORT is only wired for Android in this pass`. **Resolved by phase 1** — see
`docs/metrics-phase/1-windows-host-build.md`. The DLL now builds and loads, so the tiers that
exercise the native pipeline are unblocked.

**3. Six device metrics cannot run under `flutter test` at all — but only four of them are
truly device-bound.** Cold-start, latency, memory, and thermal/battery need a physical
phone. Model package size (metric 4) and export/quantization parity (metric 6) are host
computations that were misfiled into the device file. Splitting them recovers two real host
tests instead of two permanent skips. Of the four device-bound metrics, three (1-3) now run on
Firebase Test Lab; the fourth, thermal/battery (metric 5), was **dropped** on 2026-09-13 rather
than carried as an unowned item — see `docs/metrics-phase/6-device-metrics.md`.

**4. Two tolerance/feature-family drifts must be fixed before the parity bodies are
written.**

- `test/parity/parity_test.dart` names the feature set `[RA, LC, BL, BW, E]`. That is
  `baseline5`, retained only as a rollback. The shipped family is `chen16_noheight` (16
  features), declared in `assets/ml/manifest.json` — see AGENTS.md rule 2 and
  `docs/adr/007-manifest-declared-feature-family.md`. The test must read the family and its
  order from the manifest, never from a literal list.
- Tolerances disagree between the two places that define them:

  | quantity | `parity_test.dart` | `ML/parity/compare.py` |
  |---|---|---|
  | view probability | 0.01 abs | 0.005 abs |
  | health probability | 0.01 abs | 0.01 abs |
  | feature | 0.005 rel | 0.01 rel |
  | weight | 0.5 kg abs | 0.1 kg abs |

  `ML/parity/compare.py` is the single source of truth — its docstring already says it is
  shared by `run_reference.py` and the Dart parity test. The Dart constants get deleted and
  regenerated from it.

**5. The scenario failure-reason vocabulary is dead code.** The eleven scenario titles in
`test/scenarios/functional_scenarios_test.dart` name reasons — `multiple_pigs`,
`pig_truncated`, `endpoints_too_close` — that exist only in
`lib/features/weight_estimation/domain/use_cases/weight_eligibility_checker.dart`. That
class is referenced by **nothing in `lib/`**; its only caller is its own unit test. The nine
§7 checks it implements were superseded by native gating in `pipeline.cpp`, and its check 9
still sanity-checks the `baseline5` quantities (`bl`, `bw`, `e`, `ra`, `lc`) rather than the
shipped `chen16_noheight` family. A scenario asserting those reasons would be testing a path
the app never runs. The live vocabulary the envelope actually carries is:

  | source | reasons |
  |---|---|
  | view gate | `view_rejected` |
  | reference / scale | `weight_needs_reference_object`, `reference_object_not_confirmed`, `scale_unavailable`, `scale_out_of_range`, `scale_resample_failed` |
  | quality gates | `posture_gate_rejected`, `truncation_gate_rejected` (and their `weight_`-prefixed forms) |
  | cutter | `cutter_failed`, `cutter_identity_stub`, `weight_unavailable_cutter_not_implemented` |
  | feature domain | `features_out_of_training_domain`, `mask_shape_out_of_domain`, `extrapolated_features` |

  Phase 4 asserts against this table. Whether `WeightEligibilityChecker` should be wired in
  or deleted is a separate decision and is **not** in this plan's scope — flagged, not fixed.

**6. Two manifest facts constrain what the weight scenarios can assert.** In the shipped
`assets/ml/manifest.json`:

- Both quality gates are **off** — `capabilities.weight.quality_gates` is
  `{"posture": false, "truncation": false}`. So `posture_gate_rejected` and
  `truncation_gate_rejected` cannot fire as shipped. A scenario targeting them must either
  flip the flag on a test copy of the manifest and say so, or assert the current gate-off
  behaviour instead of inventing a rejection.
- The weight capability is a **test override**, `stability: "temporary"`, and its own `note`
  reads: *"the regressor cannot predict below ~73 kg (ADR-010), so a pig under ~85 kg reads
  high; estimated_kg is not trustworthy."* See finding 7.

**7. The XGBoost regressor has a ~73 kg floor (ADR-010).** It cannot predict below roughly
73 kg, and a pig under ~85 kg reads high. Consequences for this plan:

- Every weight fixture must sit **above** the floor, or exist explicitly as an out-of-domain
  case asserting that the pipeline gates rather than reporting a number.
- Accuracy results computed from sub-floor samples are not valid evidence. This applies to
  the five-image corpus listed in `docs/test-plan.md`, two of which (`60.27kg_35.png`,
  `66.24kg_11.png`) are well under the floor — do not cite that run's accuracy findings here.
- Parity is unaffected: two implementations of the same model agree even out of domain, so a
  weight parity pass remains meaningful *as parity* while saying nothing about accuracy.

**8. `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` is the origin spec for all 21 tests, and
findings 1-7 were written without it.** Its §14 maps one-to-one onto the three skipped test
files: the model-parity list → the 4 parity tests, the eleven functional bullets → the eleven
scenarios *in the same order*, the device bullets → the 6 device metrics. Phases 4-6 below are
written against it, with the standing instruction from the user to **apply it against the
current pipeline, ignoring its training-stage content**. Parts of it are stale — most notably
its mandated feature order `RA, LC, BL, BW, E` (§2.5/§9), superseded by ADR-007's
manifest-declared `chen16_noheight`, which is what finding 4 already says. Treat it as the
requirements source, not as a description of today's code.

Three deltas it introduces that findings 1-7 do not cover:

- **§7 enumerates nine mandatory weight-eligibility checks**, and §12 requires explicit
  handling for multiple-pigs, pig-partly-out-of-frame and endpoints-too-close. Finding 5
  called those reason codes dead, which is true of the *code path* but not of the
  *requirement*. Phase 4 now carries an explicit nine-check audit rather than routing around
  it — see the mapping table there. This resolves the "flagged, not fixed" note finding 5
  left open, and matches `docs/handoff.md` decision 1 (the checker gets wired in, not
  deleted).
- **§6 requires validated, documented routing thresholds** in a `thresholds.json`, and §12
  requires a "low-confidence view result" state. Neither exists: the view routes on the bare
  argmax label (`pipeline.cpp` lines 285-291, no confidence threshold anywhere), and health
  uncertainty is a hardcoded `kHealthUncertainBelow = 0.60` in
  `run_and_persist_pipeline_use_case.dart:51` — exactly what §6 forbids ("Do not use an
  arbitrary threshold as a final value"). §16 additionally wants every prediction traceable
  to a threshold version. This is product work, not test work; phases 4 and 6 record it and
  assert current behaviour rather than inventing a threshold.
- **§14's parity list includes "segmentation masks and confidence"**, which phase 5 as
  originally drafted did not cover. Phase 3 dropped `MASK_3394` on the reasoning that both
  sides run the same segmentation — correct for native-vs-Python parity, but it leaves this
  §14 item with no fixture and no golden. Phase 5 now covers it.

One further §9 conflict is recorded here rather than solved: §9 says the app "should not
silently deploy a fixed-camera pixel model to arbitrary phone images", and that if no
validated physical-centimetre model exists the first release must **disable** weight
estimation. The shipped manifest carries `"feature_space": "fixed_camera_pixels"` *and*
`weight.available: true`, so `pipeline.cpp`'s `weight_override` path emits an `estimated_kg`
with a caveat note instead of disabling. The envelope is not silent — it labels every weight
result with its `capture_contract` — but it is not disabled either. Phases 4 and 5 assert
what ships and name this gap; changing `available` is a product decision outside this plan.

**9. The reference object is now mandatory, which deletes two scenarios and height mode.**
The user's decision this round: the app requires every weight capture to carry a marked
reference object, and the alternative height-calibrated route is withdrawn. Three consequences
for this plan.

- **Scenarios 4 and 10 are removed from the corpus and from the test file.** Both exist only to
  exercise a capture with no usable reference — scenario 4 withholds the endpoint marks on a
  118 kg frame, scenario 10 crops the reference stick out of a 96 kg frame. Neither premise is
  reachable through the required flow. This is a deliberate deviation from §14's functional
  list, which names "dorsal image without reference" (bullet 4) and "partially hidden
  reference" (bullet 10); it is recorded here rather than quietly dropped.
- **The surviving scenarios keep their original ids — 1, 2, 3, 5, 6, 7, 8, 9, 11 — and are not
  renumbered.** §14's bullets are the authority for what each scenario means, and renumbering
  would break that one-to-one mapping for every reader who opens the requirements document.
  Nine scenarios with two gaps in the numbering is the honest shape.
- **Height mode is withdrawn from the capture UI.** `capture_screen.dart:463` already reports
  it as non-functional ("weight estimation requires height-calibrated model (not yet
  available)") and the shipped family is `chen16_noheight`, so it produces no weight today.
  §8 explicitly requires "a clear option to switch between reference mode and height mode", so
  removing it is a second recorded §14/§8 deviation. The removal is **phase 4 task 5**, not a
  separate subphase. It is the one place this plan touches `lib/` production code beyond phase
  1's build wiring, which is a deliberate exception to the deferred list, made because the work
  is small, bounded, and follows directly from the same decision that deletes the two
  scenarios.

**What removing the scenarios does *not* remove** is the no-reference code path itself. A user
can still reach it by marking endpoints badly, by marking outside the accepted range, or
through `scale_out_of_range`. On that path `pipeline.cpp` still runs the cutter — ADR-008 gates
it on `is_dorsal && have_mask` alone, deliberately, to preserve telemetry — and `applyJiDuan`
sizes its morphological kernel as `mask_area / 800` with no upper bound, which on a large mask
produces a structuring element big enough to stall the pipeline indefinitely with no timeout.
Scenario 10 was the only fixture ever measured hitting this. Deleting it removes the coverage,
not the defect. **Correction after task 1 ran: it is not only scenario 10.** Scenarios 1, 2,
and 3 — all kept, none removed — stalled the same way on this exact mechanism, because none
of the corpus's reference pixel endpoints are hand-marked yet, so none of them currently
supply a real `cm_per_px` either. See phase 4 task 1 below for the measured detail.

**The stall is deliberately parked.** The user's call this round is to leave `applyJiDuan`
alone for now: it does not block any remaining phase, and both candidate fixes carry costs
this plan should not absorb. **Update: the scaled route is now confirmed clean.** After task
1's initial run, the user supplied real pixel measurements for scenarios 1-3's reference
objects; with a genuine `cm_per_px` supplied, all three completed in 8-9s each with no stall
(full detail in phase 4 task 1). That confirms — on these three photos, not as a general
proof — that a correctly-marked capture takes the scaled route (mask resampled toward the
~720x720 training frame) and does not reach the unbounded-kernel condition. The defect is
real and still unfixed, but it is now demonstrated to require an unmarked or badly-marked
reference to trigger, not just a large photo. It stays in the deferred list as a known,
unfixed defect — recorded so it is not rediscovered as a surprise, not scheduled.

## Phases

### Phase 1 — Windows host build of `instaham_ml.dll` — **DONE**

Record: `docs/metrics-phase/1-windows-host-build.md`. Built and verified; the DLL loads and
its C ABI answers. Two findings carry into phase 2: `DynamicLibrary.open` of an absolute path
does not put that directory on the search path for the library's own imports, and a stray
`C:\Windows\System32\onnxruntime.dll` (ORT API 1–10 only) wins over the correct copy and
crashes in `OrtGetApiBase` — so dependents must be preloaded by absolute path, ORT first.
One deviation from the plan below: the VS 2022 generator is used instead of Ninja, because
`vcvars64.bat` cannot find `vswhere.exe` on this machine and hangs non-interactively.

Original scope, as planned:

Extend `packages/instaham_ml_ffi/src/CMakeLists.txt` with a Windows branch beside the
Android one, so `INSTAHAM_ML_WITH_ORT=ON` stops being a fatal error off Android. Reuse the
toolchain recipe already proven in `ML/host_scale_test/README.md` verbatim — same vcpkg
OpenCV, same generated `onnxruntime.lib`, same in-repo ORT headers. The build target is a
shared library named `instaham_ml.dll`, not the existing CLI executable.

Constraint: the Android path must be unaffected. `android/build.gradle.kts` passes
`-DINSTAHAM_ML_WITH_OPENCV` explicitly and that must keep winning; the Windows branch is
additive and guarded on `WIN32`.

Deliverable: an `instaham_ml.dll` (with `onnxruntime.dll` and the OpenCV DLLs beside it)
that `openInstahamMl()` can open from the `flutter test` working directory.

Exit check: a throwaway Dart script opens the DLL and calls the ABI-version symbol,
returning the expected value.

### Phase 2 — Native test harness seam

The tests must not go through `MlRuntime`. `MlRuntime` stages assets via `rootBundle` and
resolves a directory via `path_provider`, neither of which works unmodified in a host
`flutter test` process, and forcing them to would mean adding test-only branches to
production loading code.

Instead add `test/support/native_harness.dart`: it creates the native context directly from
the repo's own `assets/ml/manifest.json` on disk, using the generated bindings, and exposes
the same envelope shape `IPipelineService.run` returns. Nothing in `lib/` changes.

The harness reports availability rather than throwing. Native-backed tests are gated on
`INSTAHAM_NATIVE_TESTS=1` **and** a loadable DLL; when either is absent they report a skip
with a precise reason. This keeps a machine without the C++ toolchain green while making the
gate explicit, and it is the one place in this plan where a remaining skip is acceptable.

Deliverable: `test/support/native_harness.dart` plus one smoke test asserting the harness
loads the manifest and reports the manifest-declared feature family.

### Phase 3 — Fixture corpus — **DONE, corpus superseded by phase 3.1**

Record: `docs/metrics-phase/3-fixture-corpus.md` (original), `docs/metrics-phase/
3.1-corpus-rebuild.md` (current corpus selection — sources every scenario from
`.pig_pictures/` and `health_pigs/` instead of PIGRGB, per the round-14 audit against
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14). Read 3.1, not the section below, for
what the corpus currently is.

Create `test/fixtures/scenarios/<id>/` with an image and a `meta.json` per scenario.
`meta.json` declares the *expected outcome contract* — view label, whether the weight branch
should produce a number, the expected failure reason code, the reference length in cm — and
never a predicted weight or confidence, so a fixture cannot smuggle an invented model score
into the suite (AGENTS.md, "Never display invented model scores").

Sources:

- Scenarios 1–3 (valid dorsal, 100 cm / 131 cm Porac / custom reference): the PIGRGB images
  already in-repo at `Instaham/PIGRGB-Weight/sub_1.78/` (`100.9kg_3.png`, `107.54kg_13.png`,
  `117.9kg_2.png`, `125.38kg_4.png`, `133.42kg_5.png`), whose scale is fixed by acquisition
  geometry rather than by hand-marking. All five are 100–133 kg, comfortably above the ~73 kg
  regressor floor (finding 7) — verify that before adding any further image. Note that the
  corpus listed in `docs/test-plan.md` is a *different, older* set that included two sub-floor
  images; do not copy that list.
- Scenarios 4–5 (no reference / side view): the same images with the reference annotation
  withheld, plus a side-view capture. **Scenario 4 is removed by finding 9.**
- Scenarios 6–10 (lesion close-up, multiple pigs, blur, truncation, hidden reference): a mix
  of existing field captures and deliberately degraded derivatives (Gaussian blur, crop,
  composite) generated by a committed script so the corpus is reproducible. **Scenario 10 is
  removed by finding 9.**
- Scenario 11 (HEIC / JPEG / PNG): one source image transcoded three ways, asserting the
  decode path and EXIF orientation handling agree across containers (AGENTS.md rule 5).

Keep the total corpus under roughly 15 MB and record provenance for every fixture in
`test/fixtures/scenarios/README.md`.

### Phase 4 — Un-skip the 9 functional scenarios — DONE

Write each body in two tiers.

*Tier A (always runs, no native dependency)* drives `RunAndPersistPipelineUseCase` with a
stubbed `IPipelineService` replaying a **recorded** envelope for that fixture, following the
pattern already established in
`test/features/inference_pipeline/weight_domain_failure_test.dart`. Tier A asserts the
contract: the correct failure reason code, weight withheld where it must be withheld, health
still assessed when the weight branch fails (AGENTS.md rule 4), and correct persistence.

*Tier B (gated on the phase 2 harness)* runs the same fixture through the real native
pipeline and asserts the envelope it produces still satisfies the tier A contract. Tier B is
what stops the recorded envelopes from silently going stale.

Assertions are on reason codes, branch independence, and gate behaviour — not on weight
values. Numeric agreement is phase 5's job.

**Task 0 — execute finding 9's corpus removal before anything else runs.** The decision is
recorded but the files still carry all eleven scenarios, so every count below is wrong until
this is done. Delete `test/fixtures/scenarios/04_no_reference_weight_blocked/` and
`test/fixtures/scenarios/10_hidden_reference/`; delete their two generator blocks in
`test/fixtures/scenarios/generate_fixtures.py`; remove their rows from
`test/fixtures/scenarios/README.md` and state there that ids 4 and 10 are intentionally absent
so a future reader does not treat the gap as corruption. Re-run the generator and confirm it
reports **nine** scenarios. Do not renumber the survivors.

**Task 1 — re-record every envelope first — DONE.** Round 14 ran the old corpus and wrote
`observed_phase4` blocks into each `meta.json`; phase 3.1 replaced every fixture image and
those blocks were gone (`docs/metrics-phase/3.1-corpus-rebuild.md`). All 9 surviving fixtures
were run through the harness with `INSTAHAM_NATIVE_TESTS=1` against the Windows host build,
one process per fixture under an external timeout, and the actual envelope (or stall) is now
recorded in each fixture's `meta.json` under `observed_phase4`.

**The prediction below was wrong, and finding 9's premise needs correcting as a result.**
Removing scenarios 4 and 10 does not take the `applyJiDuan` stall out of scope: **scenarios 1,
2 and 3 all stalled too**, each killed after >145s by an external timeout with no envelope
ever produced. The reason is not image size, it is reference state: none of the nine
fixtures' reference pixel endpoints are hand-marked (README "Known gaps"), so no fixture in
this pass supplied a real `cm_per_px`, and every fixture that reaches the cutter — regardless
of whether its `meta.json` says `reference.provided: true` — takes the *unscaled* route
(ADR-008), not the scaled one. The "carries a marked reference so takes the scaled route"
reasoning conflated "a reference object is physically visible in the photo" with "the app has
a confirmed scale for it"; only the second matters to the cutter, and nothing in this corpus
has the second yet.

Two things this run establishes that finding 9's text did not know:

- **The stall is reachable by more of the surviving corpus than believed, not less.**
  Scenarios 1-3's images are 1200x1600; each stalled. Scenario 11's is a 900x900 thumbnail of
  a similar frame, took the same unscaled route, and *did not* stall — it completed in 21.0s
  with `cutter.status: "cut_applied"`, mask area 108,256 px. That is consistent with the
  `mask_area / 800` kernel-sizing formula (finding 9): a smaller frame keeps the kernel under
  whatever threshold makes `cv::morphologyEx` finish in reasonable time, a larger one does
  not. It is not proof of the exact boundary — that needs a deliberate sweep, not four data
  points — but it confirms frame size on the unscaled route is the live variable, not whether
  a reference happens to be visible.
- **Round 14's "all four `.pig_pictures/` handheld captures failed the cutter
  (`no_terminal_balls` / `jiduan_failed` / `mask_implausibly_small`)" no longer holds, on
  all four.** Scenario 11 (`75kg_pig_meter_stick.HEIC`) reached `cutter.status:
  "cut_applied"` with `kept_fraction: 0.91` in the initial pass. After the user supplied real
  pixel measurements for scenarios 1-3's references, all three were re-run with a genuine
  `cm_per_px` and **all three also reached and passed the cutter** — no decline, no stall,
  8-9s each. This was the single biggest open risk this plan named, and it is now fully
  answered for this corpus: the cutter does not decline on handheld captures once a real
  scale is available. Weight predictions came back at 98.1 kg (92 kg recorded), 91.9 kg
  (96 kg recorded), and 96.9 kg (75 kg recorded) — the third's over-read matches ADR-010's
  own warning that near-floor pigs read high, and none of these numbers are asserted as
  accurate (finding 7 / phase 5's job).

**Endpoint marking is done for scenarios 1-3.** The user measured each reference span
directly in the app; converting from the app's `image_picker` cap (3000px, height-constrained
on these 3024x4032 originals) to the fixture's 1600px cap uses an exact ratio (1600/3000) on
this photo geometry, not an approximation. `cm_per_px` for each is recorded in the fixture's
own `reference.pixel_endpoints`. Scenario 3's 50 cm span is the user's full-tape measurement
(1582 px) halved rather than independently measured against the tape's own 50 cm tick,
accepted because this fixture's accuracy is explicitly not asserted (see phase 3's sourcing
notes). Scenario 11's endpoints remain unmarked; its `expect_number: true` assertion (task 2)
still depends on that being done before Tier B can be numeric there.

Full per-fixture detail — envelope, elapsed time, and reasoning for every result including the
now-superseded initial stalls — is recorded in each fixture's own `meta.json` under
`observed_phase4`, not duplicated here.

**Task 2 — restate the nine surviving titles against §14 and the live vocabulary — DONE.** The titles
currently name `multiple_pigs`, `pig_truncated` and `endpoints_too_close`, which only the
unwired `WeightEligibilityChecker` produces (finding 5). §14's eleven functional bullets are
the *requirement*; the live reason table in finding 5 is what the pipeline can *say* today.
Each title states the §14 bullet; each assertion uses the live vocabulary:

| # | §14 bullet | live assertion |
|---|---|---|
| 1 | valid dorsal, 100 cm reference | full weight branch with a marked reference; blocked by whatever task 1 records if the cutter still declines on handheld captures |
| 2 | valid dorsal, 131 cm reference | same |
| 3 | valid custom reference length | same, with the custom length supplied via `cm_per_px` rather than a preset |
| ~~4~~ | ~~dorsal without reference~~ | **removed — finding 9.** The required capture flow cannot produce it |
| 5 | side-view health image | `health_only` route: no segmentation, no cutter, no weight; health assessed |
| 6 | close-up lesion image | whatever view the classifier returns; health assessed, weight not reached |
| 7 | multiple-pig image | whatever segmentation + mask-selection actually emits; `multiple_pigs` never reaches the envelope |
| 8 | blurry image | view label as recorded; if radius-8 blur does not reach `reject`, either raise the radius and regenerate or assert the gate-off behaviour honestly |
| 9 | partially cropped pig | `truncation_gate_rejected` **only** with the manifest's `truncation` gate flipped on for that test; otherwise assert the gate-off behaviour |
| ~~10~~ | ~~partially hidden reference~~ | **removed — finding 9.** The required capture flow cannot produce it |
| 11 | HEIC/JPEG/PNG | §14 says "where supported". JPEG and PNG must agree; the HEIC leg asserts the *documented* decode posture, not an invented success — see the note below |

Scenarios whose expected reason cannot be produced by the current pipeline at all are
recorded as such in the fixture's `meta.json` and asserted as "weight withheld, health still
assessed" rather than being given an invented reason code.

**Scenario 11's HEIC leg.** `util/image_io.cpp` builds stb_image with
`STBI_ONLY_JPEG`/`PNG`/`BMP`, so native cannot decode HEIC at all, and
`lib/core/utils/image_service.dart` always bakes EXIF and re-encodes to JPEG before any path
reaches native — the shipped app never hands native a raw `.heic`. §14's own wording is
"HEIC/JPEG/PNG inputs **where supported**". The test asserts that contract: HEIC is supported
*through the Dart capture layer*, not at the native boundary. Do not extend the native
decoder to satisfy a test.

**Task 2 results (2026-09-12).** Row 5's prediction above (`health_only` route) and row 7's
(vocabulary "TBD") were both written before task 1's rerun; task 1's own findings section
already corrected them, and task 2 applies those corrections to the fixtures themselves. All
nine `meta.json` files now state `expected_outcome` from `observed_phase4`, not from a
hypothesis:

- **Scenarios 5 and 7 both resolve at the view stage itself, not downstream.** Both are
  rejected outright (`view: reject`, envelope `status: stopped`, reason `view_rejected`)
  before segmentation, the cutter, or health classification run — off-dorsal framing and a
  two-pig frame both read `reject` at >0.96 confidence. Titles now read "view rejected
  (weight and health both withheld)"; `health_branch.expect_assessed` corrected from `true`
  to `false` on both. There is no live "multiple pigs detected" reason; `multiple_pigs` stays
  dead (finding 5), and §7 check 1 is not exercised by scenario 7 because the frame never
  reaches segmentation — recorded as a gap in task 3's audit, not asserted as a pass.
  **(Phase 4.1, 2026-09-12: scenario 7 was removed for exactly this reason — it never
  exercised §7 check 1 and only duplicated scenario 5's `view_rejected` assertion. §14
  bullet 7 is now an accepted coverage gap. Scenario 5 is unaffected and stays as recorded
  here.)**
- **Scenarios 6 and 9 kept `health_only` but had the wrong failure reason.** Both listed
  `weight_needs_reference_object` (a dead `WeightEligibilityChecker` string); corrected to
  the live `view_not_dorsal`.
- **Scenario 8's blur does not reach `reject` — asserted honestly rather than regenerated.**
  User decision, 2026-09-12: keep the radius-8 image and state the true outcome (`health_only`
  at 0.9999998 confidence) instead of raising the blur radius to force a `reject` that isn't
  the point of the fixture. Title now reads "health_only (radius-8 blur does not trigger
  reject)". This does not mean the pipeline has no reject state — scenarios 5 and 7 both hit
  it — only that this fixture's specific blur strength does not.
- Scenarios 1, 2, 3, and 11 needed no change; their titles and `expected_outcome` already
  matched §14 and, for 1-3, the task-1-rerun's confirmed numeric outcome.

**Task 3 — audit §7's nine eligibility checks — DONE.** §7 makes nine checks mandatory and §12
requires explicit multiple-pigs / partly-out-of-frame / endpoints-too-close states, so the
plan can no longer simply route around `WeightEligibilityChecker` (`docs/handoff.md`
decision 1: it gets wired in, not deleted). Map each check to what the pipeline does today
and assert that, recording every gap:

| § | check | live status |
|---|---|---|
| 1 | exactly one usable pig instance | **no gate.** `postprocess.single_largest_instance` picks the largest and never rejects on count; `candidates_kept` is recorded but unused as a gate |
| 2 | full body inside frame | gate exists (`run_truncation_gate`), **off** in the shipped manifest |
| 3 | no severe truncation/occlusion | partial — segmentation `conf 0.25` / `retry_conf_threshold 0.1`, plus the same off truncation gate |
| 4 | suitable dorsal posture | gate exists (`run_posture_gate`, `posture_max_bend_deg 40`), **off** in the shipped manifest |
| 5 | valid reference object available | **live** — `reference_object_not_confirmed` |
| 6 | known positive real-world length | **live but merged into check 5's reason** — the same `!cm_per_px \|\| !isfinite \|\| <= 0` test, no distinct code |
| 7 | endpoints valid and far enough apart | **not in native.** `cm_per_px` arrives pre-computed from Dart; this must be a Dart-side check |
| 8 | reference coplanar with the pig | **not in native.** `IPipelineService.run`'s contract says the caller must have confirmed coplanarity (AGENTS.md rule 7) |
| 9 | mask and features pass sanity ranges | **live and chen16-based** — the manifest's `feature_domain` gates plus `min_mask_diagonal_fraction: 0.35` |

The pipeline also enforces `scale_out_of_range` (a camera-height ratio bound) which §7 does
not name — keep it; it is a real check, not a missing one.

`WeightEligibilityChecker`'s check 9 still sanity-checks `bl`, `bw`, `e`, `ra`, `lc` — the
`baseline5` quantities the shipped `chen16_noheight` family never produces. **Wiring the
class in unchanged would re-introduce the exact drift finding 4 exists to prevent.** Check 9
must either be rewritten against the manifest-declared family or delegate to the native
`feature_domain` gate that already does this job. Checks 7 and 8 are the two that genuinely
belong in Dart and have no native equivalent; they are the strongest argument for keeping the
class. Deciding the class's final shape is still product work — this task's deliverable is
the audit and the tests that pin current behaviour, not the rewiring.

**Task 3 results (2026-09-12).** Every cell in the table above was cross-checked against the
live source, not left as prose:

- Confirmed by grep: `WeightEligibilityChecker` is referenced nowhere in `lib/` outside its
  own definition file — genuinely unwired, matching `docs/handoff.md` decision 1.
- Confirmed against source: `postprocess`'s largest-mask selection (`segmentation.cpp`)
  never gates on `candidates_kept` (check 1); `run_truncation_gate`/`run_posture_gate`
  (`stages/quality_gates.cpp`) exist and are wired behind the manifest's `quality_gates`
  switch (checks 2/4); `reference_object_not_confirmed`/`scale_out_of_range`
  (`pipeline.cpp`) are the live check-5/6 reasons; `run_feature_domain_gate` plus
  `min_mask_diagonal_fraction` (`pipeline.cpp`) are the live check-9 mechanism, not the
  dead `WeightEligibilityChecker.check()`'s `bl`/`bw`/`e`/`ra`/`lc` sanity test.
- **New pinning test: `packages/instaham_ml_ffi/src/test/test_shipped_manifest.cpp`.**
  Loads the real `assets/ml/manifest.json` (not a synthetic fixture, unlike
  `test_feature_domain.cpp`) and asserts the live §7-relevant facts as shipped:
  `quality_gate_truncation == false`, `quality_gate_posture == false`,
  `quality_gate_posture_max_bend_deg == 40.0`, `feature_family == "chen16_noheight"`,
  `feature_order.size() == 16`, `min_mask_diagonal_fraction == 0.35`, and that
  `feature_domain` carries `mask_area`/`body_curve` keys. Wired into
  `packages/instaham_ml_ffi/src/test/CMakeLists.txt` (pure JSON parsing, no OpenCV/ORT,
  builds and runs unconditionally like `test_feature_domain`). Built against
  `build/windows-host` and run directly: `test_shipped_manifest: all assertions passed`,
  exit 0. If a future manifest edit silently flips a gate or drops a domain key this task
  relied on, this test fails instead of only the audit prose going stale.
- `test/features/weight_estimation/weight_eligibility_checker_test.dart` already pinned the
  class's own 9-check contract in isolation (pre-existing, not written this task); a header
  comment was added clarifying it pins the *unwired class's own behaviour*, not what the
  live pipeline does — the two must not be conflated when task 4 or a future rewiring reads
  this file.
- **Incidental finding, not fixed here:** rebuilding to add `test_shipped_manifest` also
  rebuilt `test_feature_domain`, and its binary now crashes on run (`STATUS_STACK_BUFFER_
  OVERRUN`, exit `-1073740791`) on this host, via both `git bash` and PowerShell invocation.
  `test_feature_domain.cpp`/`manifest.cpp`/`sha256.cpp` were not touched by this task (`git
  status` confirms) and `test_shipped_manifest` — built from the same `manifest.cpp`/
  `sha256.cpp` — passes cleanly, so this is not this task's regression. Carried forward
  alongside the existing `test_scale_normalization` failure on `main` as an open native-test
  health issue for a future round to isolate.

**Task 4 — write the two-tier bodies — DONE.** Per the tier A/B description above. Nine
bodies, not eleven; the scenario 4 and 10 `skip:` slots in
`test/scenarios/functional_scenarios_test.dart` are deleted rather than filled.

**Task 4 results (2026-09-12).** `test/support/scenario_fixture.dart` (new) loads a
fixture's `meta.json` by scenario id so the nine bodies don't duplicate JSON-path knowledge.
`test/scenarios/functional_scenarios_test.dart` was rewritten in full: Tier A stubs
`IViewModelService`/`IPipelineService` and replays each fixture's own
`observed_phase4.envelope` through `RunAndPersistPipelineUseCase`, asserting the persisted
weight/health contract from `expected_outcome`; Tier B runs the same image through
`NativeHarness` (phase 2) and asserts the same contract off the raw envelope.

- **Real finding, not fixed here:** `RunAndPersistPipelineUseCase.resolveViewGate` ignores
  the constructor-injected `IViewModelService` whenever no `view` `PipelineEvent` is already
  persisted for the scan — it always falls back to the real `ViewModelServiceImpl()`
  default, which tries to load the native DLL and throws in a plain `flutter test` process.
  `weight_domain_failure_test.dart` already works around this by pre-persisting a view event
  via `RunAndPersistPipelineUseCase.recordViewGate` before calling `execute()`; every Tier A
  body here does the same. This is a real latent bug (constructor injection is silently a
  no-op on this path) worth a subphase, not fixed inline per the "new issues become
  subphases" rule.
- Scenario 9's "gate flipped on" truncation case and scenario 11's cross-container numeric
  check are explicit `skip:` tests with reasons, not fabricated passes — the first needs a
  second manifest copy through the native harness (not built here), the second needs
  scenario 11's endpoints marked (task 1's open item, still open).
- Scenario 11's HEIC leg is a documented `skip:` rather than a native run: the contract it
  asserts (native never sees a raw `.heic`) is architectural, not something
  `NativeHarness.run()` exercises the way the jpeg/png legs do.
- Validation run: `dart format` clean on both new/changed files; `flutter analyze` clean
  (one `ambiguous_import` on `isNotNull` between `drift` and `matcher` fixed by dropping the
  unused `drift` import, matching `weight_domain_failure_test.dart`'s `hide isNull`
  precedent). `flutter test test/scenarios/functional_scenarios_test.dart` without
  `INSTAHAM_NATIVE_TESTS`: 8 Tier A tests pass, 5 Tier B tests skip cleanly (harness opt-in
  gate off), 3 documented-deferral skips, 0 failures. With `INSTAHAM_NATIVE_TESTS=1` against
  `build/windows-host/Release/instaham_ml.dll`: all 18 runnable tests pass (Tier A + Tier B,
  jpeg/png legs of scenario 11 included), 3 documented skips, 0 failures, ~1m32s total.

**Task 5 — remove height mode from the capture UI — DONE.** (finding 9). The same decision that
deletes the two scenarios withdraws the height-calibrated route, so it is done here rather
than deferred. Scope:

| file | change |
|---|---|
| `lib/features/capture/presentation/screens/capture_screen.dart` | remove the mode toggle and the height prompts at lines 211, 268, 337, 463 |
| `lib/features/capture/data/capture_preferences.dart` | remove `_keyHeightCm`, `saveHeight`, and the height loader |
| `lib/features/capture/presentation/screens/capture_guidance_screen.dart` | line 18 copy still reads "or set camera height" |
| `docs/design-system.md` | the capture-mode contract |

`camera_height_cm` **stays in the Drift schema and is simply no longer written.** Dropping the
column would force a `schemaVersion` increment, an explicit migration, regenerated Drift
output and a migration test (AGENTS.md, "Database rules") for no behavioural gain, and it
would discard the height values already recorded against past captures.

This task is the plan's only `lib/` change and the only one requiring `dart format`,
`flutter analyze` and a targeted `flutter test` run on capture-feature tests. Keep it as the
last task in the phase so a failure here cannot contaminate the envelope recordings that
tasks 1-4 depend on.

**Task 5 results (2026-09-12).** All four files changed as scoped, plus one deletion the
scope table didn't name:

- `capture_screen.dart`: `_mode` is now `static const MeasurementMode.referenceObject`
  (kept, not deleted — `measurementMode` still needs a value to write every capture) rather
  than mutable state; the mode-toggle header replaced with a static title; `_cameraHeight`
  state, `_openHeightConfig`, the height guard branches in `_capture()`/`_pickFromGallery()`,
  the height chip, the height guide painter, and the dead `_MeasurementModeSelector` /
  `_HeightGuidePainter` classes all removed. `_usePhoto()` no longer writes
  `cameraHeightCm` and its dead "Height mode — ..." pipeline-event message is gone.
- `capture_preferences.dart`: `_keyHeightCm`, `saveHeight`, `loadHeight` removed.
- `capture_guidance_screen.dart`: line 18's "(or set camera height)" / reference-only
  wording fixed.
- `docs/design-system.md`: the flow diagram and camera-control-hierarchy bullets no longer
  name Height Mode as a live option; both note the withdrawal and that
  `measurementMode`/`camera_height_cm` still render for pre-existing scans.
- **Deleted, not in the scope table:** `lib/features/capture/presentation/widgets/
  height_mode_settings.dart` — grep-confirmed its only caller was the `_openHeightConfig`
  method just removed, so it became genuinely dead code, not merely unused-but-reachable.
- `results_screen.dart`'s `MeasurementMode.fixedHeight` display branch (renders
  `camera_height_cm` for a scan captured under the old mode) was deliberately left
  untouched — it is exactly the "still renders for pre-existing scans" contract the plan
  requires, not a leftover to clean up.
- Validation: `dart format` clean on all three changed Dart files. `flutter analyze
  lib/features/capture` — no issues. Full-project `flutter analyze` — 7 pre-existing issues,
  all in vendor/generated files (`model_and_cutter/`, `instaham_ml_bindings_generated.dart`),
  none touched by this task. No capture-feature `flutter test` file exists in the repo to
  run targeted (`test/` has no `*capture*` test) — noted rather than fabricated.

### Phase 4.1 — Remove scenario 7; keep scenario 5's `reject` — **DONE**

Record: `docs/metrics-phase/4.1-scenario-7-removal.md`. Fixture and test-corpus work only —
no `lib/`, model, or manifest change.

**Result (2026-09-12).** All 5 tasks executed. `Scenario 7` group deleted from
`functional_scenarios_test.dart` (Tier A count 8→7, same skip set, confirmed by a full test
run); scenario 8's stale "scenarios 5 and 7" comment corrected to scenario 5 only. Fixture
directory `07_multiple_pigs_composite/` deleted along with its `generate_fixtures.py` block;
regenerating confirmed the 8 remaining images are byte-identical to what shipped (the
generator's own `meta.json` output is a pre-phase-4 stub, not byte-identical to the
hand-edited `observed_phase4` fixtures — restored from the pre-regeneration copy and noted
in the README so a future run doesn't silently clobber it). `README.md` and this plan's End
state table updated to 8 scenarios with §14 bullet 7 recorded as an accepted gap.
`INSTAHAM_NATIVE_TESTS=1 flutter test test/scenarios/functional_scenarios_test.dart` rerun:
16/16 pass (down from 18, exactly the two scenario-7 legs removed), ~1m22s, same skip set.

Two decisions taken 2026-09-12:

1. **Scenario 7 (`07_multiple_pigs_composite`) is deleted.** Its frame is rejected at the
   view stage (0.9614), so segmentation and mask selection — where §7 check 1 lives — never
   run, and the `multiple_pigs` reason code it was written for is dead (finding 5). What it
   actually asserts duplicates scenario 5. Covering §14 bullet 7 honestly would need two pigs
   both in *valid dorsal framing*; no such photo exists in the corpus. **§14 bullet 7 becomes
   an accepted gap**, joining the two already accepted (no third reference object, no real
   lesion close-up).
2. **Scenario 5 stays exactly as written**, asserting the view classifier's `reject`. Round
   17 left this open on the premise that the app has no reject state; it does — see
   `capture_screen.dart:364` and `run_and_persist_pipeline_use_case.dart:72`, both of which
   set `ScanStatuses.rejected` and withhold both branches. The question is closed as no
   change. Whether a side-on capture *should* route to `health_only` so lateral photos can
   still get a skin assessment is a separate model/product question, deferred there.

### Phase 5 — Un-skip the 4 parity tests — **DONE, then DEFERRED by team decision**

**Superseding decision (2026-09-12, team): the parity workstream will not be used.** The
suite below was written and passed, but parity is no longer a gate on anything downstream,
and subphase 5.1 (native mask export) is not being taken. §14's "Model-parity testing"
section is therefore unmet in full — including the §18 checklist item "Exported-model parity
tests have passed" — as a recorded deviation from
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md`, not as a gap in this plan. The cost of that
deferral is written up in `docs/metrics-phase/6-device-metrics.md`, section "Phase 5 is
deferred". The suite and `ML/parity/` stay in the tree as executed work; nothing is deleted.
Everything below records what was built before the decision.

Plan and results: `docs/metrics-phase/5-parity-tests.md` — **DONE**, with one task (6,
segmentation parity) left as a reasoned `skip` rather than written unsoundly. That document
supersedes the steps below where the two differ. Six findings from inspecting the current
tree changed the shape of this phase; the load-bearing one is that the envelope exports no
mask geometry, so step 5's mask comparison cannot be written as stated and the mask-dependent
legs run on held-equal inputs instead. Execution then found a deeper version of the same
problem: no independent Python segmentation oracle can be built in this repo at all (the
training-time `src/` package is not present). The native mask-export seam that would fix both
is recorded there as subphase 5.1, not taken here. Final state: view, health, weight
(held-feature), and feature-order/family/status legs all pass native-gated
(`INSTAHAM_NATIVE_TESTS=1`); the chen16 feature leg runs the full port gate (500 masks, 0
mismatches) via a committed Python golden plus a direct native-CLI call from Dart, after an
initial version that spawned `python` from Dart proved ~15x slower under `Process.run` than a
shell and intermittently timed out. Full suite: 129 passing, 16 skipped, 0 failing.

§14's model-parity list has five items — view probabilities, **segmentation masks and
confidence**, health probabilities, the extracted features, and final weight predictions —
against four existing test slots. The segmentation item has no fixture and no golden today
(phase 3 dropped `MASK_3394`); it is added here rather than left uncovered. §14 also says
"define numerical tolerances before release", which step 1 satisfies.

1. Delete the four local tolerance constants; import them from a generated
   `test/fixtures/parity/tolerances.json` written by `ML/parity/compare.py`, so the numbers
   have exactly one definition. Add a segmentation tolerance to `compare.py` at the same
   time — mask IoU (or an equivalent agreement measure) plus an absolute bound on
   `segmentation.confidence`.
2. Rewrite the feature test from `[RA, LC, BL, BW, E]` to the manifest-declared family,
   reading `feature_order.json` / `xgboost.meta.json` for names *and* order.
3. Generate goldens with `ML/parity/run_reference.py` over the phase 3.1 fixtures into
   `test/fixtures/parity/expected.json`. Note these are the rebuilt handheld fixtures, not
   the PIGRGB images the original draft assumed.
4. Each body: run the fixture through the phase 2 harness, compare against the golden at the
   imported tolerance, and fail with the mismatching key, expected, actual, and tolerance —
   the `Mismatch` shape `compare.py` already defines.
5. Cover §14's segmentation item — assert the native mask agrees with the Python oracle's
   mask on the same image, and that `segmentation.confidence` matches within tolerance. This
   is native-vs-Python agreement on mask *geometry*, not accuracy against a ground-truth
   annotation; no fixture in this corpus carries one, and §14 does not ask for one.

The weight parity test additionally pins `cm_per_px_actual` from acquisition geometry per
`docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md`; it is a derived constant and must not be
tuned to make the test pass.

**Resolved by phase 4 task 1:** the cutter does not decline on this corpus once a real
`cm_per_px` is supplied — scenarios 1, 2, and 3 all reach the cutter and pass it (task 1's
rerun, 2026-09-12). The feature and weight parity legs have fixtures that reach them on the
handheld phase 3.1 corpus directly; PIGRGB is not needed as a fallback here. It remains
available for the segmentation-parity item below regardless.

Two scope limits the weight parity test must state in its own comment, so a future reader
does not over-read a green run:

- It measures **native-vs-Python agreement, not accuracy.** The manifest's own note says
  `estimated_kg` is not trustworthy (`stability: "temporary"`, a test-override capability),
  and the regressor cannot predict below ~73 kg (finding 7). Both implementations produce the
  same untrustworthy number, so parity passing says nothing about correctness against a
  scale.
- Its fixtures stay above the ~73 kg floor. A sub-floor fixture belongs here only as an
  explicit out-of-domain case, never as a tolerance case.

### Phase 6 — Redistribute the 6 device metrics

Plan: `docs/metrics-phase/6-device-metrics.md` — **all seven tasks complete as of
2026-09-13.** That document supersedes the steps below where the two differ. It carries the phase 5 deferral, the
re-disposed metric 6, four agreed targets (a product decision of 2026-09-12, **not** §14
requirements — §14 states no number for any metric), execution of metrics 1-3 through the
Firebase Test Lab runbook in `docs/device-testing-plan.md`, and seven numbered tasks.

| metric | disposition |
|---|---|
| 1 — cold start | move to `integration_test/benchmark_test.dart`, already implemented there as time-to-first-stable-frame |
| 2 — median/P95 inference latency | move to `integration_test/`; its body is currently a `markTestSkipped` placeholder, wire it to the real pipeline |
| 3 — memory footprint at peak inference | move to `integration_test/`; the existing body only measures startup |
| 4 — model package size | **becomes a host test** — pure file stat, no device needed |
| 5 — battery/thermal over 50 scans | **dropped** by decision of 2026-09-13 — no test, no owner, no execution path sought; a knowing deviation from §14, recorded in full under "Metric 5 is dropped" in `docs/metrics-phase/6-device-metrics.md` |
| 6 — quantization/export parity | **becomes a standalone host test** reading the manifest's recorded export deltas — no longer folded into phase 5's parity suite, which is deferred |

`test/device/device_benchmarks_test.dart` is then reduced to metric 4 and renamed to
something host-honest such as `test/assets/model_package_size_test.dart`, with the rest
removed and a comment pointing at `integration_test/` and `docs/device-testing-plan.md`.

Open question metric 4 must settle before it is written: the stated target is under 50 MB,
but current sizes are

```
 9.50 MB  assets/ml/view/model.onnx
18.68 MB  assets/ml/health/model.onnx
38.46 MB  assets/ml/segmentation/yolo.onnx
 0.97 MB  assets/ml/weight/xgboost.onnx
```

Every individual model is under 50 MB; the bundle total is 67.6 MB and is not. **§14 does not
resolve this** — its device list says only "model file sizes", with no target at all, so the
50 MB figure comes from elsewhere and the requirements doc cannot arbitrate it. The test must
assert against whichever the requirement actually means. Decide before writing the assertion,
and record the decision *and* the fact that §14 sets no number in the test's own comment.

**§14's closing constraint governs this whole phase:** "GPU or desktop latency from the
notebooks must not be reported as phone latency." Metrics 1-3 stay device-only for that
reason; the Windows host build from phase 1 must never be used to produce a latency or memory
number that gets written down as a device result. `docs/device-testing-plan.md` is the runbook.

**Two §14/§16 items this phase should carry, both currently unowned.** They are small, they
belong to the device/release gate rather than to any other phase, and leaving them unwritten
is how they get lost:

- **§14 device bullet 6, "accuracy after model export or quantization."** The table above
  originally routed this into phase 5's parity suite; with parity deferred it is now a
  standalone host test (phase 6 task 5). This was always the better home — export accuracy is
  checkpoint-versus-exported-ONNX, a different question from port parity. The manifest records
  the export self-checks (`onnx_max_abs_diff` per classifier, `box_mask_max_abs_diff` and
  `proto_max_abs_diff` for segmentation, `fusion_max_abs_diff` for health). A host test that
  asserts those recorded deltas stay within tolerance costs almost nothing and covers the
  bullet directly.
- **§16 traceability.** Every prediction must be traceable to app, deployment-package, per-
  model, preprocessing, threshold and reference-length versions. The manifest carries
  `bundle_id`, `reference_commit`, `schema_version`, per-model `sha256` and
  `protocol_version`; what has no version at all is the threshold set (finding 8 — there is
  no `thresholds.json`, and `kHealthUncertainBelow` is a bare constant). Assert what exists
  and record the threshold gap rather than inventing a version for it.

## End state

| test group | after this plan |
|---|---|
| 8 functional scenarios | tier A always runs; tier B runs with `INSTAHAM_NATIVE_TESTS=1` |
| 2 functional scenarios (4, 10) | removed, not skipped — finding 9; §14 bullets 4 and 10 deviated from on the record |
| 1 functional scenario (7) | removed, not skipped — phase 4.1; §14 bullet 7 an accepted gap, no fixture exercises multi-pig mask selection |
| 4 parity tests | written and passing, but **deferred by team decision** — not a gate; §14's model-parity section unmet in full |
| metric 4 (package size) | always runs; asserts < 50 MB **per model** (bundle total ~68 MB deliberately not asserted) |
| metrics 1–3 | run on three real devices via `integration_test/` + Firebase Test Lab; metric 1 asserts < 2 000 ms, metrics 2-3 report only |
| metric 5 | **dropped** (2026-09-13) — removed, not skipped; §14's battery/thermal bullet deviated from on the record |
| metric 6 | standalone host assertion on the manifest's recorded export deltas |
| §14 segmentation parity | **not covered** — no Python segmentation oracle exists in this repo, and the parity workstream is deferred |
| §7's nine eligibility checks | audited and pinned by phase 4 task 3; gaps recorded, not silently filled |

Skips remaining in a default `flutter test` run: the native-gated tier B and parity tests,
each with an actionable reason naming the environment variable and the missing DLL — not
"needs concrete ML service".

## Validation per phase

1. `dart format` on changed Dart files.
2. `flutter analyze` after every phase that touches Dart.
3. `flutter test test/scenarios/functional_scenarios_test.dart` (phase 4) and
   `flutter test test/assets/model_package_size_test.dart` (phase 6). The phase 5 parity run
   is no longer required — the workstream is deferred; the suite stays runnable by hand via
   `INSTAHAM_NATIVE_TESTS=1 flutter test test/parity/parity_test.dart`.
   Phase 4 task 5 is the one task that changes `lib/`, so it additionally needs `dart format`
   on the changed Dart files, `flutter analyze`, and a targeted run of whatever capture-feature
   tests exist. Run it last in the phase.
4. Full `flutter test --reporter=compact` at the end of phases 4, 5, and 6, reporting the
   `+N ~M` line each time so the skip count stays visible.
5. Native builds: the existing `packages/instaham_ml_ffi/src/test/` ctest suite must still
   configure and pass after the phase 1 CMake change. It needs `INSTAHAM_ML_WITH_ORT=ON` and
   an MSVC environment (`vcvarsall.bat x64`) to configure, and `instaham_ml.dll` plus
   `onnxruntime.dll` staged beside the test executables or they exit `0xc0000135`. Current
   state on this machine: 7 of 9 pass; `test_abi` asserts a pre-manifest-parsing skeleton
   behaviour and `test_scale_normalization` is the documented pre-existing failure.
6. `integration_test/` runs are device-only and are reported as not run on this machine.

## Risks and what would invalidate this plan

- ~~**Phase 1 fails to produce a loadable DLL.**~~ Retired — phase 1 is done and the DLL
  loads. The fallback it described (tier A plus metric 4, 12 of 21, with no native build) is
  no longer needed on this machine, but still describes what any machine without the C++
  toolchain gets.
- **Scenario expectations outrun the pipeline.** Findings 5 and 6 mean several scenario
  titles describe behaviour the shipped app does not produce — dead reason codes, and two
  quality gates switched off. The failure mode to avoid is writing a test that asserts an
  invented reason and then "fixing" the pipeline to emit it. Restate the scenario against
  live behaviour, or record it as unproducible; do not change product code to satisfy a
  test title inherited from an older design.
- **Reading weight parity as accuracy.** The regressor is a temporary test override with a
  ~73 kg floor and an explicit "not trustworthy" note in the manifest. Parity green means the
  two implementations agree, nothing more.
- **Host and device numeric divergence.** Windows x64 CPU ORT and Android arm64 ORT may not
  agree bit-for-bit. Parity tolerances are for host-versus-Python, not host-versus-phone; a
  host parity pass is not evidence about phone behaviour, and desktop latency must never be
  reported as phone latency.
- **Golden staleness.** Any change to models, manifest, or stage order invalidates
  `expected.json`. Regeneration must be a documented one-liner, and `spec-drift` should be
  run alongside it.
- **Fixture corpus honesty.** If a scenario cannot be sourced with a genuine image,
  synthesize it explicitly and label it in the provenance README rather than approximating it
  with an unrelated photo.
- **Treating a §14 requirement as licence to change product code.** Finding 8 adds three
  requirements the pipeline does not currently meet: nine eligibility checks (several
  ungated), validated routing thresholds (absent entirely), and a weight capability that §9
  says should be disabled but ships enabled. This plan's job is to *test* what ships and
  *record* each gap — not to implement §6's thresholds, flip `weight.available`, or wire
  `WeightEligibilityChecker` in order to make a test green. Each of those is a product
  decision with its own consequences.
- **Removing scenarios 4 and 10 removes coverage, not behaviour.** Finding 9 deletes the two
  no-reference fixtures because the capture flow now requires a reference, but the
  no-reference code path stays reachable through bad endpoint marks and `scale_out_of_range`,
  and the unbounded `applyJiDuan` kernel on that path is still a real stall with no timeout.
  After this plan, nothing in `test/` exercises it. The failure mode to avoid is reading a
  green nine-scenario suite as evidence that the no-reference path is safe; it is evidence
  that it is no longer tested. The stall itself is parked by explicit decision (see
  "Intentionally deferred"), so this risk is accepted, not mitigated.
- ~~**The rebuilt corpus cannot reach the weight branch.**~~ Retired — task 1 answered this.
  Phase 3.1's corpus is handheld-only, and on the old (round-14) corpus every handheld
  capture declined in the cutter. On the rebuilt corpus, with a real `cm_per_px` supplied,
  scenarios 1, 2, and 3 all reach the cutter, all pass it, and all produce a weight number.
  Phases 4 and 5 keep their feature/weight leg on this corpus; PIGRGB is not needed as a
  fallback for it. This was the single biggest open risk to the remaining phases and task 1
  is what resolved it.

## Intentionally deferred

- **The whole parity workstream (phase 5 and subphase 5.1), by team decision, 2026-09-12.**
  The suite exists and passes but gates nothing; native mask export is not being built. §14's
  "Model-parity testing" section and the §18 checklist item "Exported-model parity tests have
  passed" are knowingly unmet. Nothing standing now checks that the C++ port still agrees with
  the Python original; `ML/parity/chen16_feature_port_gate.py` remains runnable by hand if
  that question returns. Full cost write-up in `docs/metrics-phase/6-device-metrics.md`.
- iOS host build.
- CI wiring for the native-gated tier; this plan only makes it runnable locally.
- Metric 5 (battery/thermal) in any form — **dropped** 2026-09-13, not deferred to a later
  phase; see `docs/metrics-phase/6-device-metrics.md`, "Metric 5 is dropped".
- Any change to `lib/` production code beyond what phase 1's build wiring required, **except
  phase 4 task 5's height-mode removal**, which finding 9 brings in scope.
- **Deciding the final shape of `WeightEligibilityChecker`** — phase 4 task 3 now audits
  §7's nine checks against live behaviour and pins what ships, and `docs/handoff.md`
  decision 1 already rules that the class gets wired in rather than deleted. What stays
  deferred is the rewiring itself, including rewriting its `baseline5`-era check 9 against
  the manifest-declared family. That is product work.
- **§6's routing thresholds and a `thresholds.json`** (finding 8). The view has no confidence
  threshold and health's lives in a bare Dart constant. Phases 4 and 6 assert and record
  current behaviour; selecting validated thresholds from held-out results is model/product
  work outside this plan.
- **Resolving §9's feature-space conflict** (finding 8) — whether `weight.available` should
  ship false while the model remains `fixed_camera_pixels`. The tests assert what ships.
- **Bounding the `applyJiDuan` kernel** (finding 9) — **parked by explicit decision, not
  merely unscheduled.** The kernel is sized `mask_area / 800` with no upper bound, and on a
  large mask it produces a structuring element that stalls the pipeline with no timeout. Task
  1's first pass measured it firing on 3 of the 9 surviving fixtures (scenarios 1, 2, 3), all
  on the unscaled route, because no fixture's endpoints were hand-marked yet. Once the user
  supplied real pixel measurements and those three were re-run with a genuine `cm_per_px`,
  **all three completed cleanly on the scaled route** — no stall. That confirms, on these
  three photos, that a correctly-marked capture avoids the defect; it is not a general proof
  that the scaled route is unconditionally safe (a large enough scaled mask is still an open
  question, just not one any fixture here reaches), so "not reachable from the required
  capture flow" should be read as demonstrated-on-this-corpus, not proven-in-general. Two
  candidate fixes still exist if the general case ever needs closing: cap the structuring
  element at a fixed size, or stop running the cutter when no scale is available, which
  reverses ADR-008's deliberate telemetry choice. The first diverges from the vendor drop in
  `model_and_cutter/`, which the shipped file currently matches byte for byte; the second is
  an architecture decision. Whichever is chosen needs an ADR. Until then this is a known,
  unfixed defect on the unscaled route, and a defect not observed on the scaled route within
  this corpus's range.
- **Re-validating `cm_per_px_target`.** The 0.3289 currently in the manifest was settled by
  the `docs/test-plan.md` sweep, two of whose five images were below the ~73 kg floor. That
  is a real question about that constant, but it belongs to the weight branch, not here.

## Plan rating: 7/10

Revised up from 6 after phases 4-6 were rewritten against
`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` (finding 8). The plan is now anchored to the
document that actually originates the 21 tests instead of inferring their intent, which is
the single largest correctness improvement available to it. It does not go higher because
that same anchoring exposed how much of §14 the shipped pipeline cannot satisfy today.

**Pros.** Every phase now traces to a named requirement rather than to a test title inherited
from an older design, and where requirement and pipeline disagree the plan says which it is
asserting and why. Phase 1 is done and the DLL loads, retiring the highest-risk step. The
two-tier scenario design keeps the suite meaningful without a C++ toolchain instead of letting
it decay back into skips. It catches five real drifts before they are baked into fresh tests:
the `baseline5` feature list, the tolerance disagreement, the dead reason vocabulary, the two
disabled quality gates, and now the `baseline5` check 9 hiding inside
`WeightEligibilityChecker`. §14's segmentation-parity item and §16's traceability item, both
previously unowned, now have homes. Phase 3.1 sources every fixture from real handheld
captures, so the corpus finally matches the capture mode §14's functional bullets describe.

**Cons.** Finding 9 trades coverage for scope: the two no-reference scenarios are removed
because the capture flow no longer produces them, but the code path behind them survives and
now has no test at all, and the stall that lives on it is parked unfixed by explicit decision.
That is a deliberate trade, recorded rather than hidden, but it is still a real hole. Folding
the removals into phase 4 rather than spinning separate subphases keeps the work in one place
at the cost of making an already-large phase larger — six tasks now, one of which touches
`lib/` and breaks the plan's otherwise-clean "no production code" boundary. The requirements
audit surfaced three further gaps this plan deliberately does not close —
§6's absent thresholds, §7's ungated checks, §9's enabled-but-incompatible weight capability —
so several tests will pin behaviour that is known not to meet the spec. That is the honest
choice, but it means a green suite at the end of phase 6 is not a release gate. Phase 4 has
grown to four tasks and is now the largest phase by some margin. The biggest structural risk
is unresolved until task 1 runs: if the cutter still declines on every handheld capture, the
new corpus cannot reach the feature or weight branch at all and phase 5 has to pull PIGRGB
back for parity. Four of the 21 remain device or manual work, so "21 tests un-skipped in
`flutter test`" was never achievable and still is not. The weight tier sits on a temporary,
admittedly-untrustworthy regressor, so its green is narrow, and host-versus-device numeric
divergence is a limit parity cannot close.
