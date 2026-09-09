# ADR-001: The cutter stays a C++ identity stub

Status: Superseded by [009](009-cutter-ported-after-all.md) — the cutter was ported to C++ and
now runs on every dorsal scan. The Chaquopy rejection below still stands.

Context: The research weight protocol removes the head and neck from the segmentation mask
before measuring features (`ML/pipeline/cutter.py`, `isolate_body_only_mask`). That code is
roughly 9,900 lines of geometry coupled tightly to SciPy and scikit-image. Two ways existed to
put it on device: port it to C++, or ship on-device Python via Chaquopy. A port risks silently
changing the research numbers that the whole weight branch is validated against, and it cannot
be proven equivalent without a fixture corpus that does not exist. Chaquopy costs 65–85 MB per
ABI, for a regressor the manifest itself already marks `"stability": "temporary"`.

Decision: `stages::cut_body_mask()` copies the input mask through unchanged and reports
`head_removal_applied = false`, `status = "identity_stub"`. The Chaquopy option is dropped
entirely. This is permanent for the current regressor, not a placeholder awaiting a port.

Consequences: A weight produced from the resulting mask includes the head and neck and
overestimates the protocol's number, so it is not a valid research estimate. Every layer must
carry that: `envelope["cutter"]` reports `protocol_implemented: false`, `envelope["weight"]`
attaches an explicit `note`, and `instaham_ml_predict_weight_json` returns
`INSTAHAM_ML_ERR_UNAVAILABLE` with `reason: cutter_identity_stub` unless the manifest sets the
weight test override. Passing the mask through is a structural convenience so stage 4 can be
exercised on real photos — never a licence to publish a weight from it. Because nothing
crosses a runtime boundary mid-pipeline, one native call always produces one complete
envelope, with no suspended state to resume on any platform.
