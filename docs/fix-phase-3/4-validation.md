# Phase 4 — Validation: jitter, parity, and the on-device rebuild

Status: deferred 2026-09-18, no longer gated

Deferred, not abandoned. The off-device jitter measurement was taken in phase 3; what remains is
the on-device F53 re-mark and the full per-image table. [`../fix-4.md`](../fix-4.md) phase 2 has
since rejected its normalize-first composition path on host measurement
([`../fix-phase-4-2-results.md`](../fix-phase-4-2-results.md)) without changing what ships, so
the reason this phase deferred -- risk of spending device measurements on a path that might not
survive that gate -- no longer applies. This phase is still deferred because it was left that
way, not because anything still blocks it; resume it on its own terms.

## Symptom

Round 6 phase 2.1 shipped a fix candidate on a plausible mechanism and it measured worse, not
better. That outcome was only visible because the change was measured before and after on the
same corpus. This phase exists so this round cannot repeat that mistake, and so that a null or
negative result is reported as such rather than explained away.

## Root cause

Not applicable — this phase measures rather than fixes.

## Change made

No production code changes in this phase. If a measurement here fails, the fix goes back to
phase 2 or 3; it is not patched from inside this one.

### 1. Jitter, off-device

Run `jitter_sweep.py` after phases 2 and 3, on:

- `--upscale-long-edge 1280` on `sub_1.78`, against phase 1's
  `out/jitter_sweep_hires1280.json` (worst 14.7%). This is the primary comparison — phase 1
  found it is where the defect shows largest, and it is closest to the live-camera path F53
  measured on device.
- the native `sub_1.78` and `sub_1.88` sweeps against `out/jitter_sweep{,_1.88}.json`
  (11.9% / 6.4%), as a secondary check.
- `--upscale-long-edge 3000` against `out/jitter_sweep_hires3000.json` (10.8%), noting that
  phase 1 showed this corpus carries an upscaling blur confounder — do not treat a change
  here as decisive on its own.

Report worst-case spread and the per-image direction of change, in a table, the way
`docs/fix-phase-2/2.1-reference-length-sensitivity.md`'s "Rejected fix" section does. A mixed
result — some images better, some worse — is the outcome that killed the previous candidate,
so report the distribution and not only the worst case.

### 2. Parity

Gate B's IoU check against `ML/pipeline/construction.py` must still pass at ≥ 0.95. Phase 3
does not touch `construct_pig_mask`, so this is a regression check on that claim rather than a
new measurement.

### 3. Dart and native test suites

- `dart format` on any changed Dart files. None are expected this round.
- `flutter analyze`.
- Full native test suite, since this is a cross-cutting change to a shared stage.
- Full `flutter test`. Last known-good is 93 passed / 21 pre-existing skips; report against
  that, and treat any new skip as a failure to explain rather than absorb.

### 4. On device

Only after the above pass. The user builds and sideloads the APK onto their own phone; there
is no attached device in the development environment. Re-run F53's real-pixel re-marking
procedure on the three `.pig_pictures/` field photos — the same procedure that produced the
5.18% / 12.04% / 12.55% bands — and compare against those numbers directly.

This is the measurement that matters, because it is the only one taken on the geometry and the
input path the user actually has. The off-device sweeps are a proxy for it.

## Verification

The round is verified when all of the following hold, and each is reported with the command
output that produced it:

- Worst-case spread on the 1280 corpus is lower than phase 1's 14.7% before-baseline.
- Worst-case spread on the two native PIGRGB baselines is not worse than 11.9% (1.78 m) and
  6.4% (1.88 m).
- Gate-B IoU parity still ≥ 0.95.
- `flutter analyze` clean; test suite at or above 93 passed / 21 skips.
- On-device re-marking bands on the three field photos are lower than 5.18% / 12.04% /
  12.55%.

## If it does not improve

Report the numbers and stop. Do not tune the interpolation choice, the threshold, or `k` to
chase a better sweep — that is fitting the instrument. A null result means F55 is not the
dominant term, which is a real finding and is worth more than a marginal number: it would
promote the polygon hypothesis in `docs/fix-3.md`'s Open questions from deferred to next, and
it would sharpen ADR-010's claim that the training-domain floor dominates everything else.

## Exit condition

Every number above recorded in this file with its command, the round's outcome stated plainly
as improved, null, or regressed, and a `docs/changelog.md` line appended. If the round closed
on a divergence from the corrected-pipeline document — F57 — flag that an ADR is owed for it;
writing it belongs to `pipeline-docs`, not here.
