# Phase 1 — The freeze: an unscaled full-resolution mask reaches the cutter

Status: closed — F42, F43, F44, F45, F52 all fixed and verified on device (F44 host-verified only)

## Symptom

Pressing **Confirm analysis** after marking the reference endpoints hangs the app for longer
than a normal scan, then kills it. First seen on the first APK built after `docs/plan.md`
phases 1–4. This is the first build in which the cutter does real work — before phase 2 of
that plan it was an identity stub that returned immediately — so the stage has no prior
field history.

## Root cause

### F42 — `weight.available` is false in the working-tree manifest

`assets/ml/manifest.json:171` reads `"available": false` inside `capabilities.weight`. The
committed manifest at `HEAD` (commit `e13b1f4`) reads `true`.

`ML/export/export_xgboost.py:234` writes `{"available": bool(enable_for_testing)}`, and the
`--enable-for-testing` flag is documented at line 327 as "DEV ONLY: flips weight.available to
true for on-device verification". A manifest regeneration without that flag therefore turns
the weight branch off, silently, as a side effect of re-exporting.

### F43 — a false flag skips the scale, and the cutter is not guarded by the scale

This is the part that turns a disabled feature into a hang. Three facts compose:

1. `pipeline.cpp:479` checks `manifest.weight.available` *before* deriving `k`. A false flag
   sets `scale_failure_reason = "weight_capability_unavailable"` and leaves `scale_ok` false.
   The user's confirmed reference object is measured and persisted, then never applied.
2. The cutter block at `pipeline.cpp:540` is guarded by `is_dorsal && have_mask` only. Neither
   `scale_ok` nor `weight_override` gates it — they only change what the envelope reports.
3. With `scale_ok` false, `mask_for_cutter` stays pointed at the unscaled `pig_mask`
   (`pipeline.cpp:655`). The comment there states the intent: a fallback "to keep provisional
   debugging features visible when no reference was marked." That intent is reasonable for an
   identity-stub cutter and dangerous for a real one.

`construct_pig_mask` unletterboxes to `seg.orig_w × seg.orig_h` (`construction.cpp:99`), so
the mask is at full capture resolution — a comment at `pipeline.cpp:566` cites a real
2250×3000 frame, and a modern phone camera reaches 3000×4000. The V176 shrinking-ball,
Selle-filter and terminal-trunk passes were written against the 720×720 training frame.

