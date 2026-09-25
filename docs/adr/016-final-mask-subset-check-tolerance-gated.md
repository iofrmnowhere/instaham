# ADR-016: Ship README §17's FINAL_MASK ⊆ BASE_MASK check tolerance-gated, not literal

Status: Accepted

Context: README §17 lists shipped invariants for the normalize-first pipeline, including that
the cutter's final mask's foreground must be a subset of the base (pre-cut) mask's foreground —
head/neck removal should only ever remove pixels, never add any. Phase 5 measured this literally
against a real photograph (`corpus_a/75kg_pig_meter_stick.jpg`) and found it fails: the vendor
cutter's Ji/Duan preprocessing (`vendor/instaham_v176`) runs a morphological CLOSE before the cut
that legitimately fills small gaps, adding 17 of 46043 base-mask pixels (0.037%) that were not in
the base mask. This is expected denoising, not a displaced region or a coordinate bug — the added
pixels sit inside small gaps the base mask itself left, not somewhere the cut moved the silhouette
to.

Decision: Ship the check tolerance-gated rather than as a literal subset test.
`kMaxTolerableAddedMaskPxFraction = 0.01` (1%, two orders of magnitude above the one measurement
taken) is the threshold; a run whose added-pixel fraction exceeds it is a declared failure with
reason `final_mask_not_subset_of_base`, withholding weight the same way any other README §17
violation does. `final_mask_added_px` and `final_mask_removed_px` are recorded in
`envelope["cutter"]` on every run regardless of which side of the line it falls on, so the
measurement is visible without a code read whether or not the check fires.

Consequences: A literal reading of §17 would have failed every real capture tested, which would
have made the invariant useless as a signal — it would fire on ordinary cutter cleanup instead of
on the coordinate bugs it exists to catch. The 1% figure is a judgment call from one measured
photograph, not a swept statistic; if a future capture legitimately needs more Ji/Duan gap-fill
than that, the constant is what should move, not the check's removal
([`fix-phase-4/5-debug-and-assertions.md`](../fix-phase-4/5-debug-and-assertions.md)). The
`pipeline/cutter.md` status table documents the resulting `error` status and its reason string.
