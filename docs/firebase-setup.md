# Firebase Test Lab setup — what the user must do before phase 6 can run

This document lists the one-time setup required before
`docs/metrics-phase/6-device-metrics.md` task 4 (the Firebase Test Lab run) can be executed.
Everything here needs a browser login or account-level access, so it has to be done by the
project owner, not by the assistant.

Once these steps are complete, the assistant can build both APKs and submit the Test Lab run
without further input.

## Current environment state (verified 2026-09-12)

| Item | State |
|---|---|
| Google Cloud SDK | Installed, version 578.0.0 |
| `gcloud` authentication | Active as `adrianjaredsido@gmail.com` |
| Active `gcloud` project | `kalinga-bc97f` — **not** the INSTAHAM project |
| `integration_test` dev dependency | Present, `pubspec.yaml:54` |
| Integration test file | Present, `integration_test/benchmark_test.dart` |
| `testing.googleapis.com` | Not enabled on any project yet |
| `toolresults.googleapis.com` | Not enabled on any project yet |

So the CLI and the test scaffolding are already in place. What is missing is a dedicated
Firebase project for INSTAHAM with the two Test Lab APIs turned on.

## Step 1 — Create a Firebase project for INSTAHAM

1. Go to <https://console.firebase.google.com>.
2. Click **Create a project** (or **Add project**).
3. Name it something clearly distinct from `kalinga`, for example `instaham-test-lab`.
4. Google Analytics is optional and not needed for Test Lab — declining it is fine.
5. Leave the plan as **Spark**. Test Lab's free tier allows 5 physical device runs per day,
   which is enough for the three device tiers phase 6 uses. No billing account and no credit
   card are required.

No Firebase SDK has to be added to the Flutter app. Test Lab runs plain APKs, so no
`firebase_core` dependency, no `google-services.json`, and no change to `android/` are needed.

## Step 2 — Record the project ID

Firebase shows the project ID in **Project settings → General**. It is the machine-readable
identifier, not the display name, and it often has a random suffix appended
(`instaham-test-lab-4f2c1`, for instance).

Report this exact ID back — the assistant needs it and cannot read it from the console.

## Step 3 — Point `gcloud` at the new project

Run this in the repository, substituting the real ID from step 2:

```powershell
gcloud config set project YOUR_PROJECT_ID
```

This switches the active project away from `kalinga-bc97f`. If `kalinga-bc97f` is still
needed for other work, note that `gcloud config set project` changes it globally for this
machine; switching back is the same command with the old ID.

## Step 4 — Enable the two Test Lab APIs

```powershell
gcloud services enable testing.googleapis.com toolresults.googleapis.com
```

`testing.googleapis.com` is the Test Lab API that accepts the run; `toolresults.googleapis.com`
stores the results, logcat output, screenshots, and video. Both are required — a run submitted
with only one enabled fails at submission time.

This step can also be done in the Google Cloud console under **APIs & Services → Library**, but
the command above is faster and does not require finding the right console project.

## Step 5 — Verify

```powershell
gcloud config get-value project
gcloud services list --enabled --filter="name:testing.googleapis.com OR name:toolresults.googleapis.com"
gcloud firebase test android models list --filter="lion OR oriole OR tokay"
```

The first should print the new project ID. The second should list both APIs. The third is the
real end-to-end check: it authenticates against Test Lab and confirms the three devices phase 6
targets are currently available in the catalogue. If any of the three is missing or retired, the
device table in `docs/device-testing-plan.md` needs a substitute chosen before the run.

## What happens after this

With steps 1-5 done, the assistant can complete phase 6 task 4 unattended:

1. Build both APKs with the `-Ptarget` flag, per `docs/device-testing-plan.md` phase 3.
2. Submit one Test Lab run across the three device tiers.
3. Pull the logcat values for metrics 1-3 and fill in the reporting template.

## Cost and quota, stated plainly

The run uses **3 of the 5 free physical device runs per day** allowed on Spark — one per device
tier. Nothing is billed and no billing account is attached. If a run needs to be repeated after
a test-code fix, that is another 3 runs, so at most one retry per day fits inside the free quota.

## Out of scope for this setup

Metric 5 (battery and thermal across 50 consecutive scans) is **not** unlocked by this setup.
Test Lab runs here use a 5-minute timeout and Spark's daily cap makes 50 consecutive scans
impossible to fit. It remains an unowned item in `docs/metrics-phase/6-device-metrics.md` task 7
and needs either a real device or a Blaze-tier long-run budget. Creating the Firebase project
does not change that.