For contrast, the scaled path is bounded: `height_ratio` is clamped to 0.25–4.0
(`pipeline.cpp:47`), and because the resized mask's geometric mean is `height_ratio ×
training_scale`, it cannot exceed about 2880×2880 and normally lands near 720×720. Only the
unscaled fallback is unbounded.

### F44 — `applyJiDuan` is outside the cutter's exception guard

`cutter.cpp:60` calls `instaham::applyJiDuan(whole)` before the `try` block that opens at line
69. The three vendor calls inside that block are documented as throwing `std::runtime_error`
on degenerate geometry; nothing establishes that `applyJiDuan` cannot. If it throws, the
exception is unhandled and the process aborts. Independent of F42, and worth closing whatever
the logcat says.

### F52 — a non-release `pub get` rewrites the plugin registrant, breaking the release build

Found when the first `flutter build apk` after F43/F44 failed. Not caused by either fix, and
not caused by the manifest work — no Dart, Gradle or plugin source was touched by any of it.
Recorded here rather than as its own phase because it blocks phase 1's remaining on-device
verification.

`docs/logs/build_log.md`:

```text
GeneratedPluginRegistrant.java:34: error: package dev.flutter.plugins.integration_test does not exist
```

The declaration side is correct and needs no change. `pubspec.yaml:54` has `integration_test`
under `dev_dependencies`, and `.flutter-plugins-dependencies` marks it `"dev_dependency":
true`. The Flutter tool does filter those out of the Android registrant —
`flutter_plugins.dart:1316`, `if (releaseMode) { filteredPlugins = plugins.where((p) =>
!p.isDevDependency) }` — and `flutter build apk` passes the real build mode into it twice, at
`flutter_command.dart:1968` and `android/gradle.dart:207`.

The problem is that **`flutter pub get` hardcodes the opposite**. `commands/packages.dart:391`
declares `const ignoreReleaseModeSinceItsNotABuildAndHopeItWorks = false` and passes it as
`releaseMode`, so every `pub get` regenerates `GeneratedPluginRegistrant.java` *including*
dev-only plugins. The tool's own source cites the upstream issue for this,
flutter/flutter#162649.

The file timestamps place a `pub get` inside the failed build's window: the registrant was
written at `21:42:16.433`, then `pubspec.lock` and `.dart_tool/package_config.json` at
`21:42:17.040` / `.042`, and the build itself ran for 2m06s ending in that minute. So a
non-release generation was the last writer before Gradle's `compileReleaseJavaWithJavac`, and
javac compiled a registrant referencing a plugin that is not on the release classpath.

`.flutter-plugins-dependencies` keeping its 2026-08-29 mtime is not evidence against this —
`refreshPluginsList` only rewrites that file when the resolved plugin set actually changes, and
it did not.

### F45 — the pipeline runs on the Dart main isolate

`grep` for `Isolate.run`, `Isolate.spawn` and `compute(` across `lib/` returns nothing. The
FFI call is synchronous on the UI thread, so any slow native stage freezes the interface and
Android may kill the activity as an ANR. This is why a slow cutter presents as a crash rather
than as a long spinner.

## Change made

Three, in the order the steps below required — the logcat was captured before anything was
edited, so the diagnosis is attributed rather than assumed.

- **`assets/ml/manifest.json`** — `capabilities.weight.available` back to `true`, produced by
  re-running the exporter with `--enable-for-testing` rather than by hand (F42). That rebuild
  also dropped the segmentation scale ladder; see
  [1.1-manifest-input-scale-regression.md](1.1-manifest-input-scale-regression.md).
- **`packages/instaham_ml_ffi/src/pipeline.cpp`** — new `kUnscaledCutterMaxDimPx = 2880`, and
  the unscaled fallback mask is now resampled down to that bound before reaching the cutter
  (F43). `scale_ok` and everything gated on it are untouched; only which mask the cutter
  receives changed.
- **`packages/instaham_ml_ffi/src/stages/cutter.cpp`** — `applyJiDuan` moved inside its own
  `try`/`catch`, declining as `jiduan_threw` instead of aborting the process (F44).

F52 needed no source change; the build failure cleared on a rebuild.

## Steps

- [x] **F42 — capture the logcat first.** `adb logcat -c`, reproduce, `adb logcat -d >
      crash.txt`. `ANR in ... / Input dispatching timed out` means the freeze is F43 plus F45.
      `Fatal signal 11 (SIGSEGV)` or `terminating with uncaught exception` means a native
      fault, most likely F44. Do this before changing anything — it is the only cheap chance
      to tell the two apart.

      **Result: ANR, not a native fault.** `crash.txt` shows
      `ActivityManager: ANR in com.instaham.instaham (com.instaham.instaham/.MainActivity)` /
      `Reason: Input dispatching timed out ... Waited 10000ms for MotionEvent(action=DOWN)`,
      `Completed ANR of com.instaham.instaham in 15621ms`. No `Fatal signal`, `SIGSEGV`, or
      uncaught-exception line is attributed to the app's own PID; the `tombstoned` lines in the
      capture belong to other processes (`system_server`, a keyboard app, `com.miui.face`) and
      are unrelated background noise. This confirms F43+F45 as the cause and clears F44 of
      responsibility for *this* freeze — F44 is still worth closing on its own merits per the
      step below.
- [x] **F42 — set `capabilities.weight.available` back to `true`**, either by re-exporting
      with `--enable-for-testing` or by editing the manifest directly, and rebuild. Prefer the
      exporter so the manifest stays reproducible. Confirm the freeze is gone.

      **Done via the exporter**, not a hand edit:
      `python -m ML.export.export_xgboost --model ML/weight_prediction_chen16/model.json
      --feature-family chen16_noheight --out assets/ml/weight --enable-for-testing`, then
      `python -m ML.export.build_manifest --view build/ml_export/view --health
      build/ml_export/health --weight build/ml_export/weight --segmentation
      build/ml_export/segmentation --assets assets/ml`. **Freeze confirmed gone on device** —
      the same photo now completes analysis instead of hanging, which closes F42 and confirms
      F43's mechanism (the unscaled full-resolution mask was reaching the cutter only because
      the false flag skipped scale derivation).

      That rebuild also regressed the segmentation capability. See
      [1.1-manifest-input-scale-regression.md](1.1-manifest-input-scale-regression.md), F50.
- [x] **F43 — decide whether the unscaled fallback should reach the cutter at all.** Restoring
      the flag makes the freeze go away without addressing the cause: any future manifest, any
      photo with no reference, and any `scale_out_of_range` rejection still routes a
      full-resolution mask into a stage built for 720×720. Options are to gate the cutter on
      `scale_ok`, or to cap the mask handed to it. The provisional-debugging-features intent in
      the comment at `pipeline.cpp:651` needs to be weighed against it, not ignored.

      **Took the cap option**, not the gate: `pipeline.cpp` gained `kUnscaledCutterMaxDimPx =
      2880` (the same bound the scaled path already guarantees — `training_scale=720 ×
      kMaxValidHeightRatio=4.0`) and, when `scale_ok` is false, the mask handed to the cutter
      is now resampled down to that bound via the existing `scale_mask_to_training_space`
      before `cut_body_mask` runs, instead of being left at full capture resolution. Gating on
      `scale_ok` was rejected: it would delete the provisional-debugging telemetry
      (`envelope["cutter"]`/`envelope["features"]`) for every unscaled photo, which the
      comment at `pipeline.cpp:651` documents as deliberate, and F43 only needed the pixel
      count bounded, not the feature removed. `scale_ok` itself, and everything gated on it
      (`measured_on`, `weight_unavailable_json`), is untouched — only which mask reaches the
      cutter changed. **Not yet verified on device**: the doc's own verification step (a scan
      with no reference marked, and one that fails `scale_out_of_range`, both completing
      without freezing) still needs a phone.
- [x] **F44 — move `applyJiDuan` inside the try block** in `cutter.cpp`, with its own
      `decline(whole, "jiduan_threw")` status so a throw is distinguishable from the existing
      `ji.fallback` path.

      Done: `applyJiDuan` now runs inside its own `try`/`catch`, returning
      `decline(whole, "jiduan_threw")` on a throw (the raw input mask, since `ji.mask` does
      not exist yet at that point). Verified with the host build: `test_cutter_identity`
      compiles clean under `vcvars64` + ninja and passes (exit 0) — this only exercises the
      non-throwing path since nothing in the test corpus makes `applyJiDuan` throw, so it
      confirms no regression, not that the new catch branch is reachable in practice.
- [x] **F52 — re-run `flutter build apk`.** With `pubspec.lock` and
      `.dart_tool/package_config.json` now current, the build should not trigger another
      `pub get`, leaving the release-mode regeneration as the last writer of the registrant.
      This is the whole fix if the diagnosis holds, and it costs one build to test.

      **Confirmed: the rebuild succeeded with no source change**, which is what the diagnosis
      predicted and is itself the evidence for it — a genuine dependency or configuration
      fault would not clear on a second identical invocation. The two steps below stay open as
      standing guidance rather than pending work, since the race can recur any time a `pub
      get` lands inside a build window.
- [ ] **F52 — if it recurs, build with `--no-pub`.** That skips the pub step entirely and with
      it the non-release regeneration, at the cost of requiring `flutter pub get` to have been
      run by hand after any `pubspec.yaml` change. Worth checking whether the IDE's Flutter
      plugin is running `pub get` on save, since that reintroduces the race from outside the
      build.
- [ ] **F52 — do not hand-edit `GeneratedPluginRegistrant.java`.** `AGENTS.md` forbids editing
      generated plugin registrants, `android/.gitignore:7` does not track it, and the next
      generation overwrites it regardless — an edit there would look like a fix and silently
      stop being one.
- [x] **F45 — record how long the cutter actually takes** once F42 is restored and the mask is
      720×720. If it is slow enough to drop frames, moving the FFI call off the main isolate
      becomes a real item rather than a theoretical one; it also decides how much headroom
      phase 3's reordering has.

      **Measured on device: about 5 seconds** for the full analysis, wall-clock, by
      observation rather than instrumentation. Accepted for now at the user's explicit call.

      Recording the reservation without acting on it: 5 s is the whole pipeline, not the cutter
      alone, and it is spent synchronously on the UI thread (F45's own finding — no
      `Isolate.run`, `Isolate.spawn` or `compute(` anywhere in `lib/`). The ANR this phase
      opened with fired at the 10 s input-dispatch timeout quoted in the logcat, so the current
      figure sits at roughly half the budget that already killed the app once. It is fine while
      the input is a bounded ~720×720 mask; it has no headroom for a slower device, a larger
      mask, or phase 3's reordering, and moving the FFI call off the main isolate is the
      standing remedy whenever that margin is wanted back. Not scheduled — deferred, knowingly.

## Verification

Status: **all met. Phase 1 is closed.**

- [x] The freeze is reproducible before the change and absent after it, on the same photo.
- [x] The logcat names one of the two failure classes, so the fix is attributed rather than
      assumed. It named an ANR (`Input dispatching timed out`, `Completed ANR ... in 15621ms`),
      with no `Fatal signal`/`SIGSEGV`/uncaught-exception line against the app's own PID — so
      F43 plus F45, not F44.
- [x] A scan with no reference marked, and a scan that fails the scale range check, both
      complete without freezing — that is what closes F43 rather than F42. **Both tested on
      device after the F43 cap shipped; neither froze.**

Closed findings: **F42, F43, F44, F45, F52.** All five are fixed or measured, and all are
verified on device except F44, whose catch branch is unreachable in the test corpus and was
verified only as a non-regression through the host build (`test_cutter_identity`, exit 0).

One reservation is deferred rather than resolved: analysis takes about 5 s synchronously on
the UI thread, against the 10 s input-dispatch timeout that produced this phase's original
ANR. See F45 above.
