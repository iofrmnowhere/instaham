# Plan (round 3): give the health classifier the pig, not the pen — closed 2026-09-25

## Goal

Implement the `segmentation_masked` (and, as its cheaper sibling, `segmentation_crop`) health
input protocols so the health classifier sees the pig with its background removed, instead of
the whole captured scene. The segmentation mask that makes this possible is already computed
on every dorsal scan and is already handed to `prepare_health_input()` — it is simply ignored.

## Why this is worth doing

The health checkpoint's ten classes (`assets/ml/health/classes.json`) are `Healthy` plus nine
skin and hoof conditions — Erysipelas, Greasy Pig Disease, Dermatitis, Sunburn, Pityriasis
Rosea, Ringworm, Mange, Foot-and-Mouth, Swinepox. The training corpus behind them
(Roboflow-sourced; see the `.rf.` filenames in `ML/health_cnn/test_predictions.csv`) is made of
condition photographs — close views of affected skin, feet and ears — not standardised
full-pen scenes of a whole animal.

The app's capture is the opposite: a whole scene, photographed from far enough away to fit the
pig and the reference object, with the pig occupying a modest part of the frame. Today that
frame goes to the model untouched apart from a resize-shorter-side-to-255 and a 224 centre
crop (`packages/instaham_ml_ffi/src/health_input.cpp:73`). On a typical capture that crop is
substantially floor, pen rail and shadow.

So the domain gap runs the other way from how it was previously described in this repo:
cropping and masking to the pig moves the app's input **towards** the training images, not away
from them. It also removes pixels that have no business influencing a skin-condition decision.
This is consistent with — though it does not by itself explain — the `P(disease) = 0.937` on a
visibly healthy pig recorded in `packages/instaham_ml_ffi/src/health_input.h`.

None of this is a promise that the numbers improve. Phase 3 exists precisely because that has
to be measured rather than assumed.

## The one piece of real work: recovering original-image coordinates

`prepare_health_input()` receives two things that are **not in the same coordinate space**, and
this is the crux of the whole port:

| Input | Space |
|---|---|
| `src` (the photo) | the captured image, as `decode_image_rgb(image_path)` returns it (`classifier.cpp:45`) |
| `region.mask` / `region.x0..y1` | BASE_MASK space — the *normalized* image: the capture uniformly resized by `resize_factor`, with README section 4's rotation already undone |

The mask is therefore a uniformly scaled copy of the capture, never a crop or a letterbox of
it, because `segmentation.cpp:108` builds the normalized image with a single
`resize_uniform(img, comp.resize_factor)` and `rotate_pig_mask_90_ccw()` has already removed the
rotation by the time `pipeline.cpp:503-510` fills the region. Aspect ratio is preserved exactly.

That makes the recovery a single uniform factor rather than an affine with offsets:

```
original_x = mask_x / resize_factor          resize_factor == SegmentationOutput::content_scale
original_y = mask_y / resize_factor                        (stages/segmentation.h:63)
```

Both the bounding box and the mask bitmap have to be carried across — the box by arithmetic,
the bitmap by a nearest-neighbour resample to the capture's own dimensions, which stays binary.
Any implementation that masks with un-recovered coordinates will silently blank out the wrong
part of the photo, so phase 1 treats this as the thing under test, not as a detail.

AGENTS.md rule 9 applies directly here, and rule 6's prohibition on resizing after the user
marks reference endpoints is not violated: nothing in this plan touches the weight branch's
image or the reference geometry. The health crop is a separate, read-only consumer of the mask.

## Design decisions taken up front

- **Port the Python reference, do not invent.** `ML/parity/reference_health_input.py` already
  implements both protocols completely (`segmentation_crop`, `segmentation_masked`,
  `_crop_to_bbox`, `_imagenet_mean_rgb_uint8`). The C++ is a line-for-line port measured
  against it, exactly as `chen16_feature_gate_cli` is measured against its own reference.
- **`abnormality_crop` stays a stub.** Its proposer was measured selecting background and ear
  rather than lesions (`health_input.h`). Nothing in this plan revives it; it keeps degrading
  to full frame and keeps saying so.
- **The manifest still decides.** `protocol` stays `full_frame` until phase 3's measurement
  says otherwise. Shipping the code and flipping the default are deliberately separate phases.
