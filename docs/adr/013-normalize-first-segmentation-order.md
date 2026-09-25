# ADR-013: Normalize the photograph to physical scale before segmentation, by instruction

Status: Accepted (supersedes ADR-003)

Context: F49
([`fix-phase-2/3-normalization-order.md`](../fix-phase-2/3-normalization-order.md)) asked
whether a capture should be resampled to the weight regressor's training scale
(`cm_per_px_target`) before segmentation, or whether segmentation should keep composing its
own scale-aware canvas per ADR-003 and let a later stage (`transform_mask_to_training_space()`)
reconcile the mask into training space afterward. Round 8 was opened because ADR-003's canvas
still left the segmenter seeing the pig at roughly 0.85-1.85 cm/px while the models behind both
segmentation and weight prediction were trained near 0.33-0.34 cm/px
(`INSTAHAM_CAMERA_SCALE_NORMALIZATION.md:29`) — only the mask was ever normalized, not the
photograph the segmenter actually ran on (F60).

The round's own phase 2 built a measurement gate and used it to close the round with a REJECT
verdict on 2026-09-18: it measured detection rate, MAE and jitter for the normalize-first order
against the shipped ladder order and found corpus B got worse. The user overruled that verdict
on 2026-09-19: `INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md` was designated as
the specification for this round, not a proposal a self-invented gate could discard, and F49 was
reopened.

Decision: Implement the README's order as the app's only segmentation input path. A capture is
uniformly resized to `cm_per_px_target` first, rotated 90° clockwise when that leaves it
portrait (README §4 — no dynamic head-direction inference), centred unresized on a 960x540
canvas, and segmented in a single pass (`decide_normalize_first_composition()`,
`stages/canvas_scale.h`; `run_segmentation()`, `stages/segmentation.cpp`). This removes ADR-003's
`decide_canvas_scale()` composition and its four-rung retry ladder
(`segmentation.input_scale.ladder_multipliers`) outright — README §13 specifies a single pass,
not a ladder — rather than running both paths behind a switch. `pipeline.cpp` calls
`run_segmentation()` once, at `cm_per_px_target`, matching `weight_branch_cli.cpp`.

Consequences: Segmentation now costs exactly one model pass per capture instead of up to eight,
but loses the ladder's ability to retry a hard photo at a different apparent scale. Whether that
costs real detections is untested — the round's only device run (2026-09-21, `recorded.md`)
re-scanned four photos already known to detect via gallery import, not fresh captures, so it
confirms host/device arithmetic parity but not the ladder-removal question. Phase 2's own
measurement is retained as a known and accepted counter-indication: its numbers say corpus B
got worse under this order, and the round ships anyway, by instruction, with that measurement on
the record rather than discarded. README §6's exact-960x540-fit halt ships with no fallback
(ADR-003's `clamped_to_letterbox` behaviour is gone); a capture that does not fit is a declared
failure, never an enlarged canvas or a second attempt at a different scale. ADR-003 is superseded
by this decision; its `decide_canvas_scale()` function and the manifest fields that configured it
(`segmentation.input_scale.cm_per_px`/`ladder_multipliers`/`retry_conf_threshold`) are removed
from `pipeline.cpp`'s call path (see
[`fix-phase-4/1.1-readme-is-the-path.md`](../fix-phase-4/1.1-readme-is-the-path.md) and
[`fix-phase-4/4-app-wiring.md`](../fix-phase-4/4-app-wiring.md)).
