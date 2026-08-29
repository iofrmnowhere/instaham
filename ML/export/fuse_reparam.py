"""Fold a GhostNetV3 checkpoint's re-parameterisation branches into inference-only form.

Section 6.1 of ML_implementation_plan.md: `model_state` in `ML/view_model/best.pt` and
`ML/health_cnn/best.pt` carries the training-time multi-branch form
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
"""
from __future__ import annotations

FUSION_TOLERANCE = 1e-5  # fused vs trained logits, section 6.1


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
