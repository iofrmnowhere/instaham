# Metrics plan phase 3 — fixture corpus

Status: **done**. `flutter test` still reports 93 passed / 22 skipped / 0 failed — this phase
adds no tests, only fixture data; it unblocks phase 4.

## What this phase delivers

`test/fixtures/scenarios/<01..11>_<slug>/` — one real or reproducibly-derived image plus a
`meta.json` outcome contract per scenario, and `test/fixtures/scenarios/README.md`
documenting provenance for all 11. `generate_fixtures.py` is the source of truth; the
checked-in images are its deterministic output.

## Corpus selection — corrected mid-phase

The corpus was originally going to be limited to `Instaham/PIGRGB-Weight/sub_1.78/` alone
(scenarios 1–3), following the plan document's literal wording. The user pushed back twice
during discussion of this phase: first that a corpus restricted to one 100–133 kg folder
does not exercise "how small to how large" the model can handle, then — after `sub_1.88` and
`.pig_pictures` were each raised only to be given an immediate disqualifying caveat while
`sub_1.78` got none — that the caveats themselves were being applied asymmetrically. Both
points changed the corpus:

- **Range.** The corpus now spans `sub_1.88`'s 74.4 kg (scenario 3, deliberately near the
  ~73 kg regressor floor) through `sub_1.78`'s 133.42 kg (scenario 4), instead of sitting
  entirely in the 100–133 kg band.
- **Sources.** All three available sources are used: `sub_1.78`, `sub_1.88`, and the three
  real field captures in `.pig_pictures` (which also supplied the only fixtures with an
  actual physical reference object visible in frame — scenarios 1, 2, 10, 11).
- **Masks.** `MASK_3394` is not used. Phase 5 parity compares native-vs-Python output on the
  same image, so both sides run the same segmentation; nothing in this plan measures
  segmentation accuracy against ground truth, so a mask has no role here.

## Per-scenario sourcing

| id | image | source | kind |
|---|---|---|---|
| 01 | 100 cm reference | `.pig_pictures/92kg_pig_meter_stick.HEIC` | real field capture |
| 02 | 131 cm Porac reference | `.pig_pictures/96kg_pig_porac_stick.HEIC` | real field capture |
| 03 | custom reference (74.4 kg, low end) | `sub_1.88/74.4kg_9.png` | real, fixed-geometry |
| 04 | no reference (133.42 kg, high end) | `sub_1.78/133.42kg_5.png` | real, fixed-geometry |
| 05 | off-dorsal view | `sub_1.88/92.2kg_1.png` | **placeholder — see gap** |
| 06 | lesion close-up | `.pig_pictures/118kg_pig_porac_stick.jpg`, cropped | real capture, cropped to a real marked-skin region |
| 07 | multiple pigs | two real photos composited | synthetic composite |
| 08 | blurry | `sub_1.78/125.38kg_4.png`, Gaussian-blurred | synthetic degradation |
| 09 | truncated pig | `sub_1.88/105.98kg_67.png`, cropped | real capture, cropped |
| 10 | hidden reference | `.pig_pictures/96kg_pig_porac_stick.HEIC`, cropped | real capture, reference cropped out |
| 11 | HEIC/JPEG/PNG | `.pig_pictures/118kg_pig_porac_stick.jpg`, transcoded 3 ways | real capture, transcoded |

Crop boxes for scenarios 6 and 10 were chosen only after visually inspecting the source
photos (the real skin marks used for scenario 6, and the real Porac stick's position used
for scenario 10) — not guessed from filenames. All crop boxes, the blur radius, and the
composite layout are recorded as constants in `generate_fixtures.py`.

## Corpus size

8.8 MB total, under the plan's ~15 MB budget. (First pass came in at 12.8 MB with scenario
11's containers at 1600px; reduced to 900px, which shrank the lossless PNG leg from 3.97 MB
to 1.27 MB without changing what the fixture tests — cross-container decode agreement, not
resolution.)

## Verification

```
python test/fixtures/scenarios/generate_fixtures.py     # regenerates all 13 files deterministically
# -> Generated 13 files across 11 scenarios, 8.63 MB total.
```

- Every `meta.json` parses as valid JSON (checked with a small Python pass).
- Scenario 11's three containers decode to the same 675x900 RGB content via Pillow +
  pillow-heif.
- Scenarios 6, 7, 9, and 10's generated images were read back and visually confirmed: the
  lesion crop (06) contains the real red skin marks; the composite (07) shows two distinct
  pigs; the truncation crop (09) visibly cuts the pig's head off at the frame edge; the
  hidden-reference crop (10) fully removes the Porac stick.
- `flutter test --reporter=compact`: 93 passed, 22 skipped, 0 failed (unchanged from phase
  2 — this phase adds no Dart tests, only fixture data).

## Known gaps carried into phase 4

Recorded in full in `test/fixtures/scenarios/README.md`, "Known gaps" section:

1. Scenario 5 has no genuine off-dorsal photo anywhere in the repo's corpus — its fixture is
   an explicitly flagged dorsal stand-in (`"image_is_placeholder": true`).
2. Reference pixel endpoints are not hand-marked for scenarios 1, 2, 10, 11 (the ones with a
   real visible reference object) — each `meta.json` records the physical length and a note
   to mark endpoints before a phase 4 Tier B numeric assertion.
3. Scenarios 5, 6, 7, 8's expected view/reason are hypotheses pending a real run through the
   phase 2 harness — scenario 7 most of all, since finding 5 already established that the
   old `multiple_pigs` reason is dead and the live behaviour on a two-pig frame is unknown.
4. Scenario 9's truncation gate is off in the shipped manifest (finding 6); phase 4 must run
   it against both the default manifest and a gate-enabled test copy.

## Not done here (deferred to phase 4)

- No test file consumes these fixtures yet — `test/scenarios/functional_scenarios_test.dart`
  is still 11 empty `skip:` bodies.
- The scenario titles still name the dead reason vocabulary (`multiple_pigs`, `pig_truncated`,
  `endpoints_too_close`); phase 4's own first task is rewriting them against the live table.
