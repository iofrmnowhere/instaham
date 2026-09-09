# Cutter — V176 shoulder selector + V144 circle cut

Stage 3 of the `dorsal_valid` route (`src/stages/cutter.cpp`), between mask construction
([segmentation.md](segmentation.md)) and feature calculation ([prediction.md](prediction.md)).
Removes the head and neck from a constructed mask, because the weight regressor's features
were measured on head-removed masks and a weight taken from an uncut mask overestimates.

## What runs

`cut_body_mask()` is a thin adapter — it wraps the incoming `std::vector<uint8_t>` mask in a
`cv::Mat` and drives the ported vendor stack in `src/vendor/instaham_v176/`, in this order:

```
Ji/Duan cleanup → outline build → shrinking-ball medial candidates → Selle filter
  → terminal trunk geometry → break1 fit → V176 shoulder selection → V144 circle cut
```

The app's side of the seam is unchanged: `MaskView` in, `CutterResult` out, `cv::Mat` never
crosses into `pipeline.cpp`. The vendor sources compile unmodified apart from one logged edit
(see `src/vendor/instaham_v176/VENDOR.md`, which also carries a per-file sha256 of the drop).

## Status values

`status` names the stage that declined, so a rejected photo is attributable to a step rather
than to "the cutter" as a whole — the weight branch needs that to tell a user what went wrong,
and cut-parity work needs it to localise a failure.

| `status` | Meaning |
|---|---|
| `cut_applied` | The V144 circle cut ran; `mask` is the final cut body mask |
| `cut_not_required` | The V176 selector decided no cut was needed |
| `invalid_input` | Incoming mask was null or empty |
| `jiduan_failed` | Ji/Duan cleanup could not retain a plausible silhouette |
| `jiduan_threw` | `applyJiDuan` raised, rather than declining cleanly — see below |
| `no_terminal_balls` | Outline, shrinking-ball, Selle, or trunk assembly found no usable medial trunk |
| `break1_unfit` | The shoulder-region piecewise fit did not converge |
| `shoulder_undecided` | V176 could not choose a cut point on a valid trunk + fit |
| `circle_cut_failed` | V144 geometry failed on an otherwise valid cut-required decision |

`head_removal_applied` is true **only** for `cut_applied`. Every other status returns the
uncut (Ji/Duan-cleaned) mask, so a caller that ignores `status` still gets a usable mask — but
never one it may publish a weight from. `jiduan_threw` is the one exception to "Ji/Duan-cleaned":
there is no `ji.mask` at that point, so it falls back to the raw input mask.

Every vendor call is inside an exception guard. The outline/shrinking-ball/Selle/trunk group
shares one, and `applyJiDuan` and the V144 circle cut have their own; a throw becomes a
`status`, never a process abort. `applyJiDuan` was outside any guard until
`docs/fix-2.md` F44 — nothing in the vendor drop documents it as throwing, and nothing
established that it could not, so it was closed on the same footing as the calls around it
rather than on evidence that it had ever fired.

## The input is size-bounded before this stage runs

The vendor passes were written against the 720×720 training frame, and the shrinking-ball and
medial-axis work scales badly with pixel count. `pipeline.cpp` therefore guarantees a bounded
mask on both routes: with a scale, the mask is resampled into training space (~720×720, at
most ~2880×2880 given the 0.25–4.0 height-ratio clamp); without one, `kUnscaledCutterMaxDimPx`
(2880) caps it to the same budget.

Before `docs/fix-2.md` F43 the no-scale route handed over the mask at full capture resolution
— roughly 3000×4000 on a modern phone, about 20× the pixel count the passes were designed for.
That froze the app hard enough for Android to kill it as an ANR, which is what opened that fix
round. The cutter still runs on that route (its telemetry is the point), it just no longer
receives an unbounded mask.

## There is no reference implementation to diff a single cut against

`ML/pipeline/cutter.py` in this repo is **not** a parity oracle for this stage. It declares
`PROTOCOL_VERSION = "ji_duan_residual_06q_v9_headfit_exact_twotangent_v26"` and contains no
V176, V144, ShrinkingBall, SelleFilter, or Break1 machinery — a different algorithm from the
`v176_…_v144_…_v1` protocol every training row was cut with. Diffing the port against it would
compare two protocols rather than measure a port, which is also why the older plan to
"faithfully port the Python cutter" would have produced a faithful port of the wrong cutter.

The vendor C++ is therefore the only implementation of the shipped cut protocol. Correctness
is established instead against the training CSV's own per-row cutter telemetry —
`final_mask_area_px`, `kept_fraction`, `shoulder_selected_x`, `circle_center_x/y`,
`final_circle_radius_px`, `peak_route_type`, `selection_reason`, all populated on all 1821
eval rows. Until that comparison runs, this stage is verified only as far as "it compiles, it
runs, and it returns a smaller mask with a plausible status"
(`src/test/test_cutter_identity.cpp`).

> Continued in [cutter-2.md](cutter-2.md) — the two `computeBodyCurve()` calls, the two
> quality gates and their manifest switches, what the weight branch now trusts, and the
> OpenCV build implications.
