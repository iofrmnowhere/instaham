# Phase 5 — Stage debug outputs and shipped assertions

Status: not started

Parent: [`../fix-4.md`](../fix-4.md). Unblocked 2026-09-19 — phase 2's gate is void. Work this
after phase 4.

## Symptom

Coordinate bugs on the new path are invisible until they show up as a wrong weight. Round 7's
F55 defect survived several rounds for exactly this reason: nothing in the envelope said which
transform had actually been applied.

## Root cause

Not a defect. README §16 and §17 ask for stage dumps and invariant checks; this phase decides
which of them are worth shipping and which belong in the host harness only.

## Change made

**In the envelope, on every run.** These are cheap scalars and they are what a future session
reads instead of the source:

- `resize_factor`, and the normalized width and height;
- `was_rotated_clockwise`;
- the capture orientation and the user's head-direction attestation from phase 6, so a
  head-left mask can be checked against what was declared;
- whether the README §6 halt fired, and at what normalized dimensions;
- `x_offset`, `y_offset`, `rotated_width`, `rotated_height`;
- base mask dimensions and final mask dimensions;
- `k`, which should be 1.0 on the new path — a value away from 1.0 there means the photograph
  was not actually normalized and is a bug signal in itself.

**In the host harness only.** README §16's image dumps — the EXIF-corrected RGB, the normalized
RGB, the rotated RGB, the canvas, the canvas-coordinate mask, the cropped mask, the base mask
and the final mask. These are large and belong in `ML/host_scale_test/`, not on the device.
The single most useful comparison is the normalized RGB against the base mask against the final
mask; all three must align pixel for pixel.

**As shipped checks.** README §17 lists invariants. Ship all of them:

- `reference_px > 0`, `resize_factor > 0`, normalized dimensions positive — keep;
- base mask dimensions equal normalized RGB dimensions, after any inverse rotation — keep, this
  is the check that would have named a rotation bug immediately;
- final mask dimensions equal base mask dimensions, and the final mask's foreground is a subset
  of the base mask's — keep;
- `width <= 960` and `height <= 540` — **ship it.** Phase 1.1 implements README §6's halt, so
  this is the halt's trigger condition and it must be a declared failure carrying both
  dimensions and the bound. F61 predicts it fires on full-resolution captures; that is the
  specified behaviour this round ships, and the envelope must make every occurrence countable.

Every one of these failing must produce a declared failure with a reason, never a silent extra
resize.

## Verification

- A unit test per shipped invariant, including a negative case that proves the check fires.
- One end-to-end host run whose envelope is read back and checked field by field against the
  values the harness computed independently.
- The three-image visual comparison is produced for at least one corpus A photograph and one
  corpus B image, and stored with the phase 2 results.

## Deferred

Nothing, but this phase no longer closes the round — phase 6 does. The §16 image dumps stay
host-only; §16 is titled "recommended during integration" and is the one README section that
reads as guidance rather than contract, so keeping large per-stage PNGs off the device is a
scoping choice, not a withdrawn divergence. If a device-side coordinate bug ever outlives the
scalar fields above, revisit it.
