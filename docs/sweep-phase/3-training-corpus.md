# Phase 3 — wire corpus B and the k = 1.0 arm

Status: done

## Goal

Point the drivers at `Instaham/PIGRGB-Weight/sub_1.88/` instead of the retired `sub_1.78/`, and
set up the `k = 1.0` self-consistency arm that is this plan's highest-value single result.

## The retirement

`ML/host_scale_test/run_sweep.py` defines `IMAGES_DIR`, and `sweep_constants.py` imports it along
with `cm_per_px_actual`, `parse_true_kg` and `run_cli`. Both currently point at `sub_1.78`, and
`sweep_constants.py`'s own docstring names it.

- [x] Repoint `IMAGES_DIR` at `Instaham/PIGRGB-Weight/sub_1.88/`.
- [x] Update `sweep_constants.py`'s docstring, which currently says "five PIGRGB sub_1.78 images".
- [x] Leave `parse_true_kg` alone — the sub_1.88 filenames use the same `<kg>kg_<n>.png`
      convention (`74.4kg_9.png`, `87.3kg_2.png`, `92.2kg_1.png`, `97.7kg_10.png`,
      `105.98kg_67.png`); confirmed unchanged (all five files present, parses to the true_kg
      values above).

## The `cm_per_px_actual` simplification

This is the reason the corpus swap is worth doing at all, and it should be visible in the code
rather than buried in a comment.

The old `sub_1.78` path computed `cm_per_px_actual = 0.3114504` by rescaling the 304 px/m
baseline from 1.88 m to 1.78 m: `304 × 1.88 / 1.78 = 321.0787 px/m`. That rescaling is an extra
assumption on top of a baseline `docs/INSTAHAM_CAMERA_SCALE_NORMALIZATION.md` section 24 already
describes as theoretical.

At 1.88 m there is no rescaling. `cm_per_px_actual = 100 / 304 = 0.3289473684210526`, directly.

- [x] Replace the rescaling computation with the direct value, and leave the derivation in a
      comment so the next reader does not reintroduce the 1.78 m factor. **Deviation from plan:**
      `cm_per_px_actual` is written as the literal `0.3289473684210526`, not a live `100.0 /
      304.0` division, with an `assert` pinning the ULP gap between the two — see "Known hazards"
      below for why.
- [x] Assert all five images are 960 × 540 before running; the value above is only correct at the
      resolution the baseline was quoted for. Confirmed: all five are exactly 960×540.

## The k = 1.0 arm

With corpus B's `cm_per_px_actual = 0.3289473684210526` and `cm_per_px_target` set to the same
value, `k = cm_per_px_actual / cm_per_px_target` is exactly 1.0 and
`scale_mask_to_training_space` passes the mask through unresampled.

That makes this arm a falsification test, not a score. Everything upstream and downstream of the
scale step still runs — segmentation, the cutter, Chen16 extraction, the regressor — but the
scale step itself contributes nothing. Whatever error remains belongs to those other stages or to
the geometric theory that produced 304 px/m, and cannot be blamed on the constant.

- [x] Use the full-precision `0.3289473684210526`, not the truncated `0.3289` the old
      `sweep_constants.py` `TARGETS` list carries. At 0.3289 the ratio is 0.99984, not 1.0, and
      the arm stops being exact.
- [x] Assert `k == 1.0` in the driver and fail loudly if it does not. Two float-precision bugs
      surfaced and were fixed while making this assertion actually pass — see "Known hazards".
- [x] Confirm from the envelope that the resample was genuinely a no-op — `construction`'s mask
      area should be unchanged across the resample step, not merely close. Confirmed:
      `mask_area_px` is in `INVARIANT_FIELDS` and the cross-arm invariance check (exact equality,
      not tolerance) passed on all five images.

## Verification

- [x] All five corpus B images run to a prediction at both constants. Ten rows written to
      `ML/host_scale_test/out/results.csv`.
