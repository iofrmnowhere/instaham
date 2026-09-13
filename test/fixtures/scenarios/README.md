# Scenario fixture corpus — provenance

`docs/metrics-phase/3.1-corpus-rebuild.md` (supersedes `docs/metrics-phase/3-fixture-corpus.md`
for corpus selection). All 8 fixtures below are generated, deterministically, by
`generate_fixtures.py` (run from the repo root: `python test/fixtures/scenarios/
generate_fixtures.py`). Re-running it overwrites every image with the exact same bytes — the
script is the source of truth, not the checked-in images. Total corpus: **6.0 MB**, under the
plan's ~15 MB budget. (Note: the generator's own `meta.json` output is a bare stub and does
not carry the hand-recorded `observed_phase4` blocks below — re-running the generator
overwrites images only; restore `meta.json` from git if it gets clobbered.)

**Scenarios 4 and 10 were removed** (`docs/metrics-plan.md` finding 9, phase 4 task 0): the
capture flow now requires a marked reference object, so both no-reference premises are
unreachable. **Scenario 7 was removed** (`docs/metrics-phase/4.1-scenario-7-removal.md`,
2026-09-12): see "Corpus selection" below. Ids keep their original numbering — 1, 2, 3, 5, 6,
8, 9, 11 — so the mapping onto `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14's eleven
functional bullets stays one-to-one; the three gaps in the sequence are deliberate, not
missing files.

Each `<NN>_<slug>/meta.json` declares only the *expected outcome contract* — view label,
whether the weight branch should produce a number, the expected failure reason code, the
reference length in cm — never a predicted weight or confidence (AGENTS.md, "Never display
invented model scores").

## Corpus selection

**3.1 rebuild:** every scenario now sources from the app's own real capture corpus —
`.pig_pictures/` (4 handheld weight photos, real reference objects in frame) and
`health_pigs/` (5 handheld health/side-view photos, no reference object). `Instaham/
PIGRGB-Weight/` (the fixed-camera-rig dataset used by the original phase 3) is **no longer
used by any scenario fixture** — it stays available only for phase 5 parity, where scale
doesn't matter because both implementations run the same image. This closes three round-14
audit findings against `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §14:

1. Scenario 5 (off-dorsal) is now a genuine side-on capture (`IMG_9520.HEIC`), not a dorsal
   PIGRGB stand-in.
2. ~~Scenario 7 (multiple pigs) is now a real two-pig frame (`LDPH5Y0l.jpg`), not a synthetic
   composite of two single-pig photos.~~ **Removed in phase 4.1** (2026-09-12): the real
   two-pig frame was correctly sourced, but the view classifier rejects it outright
   (`view: reject`, 0.9614 confidence) before segmentation or mask selection ever run, so
   the fixture never exercised §14 bullet 7's multi-pig behaviour — it only duplicated
   scenario 5's `view_rejected` assertion, and the `multiple_pigs` reason code it was meant
   to check is dead (finding 5). See `docs/metrics-phase/4.1-scenario-7-removal.md`.
   §14 bullet 7 is now an accepted coverage gap, alongside the two below: covering it
   properly needs a frame with two pigs both in *valid dorsal framing*, which does not exist
   in `.pig_pictures/` or `health_pigs/`.
3. Scenario 3 (custom reference) now derives its length from a real sub-span of a visible
   meter tape (`75kg_pig_meter_stick.HEIC`), not an acquisition-geometry-derived pixel count
   with no object in frame.

Only one synthetic fixture remains: scenario 8's Gaussian blur, because no genuinely blurry
photo exists in either source folder.

## Fixtures

