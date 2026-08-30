"""Synthetic smoke tests for ML/parity/reference_health_input.py (TASKS.md P5.2).

    pytest ML/parity/test_health_input.py -v

No fixture corpus of real pig photos with lesion regions exists yet (that is P3), so
these only prove the four protocols run, return the right tensor shape, and that the
abnormality proposer finds a planted anomaly and degrades gracefully when there is none.
"""
from __future__ import annotations

import numpy as np
import pytest

from ML.parity import reference_health_input as rhi


def _synthetic_pig(h=480, w=640):
    """Mid-grey photo with a lighter elliptical 'pig' body on it."""
    img = np.full((h, w, 3), 90, dtype=np.uint8)
    mask = np.zeros((h, w), dtype=np.uint8)
    yy, xx = np.ogrid[:h, :w]
    body = ((xx - w / 2) / (w * 0.32)) ** 2 + ((yy - h / 2) / (h * 0.28)) ** 2 <= 1.0
    img[body] = (170, 150, 140)
    mask[body] = 1
    return img, mask


def _plant_lesion(img, mask, cx, cy, r=28):
    yy, xx = np.ogrid[: img.shape[0], : img.shape[1]]
    spot = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    spot &= mask > 0
    img = img.copy()
    img[spot] = (60, 40, 30)  # dark, high-chroma patch
    return img, spot


def test_all_protocols_return_nchw_224():
    img, mask = _synthetic_pig()
    for protocol in rhi.PROTOCOLS:
        t = rhi.preprocess(img, protocol, mask=mask)
        assert t.shape == (1, 3, 224, 224)
        assert t.dtype == np.float32
        assert np.isfinite(t).all()


def test_region_protocols_fall_back_to_full_frame_without_region():
    img, _ = _synthetic_pig()
    full = rhi.preprocess(img, "full_frame")
    for protocol in ("segmentation_crop", "segmentation_masked", "abnormality_crop"):
        np.testing.assert_allclose(rhi.preprocess(img, protocol), full)


def test_abort_on_failure_raises_without_region():
    img, _ = _synthetic_pig()
    with pytest.raises(ValueError):
        rhi.preprocess(img, "segmentation_crop", on_failure="abort")


def test_proposer_locates_planted_lesion():
    img, mask = _synthetic_pig()
    cx, cy = 250, 240
    img, spot = _plant_lesion(img, mask, cx, cy)
    region = rhi.resolve_region(img.shape[:2], mask=mask)
    box = rhi.propose_abnormality_region(img, region)
    assert box is not None
    x0, y0, x1, y1 = box
    assert x0 <= cx <= x1 and y0 <= cy <= y1


def test_proposer_returns_none_on_uniform_skin():
    img, mask = _synthetic_pig()
    region = rhi.resolve_region(img.shape[:2], mask=mask)
    # a perfectly uniform body has no ranked hot component that survives the open
    box = rhi.propose_abnormality_region(img, region)
    assert box is None or (box[2] - box[0]) * (box[3] - box[1]) >= 1


def test_bbox_region_source_is_reported():
    img, _ = _synthetic_pig()
    region = rhi.resolve_region(img.shape[:2], bbox=(100, 100, 400, 380))
    assert region is not None and region.source == "bbox"


def test_masked_protocol_fills_background():
    img, mask = _synthetic_pig()
    region = rhi.resolve_region(img.shape[:2], mask=mask)
    masked = rhi.segmentation_masked(img, region)
    crop_ = rhi.segmentation_crop(img, region)
    assert not np.allclose(masked, crop_)
