# ADR-009: The cutter is ported to C++ after all

Status: Accepted

Context: [ADR-001](001-cutter-identity-stub.md) decided that `stages::cut_body_mask()` would
remain an identity stub, and stated that this was "permanent for the current regressor, not a
placeholder awaiting a port." Its reasoning was sound on its own terms: roughly 9,900 lines of
SciPy- and scikit-image-coupled geometry, no fixture corpus to prove a port equivalent, and
Chaquopy costing 65–85 MB per ABI for a regressor the manifest itself marked
`"stability": "temporary"`.

[ADR-005](005-identity-cutter-is-the-dominant-error.md) then priced that decision rather than
revisiting it. Substituting the pre-cut area for the post-cut one across the 2014-row eval set
moved MAE from 4.94 kg to 19.96 kg and mean bias from −1.0% to +16.6%, against +15.9% observed
on device. ADR-005's own consequence section drew the conclusion explicitly: "not ported" could
not remain the end state without accepting a ~16% bias, and choosing among a C++ port, an
off-device service, and a reduced portable subset was left open as F40.

That choice has since been made and executed. A vendor drop of the V176 shoulder selector and
V144 circle cut was ported into `src/vendor/instaham_v176/`, compiling unmodified apart from one
logged edit, with a per-file sha256 recorded in `src/vendor/instaham_v176/VENDOR.md`. The
equivalence concern ADR-001 raised was not dissolved — there is still no oracle for a single
cut — but it was bounded by porting a specific vendor implementation verbatim rather than
reimplementing the Python reference.

Decision: `stages::cut_body_mask()` runs the real Ji/Duan cleanup → outline build →
shrinking-ball medial candidates → Selle filter → terminal trunk geometry → break1 fit → V176
shoulder selection → V144 circle cut chain. `pipeline.cpp` calls it on every dorsal scan and
reports `protocol_implemented: true` with a `protocol_version` string naming the vendor
protocol. ADR-001 is superseded; its identity-stub decision and the
`reason: cutter_identity_stub` unavailability path it mandated no longer describe shipped
behaviour. Chaquopy stays dropped — that half of ADR-001 survives.

Consequences: The single largest known error term in the weight branch is closed, but its
closure is **unverified in the field**. ADR-005's +16.6% figure was measured by feature
substitution on the pre-port app; nothing has yet re-measured field bias with the real cutter
running, so no accuracy claim may cite the port as evidence until a device run does.

The cut now runs on a mask that has already been resampled by `k`
(`pipeline.cpp:667-697`), which places a threshold-heavy geometric algorithm downstream of a
quantized `INTER_NEAREST` resample. F53
([../fix-phase-2/2.1-reference-length-sensitivity.md](../fix-phase-2/2.1-reference-length-sensitivity.md))
measures 11.45% weight spread from reference-marking noise with the cutter *excluded*, and
identifies the cutter's own contribution as unmeasured. Whether the port absorbs that jitter or
amplifies it is open, and it is the reason `docs/fix-2.md` phase 2.1 blocks phase 2's
calibration comparison.

Because the cutter is real, `weight.available` is no longer gated on it. It is now gated on
phase 5's field re-derivation of `cm_per_px_target` from post-cut masks, and
`pipeline.cpp` names that pending work as `weight_pending_field_validation` rather than
`cutter_identity_stub` — a different claim, deliberately, because the old one would now be
false.
