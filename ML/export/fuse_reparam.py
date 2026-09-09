"""Fold a re-parameterised checkpoint's training-time branches into inference-only form.

Section 6.1 of ML_implementation_plan.md: `model_state` in `ML/view_model/best.pt` and
`ML/health_cnn/best.pt` (both GhostNetV3) carries the training-time multi-branch form
(`*_rpr_conv.{0,1,2}`, `*_rpr_skip`, `*_rpr_scale`). Exporting that as-is ships every
training branch as a fan of parallel Convs plus a scalar-scaled Add per Ghost module —
correct, but needlessly large and slow. This folds them.

The plan originally assumed a vendored `ML/models/ghostnetv3.py` would be needed because
`create_model("ghostnetv3_100")` was believed unavailable on stock timm. That is no longer
true for the pinned toolchain: `timm >= 1.0` ships `ghostnetv3_100` natively with matching
state-dict keys and shapes (verified against both checkpoints, 1956/1956 keys, strict
load). Fusion itself is `timm.utils.model.reparameterize_model` — this module exists so
the fold is one named, tested call site rather than inlined in every export script, and so
a future real architecture mismatch (e.g. a timm downgrade) fails here with a clear error
instead of silently exporting the unfused graph.

Not every architecture has anything to fold. `reparameterize_model` walks the module tree
looking for children exposing `.fuse()` / `.reparameterize()` / `.switch_to_deploy()` and is
a silent no-op where none exist — e.g. `mobilenetv4_conv_small` (the view classifier's
2026-09 replacement, docs/plan.md), which has no re-parameterisation branches at all. Running
the fold on such a model is harmless but the "< 1e-5" assertion below then proves nothing
(both sides are the same graph), so `has_reparam_modules()` lets a caller skip the step
outright rather than keep a check that always trivially passes.
"""
from __future__ import annotations

FUSION_TOLERANCE = 1e-5  # fused vs trained logits, section 6.1


def has_reparam_modules(model) -> bool:
    """True if any submodule exposes a fuse/reparameterize/switch_to_deploy hook.

    Mirrors exactly the predicate `timm.utils.model.reparameterize_model` uses internally
    to decide what to fold, so this never disagrees with what `fuse()` below would actually
    do.
    """
    for _, child in model.named_modules():
        if hasattr(child, "fuse") or hasattr(child, "reparameterize") or hasattr(
            child, "switch_to_deploy"
        ):
            return True
    return False


def fuse(model, *, sample_input, tolerance: float = FUSION_TOLERANCE):
    """Return a deployable (fused) copy of `model`, asserting numeric transparency.

    `sample_input` is a representative batch (any batch size >= 1) run through both the
    trained and fused models in eval mode; the maximum absolute logit difference must be
    below `tolerance` or this raises. Returns `(fused_model, max_abs_diff)`.
    """
    import numpy as np
    import torch
    from timm.utils.model import reparameterize_model

    model.eval()
    fused = reparameterize_model(model, inplace=False)
    fused.eval()

    with torch.no_grad():
        trained_logits = model(sample_input).numpy()
        fused_logits = fused(sample_input).numpy()
    max_abs = float(np.max(np.abs(trained_logits - fused_logits)))
    if max_abs >= tolerance:
        raise SystemExit(f"fused vs trained logits diverge too much: {max_abs:.2e}")
    return fused, max_abs
