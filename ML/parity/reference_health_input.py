"""ML/parity/reference_health_input.py -- Python reference for the health-model input
protocols (ML_implementation_plan.md section 1.1(c); TASKS.md addendum P5).

Each protocol turns a photo (plus an optional pig region -- a binary mask when available,
otherwise the detector bounding box) into the 224x224 NCHW float tensor the GhostNetV3
health checkpoint consumes:

  full_frame           resize-shorter-side + center-crop of the whole photo (shipped default)
  segmentation_crop    crop to the pig region bbox, background retained, then resize/crop
  segmentation_masked  crop to the pig region bbox, background mean-filled, then resize/crop
  abnormality_crop     crop to the largest classically-detected abnormal patch on the pig

This is a parity/reference file, not a process stage. It operates on pixels, so it can
never live in any of the ML/pipeline/ stage files -- cutter.py's purity gate
(scripts/check_cutter_purity.sh) forbids image IO and any non-mask input, and none of
the other four stages take a raw photo either. The C++ port target is
health_input.{h,cpp} (section 3.2, the deliberate exception to the five-stage rule);
this file is the line-for-line reference that port is measured against.

Nothing here trains, fine-tunes, or loads a model. The abnormality proposer is CIELAB
statistics + morphology + connected components; the domain corrections are grey-world
colour constancy and scale matching. All classical CV (TASKS.md P5, "Nothing here is
retraining").
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from ML.export.common import IMAGENET_MEAN, IMAGENET_STD, RESIZE_RATIO

PROTOCOLS = ("full_frame", "segmentation_crop", "segmentation_masked", "abnormality_crop")
DEFAULT_PROTOCOL = "full_frame"

# Manifest params block (TASKS.md P5.1). These are the swappable knobs for the region
# protocols; the manifest carries a copy under capabilities.health.input so a change here
# is a manifest change, never a recompile.
HEALTH_INPUT_PARAMS: dict[str, object] = {
    "bbox_padding_ratio": 0.06,
    "background_fill": "imagenet_mean",
    "on_segmentation_failure": "full_frame",
    "abnormality": {
        # fraction of the region's shorter side to erode before sampling skin colour, so
        # the body outline itself does not read as an anomaly
        "erode_frac": 0.02,
        # keep this percent of in-region pixels, ranked by anomaly score -- a rank, never
        # an absolute threshold (TASKS.md Cause B: no invented cut-offs)
        "top_k_percent": 2.0,
        # weight of the local-texture term relative to the chromatic term when scoring
        "texture_weight": 0.5,
        # window (in fraction of region shorter side) for the local-L standard deviation
        "texture_window_frac": 0.03,
        # the proposed crop is grown so it spans at least this fraction of the pig
        # region's shorter side -- stops a 10 px blob being upscaled to 224 as mush.
        # NOTE: this is a floor on the LESION crop, not a relation to the region's own
        # size. An earlier revision expressed it as "region fills <= 0.6 of the crop",
        # which forced every crop to exceed the pig region and clamp to the whole frame.
        "min_crop_frac_of_region": 0.25,
        # candidate components are ranked by mean anomaly score x compactness, not raw
        # area: a compact, strongly-deviating patch is a lesion, a large diffuse one is
        # usually lighting or dirt.
        "compactness_weight": 1.0,
        "grey_world": True,
    },
}

_CROP = 224


# --------------------------------------------------------------------------------------
# region handling
# --------------------------------------------------------------------------------------
@dataclass
class PigRegion:
    """The pig's location in ORIGINAL image coordinates. `mask` is preferred when the
    segmentation mask decode is available; `bbox` (x0, y0, x1, y1) is the fallback the
    detector can already supply today (TASKS.md P5.1). `source` records which was used so
    the result envelope can report it."""

    bbox: tuple[int, int, int, int]
    mask: np.ndarray | None = None
    source: str = field(default="bbox")

    @classmethod
    def from_mask(cls, mask: np.ndarray) -> "PigRegion":
        ys, xs = np.where(mask > 0)
        if len(xs) == 0:
            raise ValueError("empty mask has no pig region")
        return cls(
            bbox=(int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1),
            mask=(mask > 0).astype(np.uint8),
            source="mask",
        )

    @classmethod
    def from_bbox(cls, bbox: tuple[float, float, float, float]) -> "PigRegion":
        x0, y0, x1, y1 = (int(round(v)) for v in bbox)
        return cls(bbox=(x0, y0, x1, y1), mask=None, source="bbox")

    def interior_mask(self, h: int, w: int) -> np.ndarray:
        """Binary HxW mask of the pig: the real mask if present, else the filled bbox."""
        out = np.zeros((h, w), dtype=np.uint8)
        if self.mask is not None:
            m = self.mask
            if m.shape != (h, w):
                m = cv2.resize(m, (w, h), interpolation=cv2.INTER_NEAREST)
            out[m > 0] = 1
            return out
        x0, y0, x1, y1 = self._clamped(h, w)
        out[y0:y1, x0:x1] = 1
        return out

    def _clamped(self, h: int, w: int) -> tuple[int, int, int, int]:
        x0, y0, x1, y1 = self.bbox
        x0 = max(0, min(x0, w - 1))
        y0 = max(0, min(y0, h - 1))
        x1 = max(x0 + 1, min(x1, w))
        y1 = max(y0 + 1, min(y1, h))
        return x0, y0, x1, y1


def resolve_region(
    image_hw: tuple[int, int],
    *,
    mask: np.ndarray | None = None,
    bbox: tuple[float, float, float, float] | None = None,
) -> PigRegion | None:
    if mask is not None and np.any(mask > 0):
        return PigRegion.from_mask(mask)
    if bbox is not None:
        return PigRegion.from_bbox(bbox)
    return None


# --------------------------------------------------------------------------------------
# shared preprocessing tail -- identical to ML/export/common.classifier_preprocessing()
# --------------------------------------------------------------------------------------
def _resize_shorter_then_crop(img: np.ndarray, crop: int = _CROP) -> np.ndarray:
    short = round(crop * RESIZE_RATIO)
    h, w = img.shape[:2]
    scale = short / min(h, w)
    resized = cv2.resize(
        img, (max(1, round(w * scale)), max(1, round(h * scale))), interpolation=cv2.INTER_LINEAR
    )
    rh, rw = resized.shape[:2]
    top = max(0, (rh - crop) // 2)
    left = max(0, (rw - crop) // 2)
    out = resized[top : top + crop, left : left + crop]
    if out.shape[:2] != (crop, crop):  # image smaller than crop after resize -- pad
        pad = np.zeros((crop, crop, 3), dtype=img.dtype)
        pad[: out.shape[0], : out.shape[1]] = out
        out = pad
    return out


def _to_nchw(img_uint8: np.ndarray) -> np.ndarray:
    arr = img_uint8.astype(np.float32) / 255.0
    arr = (arr - np.array(IMAGENET_MEAN, dtype=np.float32)) / np.array(IMAGENET_STD, dtype=np.float32)
    return arr.transpose(2, 0, 1)[None, ...]


def _imagenet_mean_rgb_uint8() -> np.ndarray:
    return np.round(np.array(IMAGENET_MEAN, dtype=np.float32) * 255.0).astype(np.uint8)


# --------------------------------------------------------------------------------------
# P5.3 -- classical domain-gap corrections (no training)
# --------------------------------------------------------------------------------------
def apply_domain_corrections(crop_img: np.ndarray, *, grey_world: bool = True) -> np.ndarray:
    """Grey-world colour constancy on the crop, so a shed lamp's warm cast or open shade's
    blue cast does not shift a lesion's a/b statistics -- the channels several health
    classes are separated on. Scale matching is handled upstream in abnormality_crop() by
    choosing the crop window; here we only neutralise illumination."""
    if not grey_world:
        return crop_img
    out = crop_img.astype(np.float32)
    means = out.reshape(-1, 3).mean(axis=0)
    grey = means.mean()
    scale = np.where(means > 1e-6, grey / means, 1.0)
    out = np.clip(out * scale, 0, 255)
    return out.astype(np.uint8)


# --------------------------------------------------------------------------------------
# abnormality proposer (P5.2)
# --------------------------------------------------------------------------------------
def propose_abnormality_region(
    image: np.ndarray,
    region: PigRegion,
    *,
    params: dict | None = None,
) -> tuple[int, int, int, int] | None:
    """Return the ORIGINAL-coordinate bbox of the largest classically-abnormal patch on
    the pig, or None if no region is available. Purely CIELAB stats + morphology +
    connected components -- see TASKS.md P5.2 for the step list."""
    p = {**HEALTH_INPUT_PARAMS["abnormality"], **(params or {})}  # type: ignore[dict-item]
    h, w = image.shape[:2]
    interior = region.interior_mask(h, w)
    if not np.any(interior):
        return None

    x0, y0, x1, y1 = region._clamped(h, w)
    short_side = max(1, min(x1 - x0, y1 - y0))

    # 1. erode so the body outline does not itself register as an anomaly
    erode_px = max(1, int(round(short_side * float(p["erode_frac"]))))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * erode_px + 1, 2 * erode_px + 1))
    eroded = cv2.erode(interior, k)
    if not np.any(eroded):
        eroded = interior

    # 2. robust skin reference in CIELAB over the eroded interior (median + MAD, so a big
    #    lesion cannot drag the reference toward itself)
    lab = cv2.cvtColor(image, cv2.COLOR_RGB2LAB).astype(np.float32)
    sel = eroded > 0
    ref_med = np.median(lab[sel], axis=0)
    mad = np.median(np.abs(lab[sel] - ref_med), axis=0)
    mad = np.where(mad < 1e-3, 1.0, mad)

    # 3. per-pixel score: chromatic deviation on a,b + local texture (local std of L)
    chroma = np.sqrt(
        ((lab[..., 1] - ref_med[1]) / mad[1]) ** 2 + ((lab[..., 2] - ref_med[2]) / mad[2]) ** 2
    )
    win = max(3, int(round(short_side * float(p["texture_window_frac"]))) | 1)
    L = lab[..., 0]
    mean_L = cv2.blur(L, (win, win))
    mean_L2 = cv2.blur(L * L, (win, win))
    local_std = np.sqrt(np.clip(mean_L2 - mean_L * mean_L, 0, None))
    ref_std = np.median(local_std[sel])
    ref_std_mad = np.median(np.abs(local_std[sel] - ref_std)) or 1.0
    texture = np.clip((local_std - ref_std) / ref_std_mad, 0, None)
    score = chroma + float(p["texture_weight"]) * texture
    score[~sel] = -np.inf

    # 4. select by RANK: keep the top-k percent of in-region pixels
    vals = score[sel]
    if vals.size == 0:
        return None
    cutoff = np.percentile(vals, 100.0 - float(p["top_k_percent"]))
    hot = ((score >= cutoff) & sel).astype(np.uint8)
    hot = cv2.morphologyEx(hot, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    if not np.any(hot):
        return None

    # 5. rank components by mean anomaly score x compactness, not by raw area -- a large
    #    diffuse component is usually lighting or dirt, a compact strongly-deviating one
    #    is the lesion.
    n, labels, stats, _ = cv2.connectedComponentsWithStats(hot, connectivity=8)
    if n <= 1:
        return None
    cw = float(p["compactness_weight"])
    best_idx, best_rank = None, -np.inf
    for i in range(1, n):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area < 16:  # denoise: a handful of pixels cannot be a lesion
            continue
        bw_i, bh_i = int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT])
        compactness = area / float(max(1, bw_i * bh_i))  # 1.0 = fills its own bbox
        mean_score = float(score[labels == i].mean())
        rank = mean_score * (compactness**cw)
        if rank > best_rank:
            best_rank, best_idx = rank, i
    if best_idx is None:
        return None
    bx, by, bw_, bh_ = (
        stats[best_idx, cv2.CC_STAT_LEFT],
        stats[best_idx, cv2.CC_STAT_TOP],
        stats[best_idx, cv2.CC_STAT_WIDTH],
        stats[best_idx, cv2.CC_STAT_HEIGHT],
    )
    pad = float(HEALTH_INPUT_PARAMS["bbox_padding_ratio"])
    px = int(round(bw_ * pad))
    py = int(round(bh_ * pad))
    lx0, ly0, lx1, ly1 = bx - px, by - py, bx + bw_ + px, by + bh_ + py

    # grow to a floor tied to the pig region's shorter side, so a tiny blob is not
    # upscaled to 224 as mush. This is a MINIMUM on the lesion crop; it never forces the
    # crop past the region (the bug that made every crop the whole frame).
    floor = int(round(short_side * float(p["min_crop_frac_of_region"])))
    cx, cy = (lx0 + lx1) / 2.0, (ly0 + ly1) / 2.0
    half_w = max((lx1 - lx0) / 2.0, floor / 2.0)
    half_h = max((ly1 - ly0) / 2.0, floor / 2.0)
    ex0, ey0 = int(round(cx - half_w)), int(round(cy - half_h))
    ex1, ey1 = int(round(cx + half_w)), int(round(cy + half_h))

    # 6. clamp
    ex0 = max(0, ex0)
    ey0 = max(0, ey0)
    ex1 = min(w, max(ex0 + 1, ex1))
    ey1 = min(h, max(ey0 + 1, ey1))
    return ex0, ey0, ex1, ey1


# --------------------------------------------------------------------------------------
# protocol entry points
# --------------------------------------------------------------------------------------
def _crop_to_bbox(
    image: np.ndarray,
    bbox: tuple[int, int, int, int],
    *,
    mask: np.ndarray | None = None,
    background_fill: str = "imagenet_mean",
) -> np.ndarray:
    h, w = image.shape[:2]
    x0, y0, x1, y1 = bbox
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, max(x0 + 1, x1)), min(h, max(y0 + 1, y1))
    patch = image[y0:y1, x0:x1].copy()
    if mask is not None:
        m = (mask > 0).astype(np.uint8)
        if m.shape != image.shape[:2]:
            m = cv2.resize(m, (w, h), interpolation=cv2.INTER_NEAREST)
        m = m[y0:y1, x0:x1]
        fill = (
            _imagenet_mean_rgb_uint8()
            if background_fill == "imagenet_mean"
            else np.zeros(3, dtype=np.uint8)
        )
        patch[m == 0] = fill
    return patch


def full_frame(image: np.ndarray, *, crop: int = _CROP) -> np.ndarray:
    return _to_nchw(_resize_shorter_then_crop(image, crop))


def segmentation_crop(
    image: np.ndarray,
    region: PigRegion,
    *,
    crop: int = _CROP,
) -> np.ndarray:
    pad = float(HEALTH_INPUT_PARAMS["bbox_padding_ratio"])
    h, w = image.shape[:2]
    x0, y0, x1, y1 = region._clamped(h, w)
    px, py = int(round((x1 - x0) * pad)), int(round((y1 - y0) * pad))
    patch = _crop_to_bbox(image, (x0 - px, y0 - py, x1 + px, y1 + py))
    return _to_nchw(_resize_shorter_then_crop(patch, crop))


def segmentation_masked(
    image: np.ndarray,
    region: PigRegion,
    *,
    crop: int = _CROP,
    background_fill: str | None = None,
) -> np.ndarray:
    fill = background_fill or str(HEALTH_INPUT_PARAMS["background_fill"])
    pad = float(HEALTH_INPUT_PARAMS["bbox_padding_ratio"])
    h, w = image.shape[:2]
    x0, y0, x1, y1 = region._clamped(h, w)
    px, py = int(round((x1 - x0) * pad)), int(round((y1 - y0) * pad))
    mask_full = region.interior_mask(h, w) if region.mask is not None else None
    patch = _crop_to_bbox(
        image, (x0 - px, y0 - py, x1 + px, y1 + py), mask=mask_full, background_fill=fill
    )
    return _to_nchw(_resize_shorter_then_crop(patch, crop))


def abnormality_crop(
    image: np.ndarray,
    region: PigRegion,
    *,
    crop: int = _CROP,
    params: dict | None = None,
) -> np.ndarray:
    """Crop to the proposed largest-abnormality bbox, with grey-world correction; falls
    back to full_frame when no abnormal component is found (TASKS.md P5.2 step 6 /
    on_segmentation_failure)."""
    p = {**HEALTH_INPUT_PARAMS["abnormality"], **(params or {})}  # type: ignore[dict-item]
    box = propose_abnormality_region(image, region, params=params)
    if box is None:
        return full_frame(image, crop=crop)
    x0, y0, x1, y1 = box
    patch = image[y0:y1, x0:x1]
    patch = apply_domain_corrections(patch, grey_world=bool(p["grey_world"]))
    return _to_nchw(_resize_shorter_then_crop(patch, crop))


def preprocess(
    image: np.ndarray,
    protocol: str,
    *,
    mask: np.ndarray | None = None,
    bbox: tuple[float, float, float, float] | None = None,
    on_failure: str | None = None,
    params: dict | None = None,
) -> np.ndarray:
    """Dispatch to a protocol. `image` is an EXIF-normalised RGB uint8 HxWx3 array.
    Returns a (1, 3, 224, 224) float32 NCHW tensor.

    The three region protocols need a pig region (mask preferred, bbox otherwise). When
    none is supplied they fall back to `on_failure` (default: the manifest's
    on_segmentation_failure, i.e. full_frame) rather than raising -- AGENTS.md rule 4,
    segmentation failure degrades health input, never blocks it."""
    if protocol not in PROTOCOLS:
        raise ValueError(f"unknown health input protocol {protocol!r}; expected one of {PROTOCOLS}")
    if protocol == "full_frame":
        return full_frame(image)

    region = resolve_region(image.shape[:2], mask=mask, bbox=bbox)
    if region is None:
        fallback = on_failure or str(HEALTH_INPUT_PARAMS["on_segmentation_failure"])
        if fallback == "abort":
            raise ValueError(f"protocol {protocol!r} needs a pig region and none was provided")
        return full_frame(image)

    if protocol == "segmentation_crop":
        return segmentation_crop(image, region)
    if protocol == "segmentation_masked":
        return segmentation_masked(image, region)
    return abnormality_crop(image, region, params=params)
