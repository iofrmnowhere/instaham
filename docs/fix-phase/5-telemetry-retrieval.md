# Phase 5 — F27 telemetry retrieval (Option A, debug build + `adb run-as`)

Status: in progress

This phase does one thing: get F20's persisted pipeline events off the phone so F28 has a
device-side `RA` to compare against the harness. No source changes. Option A uses
`adb run-as`, which needs no new code but does need a debug build.

Everything below was read out of the tree, not assumed:

- Drift opens the database as `name: 'instaham'` under `getApplicationSupportDirectory`
  (`lib/core/database/app_database.dart:199`). On Android that resolves to
  `/data/user/0/com.instaham.instaham/files/`.
- `applicationId` is `com.instaham.instaham` (`android/app/build.gradle:22`).
- The events live in table `pipeline_events`, columns `id, scan_id, stage, status, message,
  created_at` (`app_database.dart:111`, generated name at `app_database.g.dart:3940`).
- F20 writes one row per stage with the **whole** envelope block JSON-encoded into `message`.
  The stages worth pulling are `scale`, `segmentation`, `construction`, `features`, `weight`
  (`run_and_persist_pipeline_use_case.dart:132,176,186,205,258`).

## The catch, read this before starting

`run-as` only works on a **debug-signed, debuggable** build. Your current phone build came
from `flutter build apk`, which is release. Installing a debug build over a release one
requires an uninstall first, and **the uninstall wipes the app database** — so the three
"Weight Mismatch" scans already on the phone cannot be recovered this way. You will re-scan
the same three photos on the debug build.

That is not wasted work: step 5 turns the re-scan into a check that the debug build even
reproduces the release build's numbers. If it does not, that is itself a finding.

## Steps

- [ ] **1. Enable USB debugging.** On the phone: Settings → About phone → tap Build number
      seven times → back → System → Developer options → USB debugging on. Plug into the PC
      and accept the "Allow USB debugging?" RSA prompt.

- [ ] **2. Confirm the PC sees it.**
      ```
      adb devices
      ```
      Expect a serial with `device` next to it. `unauthorized` means the RSA prompt was not
      accepted; `no permissions` or an empty list usually means a cable or driver problem —
      try a different cable, USB port, or set the USB mode to "File transfer".

- [ ] **3. Build and install the debug APK.** From the repo root:
      ```
      flutter build apk --debug
      adb uninstall com.instaham.instaham
      adb install build/app/outputs/flutter-apk/app-debug.apk
      ```
      The `uninstall` is what wipes the old data — expected, see the catch above. If
      `install` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, the uninstall did not take;
      run it again.

- [ ] **4. Verify the build is actually debuggable** before scanning anything, so a failure
      here costs one command instead of three scans:
      ```
      adb shell run-as com.instaham.instaham id
      ```
      A uid line means Option A works. `run-as: package not debuggable` means it does not —
      stop here and switch to Option B (the in-app diagnostics export), noted at the bottom
      of this file.

- [ ] **5. Re-scan the same three photos**, the ones in `.pig_pictures/`: the 92 kg meter
      stick, the 118 kg Porac stick, the 96 kg Porac stick. Mark the reference object the
      same way each time. **Write down the weight the app shows for each**, then compare
      against the release build's numbers — 116.0 kg (96 kg photo), 108.3 kg (92 kg photo),
      128.8 kg (118 kg photo). Matching within a kilogram or so means the telemetry you are
      about to pull represents the build that produced the reported error. A large mismatch
      means the debug and release native builds differ, which changes the whole diagnosis —
      note it and tell me before continuing.

- [ ] **6. Fully close the app.** Swipe it out of the recents list. Drift runs SQLite in WAL
      mode, so recent writes may still be sitting in the `-wal` sidecar; closing the app
      checkpoints them into the main file. Skipping this is the most likely way to pull a
      database that is missing the scans you just did.

- [ ] **7. Find the database file.**
      ```
      adb shell run-as com.instaham.instaham ls -la files/
      ```
      Expect `instaham.sqlite`, possibly alongside `instaham.sqlite-wal` and
      `instaham.sqlite-shm`. If the name differs, use what is actually listed in the next
      step.

- [ ] **8. Pull it.** Use `exec-out`, not `shell` — `shell` mangles binary with newline
      translation and produces a corrupt file:
      ```
      adb exec-out run-as com.instaham.instaham cat files/instaham.sqlite > instaham.sqlite
      ```
      If step 7 listed `-wal` and `-shm` files, pull those too, into the same folder and with
      the same base name:
      ```
      adb exec-out run-as com.instaham.instaham cat files/instaham.sqlite-wal > instaham.sqlite-wal
      adb exec-out run-as com.instaham.instaham cat files/instaham.sqlite-shm > instaham.sqlite-shm
      ```

- [ ] **9. Sanity-check the pull before sending.** A truncated or empty file is the common
      failure and it looks like success at the shell:
      ```
      ls -l instaham.sqlite
      head -c 16 instaham.sqlite
      ```
      Expect a non-trivial size and the bytes `SQLite format 3`. A zero-byte file means
      `run-as` failed silently — re-check step 4.

- [ ] **10. Hand the file over.** Put `instaham.sqlite` (plus any sidecars) somewhere in the
      repo working tree or tell me the path, and say which scan is which photo if the order
      is not obvious. I read `pipeline_events` directly — no need to export or query it
      yourself.

## What I do with it

Read `features.RA` and the rest of the five values, `segmentation.ladder_rung`,
`content_scale`, `candidates_kept`, `mask_diagonal_fraction`, and `scale.k` for each of the
three scans. Compare `RA` field-by-field against the harness's `RA` for the same photo. That
comparison is F28, and F28 unblocks F25, F26, F31's conclusion, and any decision about the
cutter or `cm_per_px_target`.

## Acceptance

- `pipeline_events` contains `scale`, `segmentation`, `construction`, `features` and `weight`
  rows for three distinct `scan_id` values.
- Those three scans' displayed weights match the release build's 116.0 / 108.3 / 128.8 kg, or
  the mismatch is recorded.
- Every `features` row carries all five values, and every `segmentation` row carries
  `ladder_rung` and `rungs_tried`.

## If Option A fails

`run-as: package not debuggable` at step 4, or a device that will not authorize, means
Option B: a small in-app "Export diagnostics" action that writes the recent
`pipeline_events` rows to a JSON file and opens the Android share sheet, so the file can go
to Drive or Files by hand. That is a real source change — a screen action plus `share_plus`,
which is not currently a dependency — and it belongs in `docs/plan.md`, not here, since it is
a feature rather than part of the diagnosis. Say the word and I will write it up there.