- [x] `cutter.status: cut_applied` on all ten runs. Confirmed in the console log for every row.
- [x] `seg_conf`, mask dimensions and `construction.mask_area_px` are identical per image across
      the two arms. `Cross-arm invariance: OK (5 images, ...)` — exact equality, not tolerance.
- [x] `k == 1.0` exactly in the derived arm. Confirmed for all five images (`k=1.0` in
      `results.csv`); the driver now hard-fails if this is not exact.
- [x] Re-running is byte-identical. Confirmed: a second full run's `results.csv` diffed clean
      against the first.
- [x] `0.3289 arm matches unpatched committed manifest` check (pre-existing, not in this phase's
      original scope but exercised by this run): OK — `assets/ml/manifest.json`'s committed
      `cm_per_px_target` (`0.3289473684210526`, ADR-011) is confirmed bit-identical to this
      phase's derived-arm target.

## Known hazards

- **Two float-precision bugs had to be fixed to make `k == 1.0` land exactly, both worth
  understanding before touching this driver again.**
  1. `run_cli` passed `cm_per_px_actual` to the CLI as a subprocess argument formatted with
     `"%.10f" %`, which truncates a double to 10 decimal places. `0.3289473684210526` has 16
     significant digits, so the CLI received a rounded-off value and computed `k =
     0.9999999999360001`, not `1.0`. Fixed by passing `repr(cm_per_px_actual)` instead, which
     round-trips the double exactly.
  2. Even after that fix, `k` still landed at `1.0000000000000002`: the Python literal
     `0.3289473684210526` (used for the derived arm's `cm_per_px_target`) and the live
     expression `100.0 / 304.0` (used for `cm_per_px_actual`) round to **adjacent doubles** —
     `0x1.50d79435e50d7p-2` vs `0x1.50d79435e50d8p-2`, a 1-ULP gap. Fixed by making
     `cm_per_px_actual` itself the literal `0.3289473684210526` (with an `assert` recording that
     `100.0 / 304.0` differs from it by 1 ULP, so a future reader does not "simplify" it back to
     a live division) and setting the derived arm's target to the same `cm_per_px_actual`
     variable rather than re-typing the literal a second time. This also makes the value
     bit-identical to `assets/ml/manifest.json`'s committed `cm_per_px_target`, which is what the
     pre-existing "0.3289 arm matches unpatched committed manifest" check depends on.
- **`74.4kg_9.png` sits on the regressor floor.** [ADR-010](../adr/010-regressor-training-domain-floor.md)
  puts it near 73–74 kg. Expect this row to barely respond to the constant, exactly as the
  retired sweep's 60.27 kg and 66.24 kg rows did. Run it, report it, exclude it from aggregates,
  and use phase 1's new `extrapolated_features` field to say *why* it is excluded rather than
  asserting it. **Observed, and it did not barely respond:** 74.07 kg (−0.44%) at 0.35 vs
  80.24 kg (+7.85%) at the derived constant — an 8-point swing, not a flat line. The envelope
  confirms why the expectation from the retired sweep does not transfer: at 0.35,
  `extrapolated: false`; at the derived constant, `extrapolated: true` with `shortest` in
  `extrapolated_features`. The 0.35 arm's prediction is in-domain and the derived arm's is
  extrapolated past the regressor's training floor, so this row is not "barely responding to the
  constant" — it is crossing the floor boundary between the two arms. Phase 5 should present it
  as excluded-from-aggregates for that reason, not as evidence either constant is closer to the
  truth.
- Corpus B is drawn from the regressor's own training distribution. Good agreement here is partly
  memorisation and does not predict field accuracy. This limits what the arm can prove in the
  positive direction; it does not limit what it can falsify, which is the point of running it.
- The remaining four rows span 87.3–105.98 kg. That is a narrower range than the retired sweep's
  60–133 kg, so this corpus is worse at exposing a scale-dependent bias and better at isolating
  one. Say so in phase 5 rather than presenting the narrower range as an improvement.