| id | scenario | image | source | kind |
|---|---|---|---|---|
| 01 | Valid dorsal, 100 cm reference | `image.jpg` | `.pig_pictures/92kg_pig_meter_stick.HEIC` | real field capture |
| 02 | Valid dorsal, 131 cm Porac reference | `image.jpg` | `.pig_pictures/96kg_pig_porac_stick.HEIC` | real field capture |
| 03 | Valid dorsal, custom reference | `image.jpg` | `.pig_pictures/75kg_pig_meter_stick.HEIC` | real field capture (real sub-span of the same tape) |
| 05 | Off-dorsal view | `image.jpg` | `health_pigs/IMG_9520.HEIC` | real field capture (closes round-14 gap) |
| 06 | Lesion close-up | `image.jpg` | `health_pigs/owaKvudb.jpg`, cropped | real capture, cropped to a marked-skin region |
| 08 | Blurry | `image.jpg` | `health_pigs/kARi2pdr.jpg`, Gaussian-blurred | synthetic degradation (only remaining synthetic fixture) |
| 09 | Truncated pig | `image.jpg` | `health_pigs/VBYvVvwj.jpg`, cropped | real capture, head/front cropped off |
| 11 | HEIC/JPEG/PNG containers | `image.{heic,jpg,png}` | `.pig_pictures/75kg_pig_meter_stick.HEIC` | real capture, transcoded three ways (same source as 03) |

Every transform (crop box, blur radius, resize target) is recorded in both
`generate_fixtures.py` and the fixture's own `meta.json`. Crop boxes for 06, 09, and 10 were
chosen only after visually inspecting the rendered crop, not guessed from filenames.

## Task 1 results (2026-09-11)

Every fixture's `meta.json` now carries an `observed_phase4` block from a real run against
the Windows host build, `INSTAHAM_NATIVE_TESTS=1`, no `cm_per_px` supplied to any fixture
(endpoints remain unmarked — see below). Two results correct assumptions made earlier in this
README and in `docs/metrics-plan.md`:

- **Scenarios 1, 2, and 3 stall, not just the removed scenario 10.** Each was killed after
  >145s with no envelope ever produced. The cause is the same `applyJiDuan` kernel-sizing
  defect documented in `docs/metrics-plan.md` finding 9 (`mask_area / 800`, no upper bound):
  without a marked reference, these three 1200x1600 fixtures take the unscaled cutter route
  and their masks are large enough to hang `cv::morphologyEx`. **"Carries a marked reference"
  was the wrong test** — what determines the route is whether `cm_per_px` was actually
  supplied, and none of the nine fixtures has hand-marked endpoints, so none of them currently
  produce one.
- **Scenario 11 did not stall and its cutter did not decline.** Same unscaled route, same
  kernel-sizing defect, but its image is a 900x900 thumbnail — small enough that the kernel
  stayed under whatever threshold keeps the morphological open fast. It completed in 21.0s
  with `cutter.status: "cut_applied"`, `kept_fraction: 0.91`. This overturns the round-14
  finding below it used to say (all four `.pig_pictures/` captures failing the cutter): at
  least one handheld capture, on this corpus, reaches and passes the cutter.
- Scenarios 5, 6, 7, 8, 9 all completed in under 110ms each with no stall. Their actual
  outcomes are recorded per-fixture; two disagree with the hypothesis this README stated
  earlier — scenario 5 (off-dorsal) resolved to `reject`, not `health_only`, and scenario 8's
  radius-8 blur did **not** reach `reject` (it resolved to `health_only` at 0.9999998
  confidence) — both were flagged as open hypotheses in the original text and are now closed.
- Scenario 9 never reaches segmentation or the cutter at all (`view: health_only`), so
  finding 6's "truncation gate is off" question does not apply to it as currently framed —
  the fixture would need to reach a dorsal route before the gate is even relevant.

## Task 1 rerun (2026-09-12) — scenarios 1, 2, 3 endpoints marked, stall resolved

The user measured each reference span directly in the app (`image_picker`'s 3000px cap,
height-constrained on these 3024x4032 originals) and supplied the pixel counts. Converting to
this fixture corpus's 1600px cap uses the exact ratio 1600/3000 on this photo geometry (both
caps are constrained by the same axis, so it is not an approximation). Each fixture's
`reference.pixel_endpoints` now records the measured span and derived `cm_per_px`.

