# Phase 1 — rebuild the harness and add the missing telemetry

Status: done

## Goal

Get `ML/host_scale_test/build/weight_branch_cli.exe` onto the current sources, and make it emit
the two envelope fields the app emits but the harness does not, so the next run records domain
excursions live instead of having them reconstructed afterwards.

Nothing in this phase runs a sweep. Its output is a binary and a proof that the binary is
current.

## Why this is first

The binary is dated 2026-09-10 16:57. `pipeline.cpp`, `stages/cutter.cpp` and
`stages/segmentation.cpp` are all dated 2026-09-11 15:45. Any run against the existing binary
measures code that is no longer shipped, and would reproduce exactly the defect that makes
`docs/scale-constant-sweep-results.md` unusable. No later phase may run until this one closes.

## Steps

- [x] Open a shell that has sourced
      `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat`.
      `ML/host_scale_test/README.md` records that the `'vswhere.exe' is not recognized` line this
      prints on this machine is harmless. Confirmed harmless again this round.
- [x] Confirm `ML/host_scale_test/third_party/onnxruntime.lib` is still present. **It was** —
      not regenerated.
- [x] Add `extrapolated` and `extrapolated_features` to `weight_branch_cli.cpp`'s envelope
      output. Added `feature_extrapolated()` and `extrapolated_feature_names()` as verbatim
      copies of `pipeline.cpp`'s (lines ~183 and ~245), called unconditionally after the
      existing (widened) domain gate and before predict — unlike the app, which only surfaces
      this when the widened gate passed and predict succeeded, this CLI always predicts, so it
      always reports it.
- [x] Rebuild with the README's `cmake -G Ninja -S ML/host_scale_test -B ML/host_scale_test/build`
      invocation, passing the vcpkg toolchain file explicitly (`VCPKG_ROOT` is not set on this
      machine). Exit code 0, 9/9 targets.
- [x] Record the new binary's timestamp and confirm it is newer than every file under
      `packages/instaham_ml_ffi/src/`. **`weight_branch_cli.exe`: 2026-09-13 23:08:55.** State
      this in phase 4's results header.

## Verification

- [x] `weight_branch_cli.exe` timestamp is newer than `pipeline.cpp` (2026-09-11 15:45:50),
      `stages/cutter.cpp` (2026-09-11 15:45:40), `stages/segmentation.cpp` (2026-09-11 15:45:40),
      `stages/construction.cpp` (2026-09-10 16:41:43), and every other file it links.
- [x] A single smoke run on one `sub_1.88` image (`105.98kg_67.png`, `cm_per_px_actual =
      0.3289473684210526`) at the shipped manifest emits an envelope containing `extrapolated`
      (`false`) and `extrapolated_features` (`[]`).
- [x] The smoke run reports `cutter_status: cut_applied`.
- [x] Re-running the same image twice produced a byte-identical envelope (`diff` clean).

**Environment note for future rounds:** invoking `cmd.exe /c <path>.bat` from this Bash tool
silently mangles `/c` into `C:/` (MSYS path conversion) and launches an interactive shell
instead of running the script — it just sits there, looking like a slow build rather than a
failure. Prefix with `MSYS_NO_PATHCONV=1` when shelling out to `cmd.exe` from here.

## Known hazards

- **Do not write `assets/ml/manifest.json`.** The existing drivers patch gitignored
  `manifest.test_*.json` copies and delete them afterwards. Preserve that mechanism exactly; the
  committed manifest currently carries hand-edited fields that a careless write would lose.
- The harness reproduces `pipeline.cpp`'s weight branch rather than calling it, and
  `weight_branch_cli.cpp`'s own header lists deliberate deviations from the app. Adding the
  extrapolation fields must not quietly close or widen any of those deviations — if one has to
  change, record it, because it changes what phase 4's numbers mean.
- `weight_branch_cli.cpp` duplicating `pipeline.cpp`'s weight branch with nothing enforcing sync
  is a standing carried finding. This phase does not fix that. It does make the duplication one
  day fresher, which is the most that is in scope here.
