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


# ----------------------------------------------------------------------------------------
# docs/plan-phase-3/2-parity-gate-and-tests.md: the real pixel-parity gate. Drives
# health_input_gate_cli (packages/instaham_ml_ffi/src/test CMake target) over the three
# real, valid-dorsal scenario fixtures and compares its crop against
# reference_health_input.py's segmentation_crop / segmentation_masked on the SAME image
# and region. See that phase file's "Parity tolerance" / "Fixture corpus" sections for the
# reasoning behind HEALTH_INPUT_MAX_ABS_DIFF and the choice of fixtures 01/02/03.
# ----------------------------------------------------------------------------------------
import json
import os
import pathlib
import struct
import subprocess

import cv2

from ML.parity import compare as _compare
from ML.parity import reference_health_input as _rhi

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SCENARIOS_ROOT = REPO_ROOT / "test" / "fixtures" / "scenarios"
GATE_FIXTURE_IDS = ("01_valid_dorsal_100cm_reference",
                     "02_valid_dorsal_131cm_porac_reference",
                     "03_valid_dorsal_custom_reference")

# docs/handoff.md: the host native build directory is
# packages/instaham_ml_ffi/src/build/host (not .../build/host/src -- chen16_feature_port_
# gate.py's own DEFAULT_CLI_CANDIDATES predates that being written down and is wrong on
# this machine too; not fixed here as it is outside this phase's scope).
_DEFAULT_CLI_CANDIDATES = [
    "packages/instaham_ml_ffi/src/build/host/test/health_input_gate_cli.exe",
    "packages/instaham_ml_ffi/src/build/host/test/health_input_gate_cli",
]


def _find_default_cli() -> pathlib.Path | None:
    for rel in _DEFAULT_CLI_CANDIDATES:
        p = REPO_ROOT / rel
        if p.exists():
            return p
    return None


def _write_raw_mask(path: pathlib.Path, mask: "np.ndarray") -> None:
    h, w = mask.shape[:2]
    with open(path, "wb") as f:
        f.write(struct.pack("<ii", w, h))
        f.write(mask.astype("uint8").tobytes())


def _read_raw_crop(path: pathlib.Path) -> "np.ndarray":
    import numpy as np

    with open(path, "rb") as f:
        w, h = struct.unpack("<ii", f.read(8))
        data = np.frombuffer(f.read(w * h * 3), dtype=np.uint8)
    return data.reshape(h, w, 3)


def _ellipse_mask_from_bbox(h: int, w: int, bbox: tuple[float, float, float, float]):
    """Deterministic stand-in for the real segmentation mask (docs/plan-phase-3/
    2-parity-gate-and-tests.md, "Fixture corpus", open question 2): no real mask bitmap
    is recorded for any fixture, only the detector box, so segmentation_masked is
    measured against an ellipse inscribed in that box, generated once here -- not random,
    not hand-drawn, reproducible from meta.json alone."""
    import numpy as np

    x0, y0, x1, y1 = bbox
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    rx, ry = max(1.0, (x1 - x0) / 2.0), max(1.0, (y1 - y0) / 2.0)
    mask = np.zeros((h, w), dtype=np.uint8)
    cv2.ellipse(mask, (int(round(cx)), int(round(cy))), (int(round(rx)), int(round(ry))), 0,
                0, 360, 255, -1)
    return mask


def _load_fixture(fixture_id: str):
    d = SCENARIOS_ROOT / fixture_id
    meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    image_path = d / meta["image_file"]
    bbox = tuple(meta["observed_phase4"]["envelope"]["segmentation"]["selected_box_orig"])
    return image_path, bbox