Re-running scenarios 1, 2, and 3 with a real `cm_per_px` **resolves the stall**: all three
completed in 8-9s each, all reached and passed the cutter, and all produced a weight number
(98.1 kg / 91.9 kg / 96.9 kg against 92 / 96 / 75 kg recorded — accuracy is not asserted here,
only that the branch does not gate; scenario 3's over-read matches ADR-010's own floor
warning). This confirms — on these three photos — that a correctly-marked capture takes the
scaled cutter route and does not hit the `applyJiDuan` stall the unscaled route hit on the
same images. It is not a general proof that the scaled route is unconditionally safe, only
that it is safe within this corpus's range; see `docs/metrics-plan.md` finding 9 for the full
reasoning and its limits.

Scenario 11's endpoints remain unmarked. Its `expect_number: true` assertion still needs that
done before task 4 can write a real Tier B numeric check for it.

## Task 2 — titles and expected outcomes restated against live vocabulary (2026-09-12)

Every `expected_outcome` that was still a pre-task-1 hypothesis or a dead
`WeightEligibilityChecker` reason code has been rewritten against each fixture's own
`observed_phase4` block. Titles changed where the old wording no longer matched:

- **Scenarios 5 and 7 both resolve at the view stage itself**, not further downstream as
  their old titles implied. Both are rejected outright (`view: reject`, envelope
  `status: stopped`, reason `view_rejected`) before segmentation, the cutter, or health
  classification ever run — off-dorsal framing and a two-pig frame both read as `reject` to
  the view classifier at >0.96 confidence. Titles now say "view rejected (weight and health
  both withheld)"; `health_branch.expect_assessed` is `false` for both, correcting the
  previous (wrong) `true`. There is no live "multiple pigs detected" reason code — the old
  `multiple_pigs` string is dead (finding 5); §7 check 1 is not exercised by this fixture
  because the frame never reaches segmentation.
- **Scenarios 6 and 9 kept their `health_only` hypothesis but had the wrong failure reason.**
  Both listed `weight_needs_reference_object`, a dead `WeightEligibilityChecker` string; the
  live pipeline reason for a non-dorsal view is `view_not_dorsal`. Fixed in both.
- **Scenario 8's hypothesis was wrong and stays wrong on purpose.** Radius-8 Gaussian blur
  does not reach `reject` — it resolves `health_only` at 0.9999998 confidence. User decision
  2026-09-12: assert this honestly rather than regenerating with a stronger blur, since the
  reject state is not being chased here as a goal for this fixture. (Note: `reject` itself is
  real and live — scenarios 5 and 7 both hit it — this decision is specific to scenario 8's
  blur strength, not a claim that the pipeline has no reject state.) Title now reads
  "health_only (radius-8 blur does not trigger reject)".
- **Scenarios 1, 2, 3, and 11 needed no change** — their titles and `expected_outcome`
  already matched §14's bullets and, for 1-3, the task-1-rerun's confirmed numeric outcome.

## Known gaps, carried into phase 4

- **No third reference-object length exists in the corpus** — only the meter tape (100 cm)
  and two Porac sticks (131 cm) are photographed. Scenario 3's "custom" length (50 cm) is a
  real sub-span of the same meter tape rather than a distinct object; it exercises the
  custom-length code path but not a visually distinct third reference object. A photo of any
  other straight object with a known length would close this fully.
- **§14 bullet 7 (multiple-pig image) has no fixture and no test**, accepted in phase 4.1
  (2026-09-12) after scenario 7's removal — see "Corpus selection" above. A real two-pig
  photo exists in `health_pigs/` (`LDPH5Y0l.jpg`), but the view classifier rejects it before
  segmentation runs, so it cannot exercise the mask-selection behaviour the bullet is about.
  Closing this needs a frame with two pigs both in valid dorsal framing.
