# ADR-008: The unscaled cutter input is size-capped, not gated off

Status: Accepted

Context: The cutter block in `pipeline.cpp` is guarded by `is_dorsal && have_mask` alone —
neither `scale_ok` nor the weight override gates it. That is deliberate: it keeps
`envelope["cutter"]` and `envelope["features"]` populated on photos with no usable reference
object, which is the only telemetry available for diagnosing the stage in the field. The
fallback mask it uses on that route is `pig_mask`, which `construct_pig_mask` unletterboxes
back to the original capture dimensions — roughly 3000×4000 on a modern phone.

That was harmless while the cutter was the identity stub of
[ADR-001](001-cutter-identity-stub.md), which returned immediately. Once the real V176/V144
stack shipped it stopped being harmless: the shrinking-ball and medial-axis passes were written
against the 720×720 training frame, and about 20× the pixel count made the first field build
hang long enough for Android to kill it as an ANR (`Input dispatching timed out`, ANR completed
in 15.6 s). The scaled route never had this problem — it is bounded by the 0.25–4.0 height-ratio
clamp to at most about 2880×2880, and normally lands near 720×720. Only the unscaled fallback
was unbounded.

Two fixes were available: gate the cutter on `scale_ok` so it does not run at all without a
scale, or cap the mask handed to it.

Decision: **Cap it.** `pipeline.cpp` defines `kUnscaledCutterMaxDimPx = 2880` — the same bound
the scaled path already guarantees, derived the same way (`training_scale` 720 ×
`kMaxValidHeightRatio` 4.0) — and when `scale_ok` is false the mask is resampled down to that
budget through the existing `scale_mask_to_training_space` before `cut_body_mask` sees it.
`scale_ok` itself is not touched, so everything gated on it is unchanged: `measured_on` still
reports `uncut_mask_unnormalized`, features from that route are still never weight input, and
no rejection reason moves.

Gating on `scale_ok` was rejected because it would have deleted the provisional-debugging
telemetry the fallback exists to provide, on every photo without a reference — a behaviour
change well beyond the defect. The problem was never that the cutter ran without a scale; it
was that it ran on an unbounded mask.

Consequences:

- The freeze is fixed at its cause rather than at the manifest flag that exposed it. Any future
  manifest, any unmarked photo, and any `scale_out_of_range` rejection now route a bounded mask.
- Unscaled-route telemetry is preserved, but it is now measured on a downsampled mask on
  high-resolution captures. It was already explicitly not-comparable to the scaled route
  (`measured_on` says so), so this costs nothing that was being relied on — but anyone treating
  those values as absolute pixel counts should read the label first.
- The cap is best-effort, not a gate: if the resample itself fails, the uncapped mask is still
  handed over. The cutter's own exception guards, including the one added for `applyJiDuan`,
  bound that to a decline rather than a crash — but it is a slow decline, not a fast one.
- 2880 is inherited, not measured. It is the bound the scaled path happens to guarantee, chosen
  so both routes share one number. If the real cutter turns out to be slow well below that, the
  right response is to measure and lower it rather than to add a second unrelated constant.
- Wall-clock analysis was measured at about 5 s on device after this change, against the 10 s
  input-dispatch timeout. That is a margin, not a fix; the pipeline still runs synchronously on
  the Dart main isolate, and moving it off is the standing remedy if the margin is ever wanted
  back.