- **Truthful reporting is preserved, not weakened.** `protocol_applied`, `degraded` and
  `region_source` must keep reporting what actually ran. A capture with no mask (the
  `health_only` route, or a failed segmentation) still falls back to full frame and still says
  so — AGENTS.md rule 4: a health-input problem must never block the health branch.

## Phases

| # | Name | Status | File |
|---|---|---|---|
| 1 | Coordinate recovery and the masked crop | done | docs/plan-phase-3/1-coordinate-recovery-and-masked-crop.md |
| 2 | Parity gate and native tests | done | docs/plan-phase-3/2-parity-gate-and-tests.md |
| 2.1 | Move coordinate recovery into a testable helper | done | docs/plan-phase-3/2.1-recovery-helper.md |
| 3 | Measure the three protocols on real captures | done | docs/plan-phase-3/3-measurement.md |
| 4 | Flip the default, fixtures and surfacing | not taken (phase 3: do not flip) | docs/plan-phase-3/4-flip-and-surface.md |

Phases run in numerical order. Phase 4 is conditional on phase 3's result and may end up
deliberately not taken.

## Relationship to the other open documents

This is the **fourth** plan/fix document open at once, which is more than this project's
conventions want:

- `docs/plan-2.md` — round 2, phase 3 open (device check only).
- `docs/fix-5.md` (round 9) and `docs/fix-4.md` (round 8) — both still carry outstanding debts.
- `docs/plan.md` — Chen16 regressor swap, phase 5 outstanding.

Round 3 is independent of all four: it touches only `health_input.{h,cpp}`, its call sites, and
the health branch's tests. It shares no file with the weight branch's open work. It should
still not be started before round 2's device check closes, unless the user chooses otherwise.

## Open questions

1. **Padded bbox versus mask extent.** The reference pads the bbox by `bbox_padding_ratio`
   (0.06) and masks within the padded box, so a ring of mean-fill surrounds the pig. Keeping
   that is the parity-correct choice; whether it is the *best* choice for this checkpoint is a
   phase 3 question, not a phase 1 one.
2. **Whether `segmentation_crop` or `segmentation_masked` wins.** Retaining the immediate
   background may help (context) or hurt (pen texture reading as a skin condition). Phase 3
   measures both rather than guessing.
3. **Whether a masked input needs retraining to be trustworthy.** If phase 3 shows the
   protocols shifting predictions substantially without improving agreement with ground truth,
   the honest conclusion is that the checkpoint needs fine-tuning on masked crops, and phase 4
   is not taken. That is a training job, outside this plan.
4. **The `health_only` route.** `pipeline.cpp:328` deliberately skips segmentation on that
   route because the region protocols were stubs. If a region protocol becomes the default,
   that trade-off is worth revisiting — a health-only capture would then be running full frame
   while a dorsal capture runs masked. Raised here, resolved in phase 4 if at all.

## Plan rating: 7/10

**Pros.** The hard part is already done and sitting unused — the mask is computed, cleaned,
un-rotated and handed to the exact function that ignores it, and the Python reference for both
protocols is written and complete, so phase 1 is a port rather than a design. The coordinate
recovery turns out to be a single uniform factor with no offsets, which is about the best case
this repo's coordinate handling offers. Separating the port (phase 1) from the default flip
(phase 4) means the capability can ship without changing any user's result, and the measurement
in phase 3 is what decides, not an argument. Blast radius is small: `health_input.{h,cpp}`, one
call site, and the health branch's tests. The weight branch, the cutter and the reference
geometry are untouched.

**Cons.** The payoff is genuinely uncertain. This plan can be executed perfectly and still end
at "do not flip", because the checkpoint may need fine-tuning on masked crops to benefit — and
that training job is outside the plan entirely. Phase 3's strength depends on ground-truth
labels that may barely exist, in which case the recommendation rests on a label-change rate and
one healthy-pig data point, which is thin. The parity tolerance in phase 2 is a real risk of
being tuned until it passes rather than justified. Phase 4 disturbs recorded fixtures, which is
the most tedious part and the easiest place to paper over a real change. And this becomes the
fourth plan/fix document open at once, against a project convention that wants one.

**Why not higher.** The uncertainty is in the outcome, not the plan, and no amount of planning
removes it.

**Why not lower.** Every phase has a concrete artefact, a named reference to measure against,
and an explicit condition for not proceeding.