def _run_cli(cli: pathlib.Path, image_path: pathlib.Path, protocol: str, out_path: pathlib.Path,
             *, mask_path: pathlib.Path | None, bbox: tuple[float, float, float, float]) -> tuple:
    x0, y0, x1, y1 = (str(int(round(v))) for v in bbox)
    if mask_path is not None:
        args = [str(cli), str(image_path), protocol, str(out_path), "mask", str(mask_path),
                x0, y0, x1, y1]
    else:
        args = [str(cli), str(image_path), protocol, str(out_path), "bbox", x0, y0, x1, y1]
    env = {**os.environ, "OPENCV_LOG_LEVEL": "SILENT"}
    result = subprocess.run(args, capture_output=True, text=True, check=True, env=env)
    line = next((l for l in reversed(result.stdout.splitlines()) if l.strip()), "")
    requested, applied, region_source, degraded = line.strip().split(",")
    return requested, applied, region_source, degraded == "1"


def _needs_gate_cli():
    return pytest.mark.skipif(
        _find_default_cli() is None,
        reason="health_input_gate_cli not built -- build packages/instaham_ml_ffi host "
        "ctest target 'health_input_gate_cli' first",
    )


@_needs_gate_cli()
@pytest.mark.parametrize("fixture_id", GATE_FIXTURE_IDS)
@pytest.mark.parametrize("protocol", ("segmentation_crop", "segmentation_masked"))
def test_gate_cli_matches_reference(tmp_path, fixture_id, protocol):
    cli = _find_default_cli()
    image_path, bbox = _load_fixture(fixture_id)

    bgr = cv2.imread(str(image_path))
    assert bgr is not None, f"failed to decode {image_path}"
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    h, w = rgb.shape[:2]

    mask_path = None
    region = None
    if protocol == "segmentation_masked":
        mask = _ellipse_mask_from_bbox(h, w, bbox)
        mask_path = tmp_path / f"{fixture_id}_mask.raw"
        _write_raw_mask(mask_path, mask)
        region = _rhi.PigRegion(bbox=tuple(int(round(v)) for v in bbox), mask=mask, source="mask")
    else:
        region = _rhi.PigRegion(bbox=tuple(int(round(v)) for v in bbox), mask=None, source="bbox")

    out_path = tmp_path / f"{fixture_id}_{protocol}.raw"
    requested, applied, region_source, degraded = _run_cli(
        cli, image_path, protocol, out_path, mask_path=mask_path, bbox=bbox
    )
    assert requested == protocol
    assert applied == protocol, f"unexpectedly degraded: {applied}"
    assert degraded is False
    assert region_source == ("mask" if protocol == "segmentation_masked" else "bbox")

    cpp_crop = _read_raw_crop(out_path)

    if protocol == "segmentation_crop":
        py_tensor = _rhi.segmentation_crop(rgb, region)
    else:
        py_tensor = _rhi.segmentation_masked(rgb, region)
    # py_tensor is the normalized (1, 3, 224, 224) NCHW float tensor -- undo
    # _to_nchw() back to the uint8 HWC crop the CLI dumped, for a pixel comparison.
    import numpy as np

    mean = np.array(_rhi.IMAGENET_MEAN, dtype=np.float32)
    std = np.array(_rhi.IMAGENET_STD, dtype=np.float32)
    arr = py_tensor[0].transpose(1, 2, 0)
    py_crop = np.clip(np.round((arr * std + mean) * 255.0), 0, 255).astype(np.uint8)

    assert cpp_crop.shape == py_crop.shape
    diff = np.abs(cpp_crop.astype(np.int16) - py_crop.astype(np.int16))
    max_abs_diff = int(diff.max())
    mean_abs_diff = float(diff.mean())
    differing_fraction = float((diff > 0).mean())
    print(
        f"[{fixture_id}/{protocol}] max_abs_diff={max_abs_diff} "
        f"mean_abs_diff={mean_abs_diff:.4f} differing_fraction={differing_fraction:.4f}"
    )
    assert max_abs_diff <= _compare.HEALTH_INPUT_MAX_ABS_DIFF, (
        f"{fixture_id}/{protocol}: max_abs_diff={max_abs_diff} > "
        f"{_compare.HEALTH_INPUT_MAX_ABS_DIFF}"
    )
