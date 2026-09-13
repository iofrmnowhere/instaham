#!/usr/bin/env python3
"""docs/metrics-phase/3.1-corpus-rebuild.md -- reproducible generator for the 9 scenario
fixtures.

Scenarios 4 and 10 were removed (docs/metrics-plan.md finding 9, phase 4 task 0): the
capture flow now requires a marked reference object, so both no-reference premises are
unreachable. Ids keep their original numbering (1, 2, 3, 5, 6, 7, 8, 9, 11) rather than
being renumbered, so the mapping onto INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md section 14
stays one-to-one.

Run from the repo root:

    python test/fixtures/scenarios/generate_fixtures.py

Requires Pillow and pillow-heif (both present in this environment; if missing:
`pip install pillow pillow-heif`). Regenerating overwrites every fixture image, so the
transforms below are the single source of truth -- do not hand-edit the generated images.

Every fixture is deterministic (fixed crop boxes / blur radius, no randomness), so this
script can be re-run to reproduce the exact same corpus bit-for-bit.

v2 (3.1 rebuild): sources every scenario from the app's own real capture corpus --
.pig_pictures/ (4 handheld weight photos) and health_pigs/ (5 handheld health/side-view
photos) -- instead of the PIGRGB fixed-rig dataset and synthetic composites. PIGRGB is no
longer used by any scenario fixture (it stays available for phase 5 parity only, where
scale doesn't matter). This closes two audit gaps from docs/metrics-plan.md round 14:
no scenario 5 side-view (now IMG_9520.HEIC, a real one), and scenario 3's
fabricated-geometry custom reference (now a real sub-span of the visible meter tape in
75kg_pig_meter_stick.HEIC).

v3 (phase 4.1): scenario 7 (multiple pigs, LDPH5Y0l.jpg) is removed. The frame is rejected
at the view stage before segmentation ever runs, so it cannot exercise §14 bullet 7's
multi-pig mask-selection behaviour and only duplicated scenario 5's reject assertion. See
docs/metrics-phase/4.1-scenario-7-removal.md. §14 bullet 7 is an accepted coverage gap.
"""

import json
from pathlib import Path

import pillow_heif
from PIL import Image, ImageFilter, ImageOps

pillow_heif.register_heif_opener()

REPO_ROOT = Path(__file__).resolve().parents[3]
WEIGHT = REPO_ROOT / ".pig_pictures"
HEALTH = REPO_ROOT / "health_pigs"
OUT = Path(__file__).resolve().parent

# 75kg_pig_meter_stick.HEIC: the visible meter tape spans 1582 px end-to-end for its
# 100 cm length (measured by the user against the real tape markings, 2026-09-11). Used by
# scenario 3 to derive a real sub-span reference length instead of an acquisition-geometry
# guess.
METER_STICK_75KG_PX_PER_CM = 1582.0 / 100.0


def load_exif_upright(path: Path) -> Image.Image:
    """Opens an image and applies its EXIF orientation, mirroring the app's own rule 5
    ("correct EXIF orientation before any model receives the image")."""
    im = Image.open(path)
    return ImageOps.exif_transpose(im)


def save_jpeg(im: Image.Image, dest: Path, *, max_dim: int | None = None, quality: int = 88):
    im = im.convert("RGB")
    if max_dim is not None and max(im.size) > max_dim:
        im = im.copy()
        im.thumbnail((max_dim, max_dim), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, "JPEG", quality=quality)
    return dest


def save_png(im: Image.Image, dest: Path, *, max_dim: int | None = None):
    im = im.convert("RGB")
    if max_dim is not None and max(im.size) > max_dim:
        im = im.copy()
        im.thumbnail((max_dim, max_dim), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, "PNG")
    return dest


def save_heic(im: Image.Image, dest: Path, *, quality: int = 85):
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.convert("RGB").save(dest, "HEIF", quality=quality)
    return dest


def write_meta(scenario_dir: Path, meta: dict):
    (scenario_dir / "meta.json").write_text(
        json.dumps(meta, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )


def kb(path: Path) -> float:
    return path.stat().st_size / 1024.0


results = []


# --- Scenario 1: valid dorsal, 100 cm meter-stick reference -------------------------------
d = OUT / "01_valid_dorsal_100cm_reference"
im = load_exif_upright(WEIGHT / "92kg_pig_meter_stick.HEIC")
img_path = save_jpeg(im, d / "image.jpg", max_dim=1600, quality=90)
write_meta(
    d,
    {
        "scenario_id": 1,
        "title": "Valid dorsal image with 100 cm reference stick",
        "image_file": img_path.name,
        "source": {
            "origin": ".pig_pictures/92kg_pig_meter_stick.HEIC",
            "kind": "real_field_capture",
            "transform": "EXIF-upright, longest side resized to 1600px, re-encoded as JPEG q90",
            "recorded_weight_kg": 92.0,
            "notes": "real photo of a real yellow tailor's meter tape laid beside the pig; "
            "visible in the lower-left of the frame.",
        },
        "reference": {
            "provided": True,
            "physical_length_cm": 100.0,
            "pixel_endpoints": None,
            "pixel_endpoints_note": "not yet hand-marked -- pick the two tape endpoints "
            "visible in image.jpg and record them here before writing a Tier B numeric "
            "assertion in phase 4 (docs/metrics-plan.md phase 4).",
        },
        "expected_outcome": {
            "view": "dorsal_valid",
            "weight_branch": {"expect_number": True, "expected_failure_reason": None},
            "health_branch": {"expect_assessed": True},
        },
        "notes": "92 kg is comfortably above the ~73 kg XGBoost regressor floor (ADR-010).",
    },
)
results.append(("01", img_path))


# --- Scenario 2: valid dorsal, 131 cm Porac stick reference -------------------------------
d = OUT / "02_valid_dorsal_131cm_porac_reference"
im = load_exif_upright(WEIGHT / "96kg_pig_porac_stick.HEIC")
img_path = save_jpeg(im, d / "image.jpg", max_dim=1600, quality=90)
write_meta(
    d,
    {
        "scenario_id": 2,
        "title": "Valid dorsal image with 131 cm Porac stick reference",
        "image_file": img_path.name,
        "source": {
            "origin": ".pig_pictures/96kg_pig_porac_stick.HEIC",
            "kind": "real_field_capture",
            "transform": "EXIF-upright, longest side resized to 1600px, re-encoded as JPEG q90",
            "recorded_weight_kg": 96.0,
            "notes": "real photo of a real bamboo Porac reference stick laid beside the pig; "
            "visible along the left edge of the frame.",
        },
        "reference": {
            "provided": True,
            "physical_length_cm": 131.0,
            "pixel_endpoints": None,
            "pixel_endpoints_note": "not yet hand-marked -- see scenario 1's note; same "
            "requirement applies before a phase 4 Tier B numeric assertion.",
        },
        "expected_outcome": {
            "view": "dorsal_valid",
            "weight_branch": {"expect_number": True, "expected_failure_reason": None},
            "health_branch": {"expect_assessed": True},
        },
        "notes": "96 kg is comfortably above the ~73 kg XGBoost regressor floor (ADR-010).",
    },
)
results.append(("02", img_path))


# --- Scenario 3: valid dorsal, custom reference length (real sub-span of the same tape) ---
d = OUT / "03_valid_dorsal_custom_reference"
im = load_exif_upright(WEIGHT / "75kg_pig_meter_stick.HEIC")
img_path = save_jpeg(im, d / "image.jpg", max_dim=1600, quality=90)
custom_len_cm = 50.0
write_meta(
    d,
    {
        "scenario_id": 3,
        "title": "Valid dorsal image with custom positive reference length",
        "image_file": img_path.name,
        "source": {
            "origin": ".pig_pictures/75kg_pig_meter_stick.HEIC",
            "kind": "real_field_capture",
            "transform": "EXIF-upright, longest side resized to 1600px, re-encoded as JPEG q90",
            "recorded_weight_kg": 75.0,
            "notes": "real photo of the same yellow tailor's meter tape as scenario 1; its "
            "full visible span is 1582 px for the tape's 100 cm length (measured against "
            "the tape's own printed markings, 2026-09-11). This is the deliberate low end "
            "of the corpus weight range -- right at the ~73 kg XGBoost regressor floor "
            "(ADR-010), where the manifest's own note says a reading may run high.",
        },
        "reference": {
            "provided": True,
            "physical_length_cm": custom_len_cm,
            "pixel_endpoints": None,
            "pixel_endpoints_note": f"custom length exercised as a REAL sub-span of the "
            f"visible tape, not a fabricated geometry-derived value: {custom_len_cm} cm is "
            "half the tape's printed length, so its two endpoints are the tape's 0 cm mark "
            "and its 50 cm mark (both physically visible, verify against the tape's own "
            "printed tick when hand-marking). At the full-tape calibration of "
            f"{METER_STICK_75KG_PX_PER_CM:.4f} px/cm this spans roughly "
            f"{custom_len_cm * METER_STICK_75KG_PX_PER_CM:.0f} px before the 1600px resize "
            "above; re-derive after resize when marking.",
        },
        "expected_outcome": {
            "view": "dorsal_valid",
            "weight_branch": {"expect_number": True, "expected_failure_reason": None},
            "health_branch": {"expect_assessed": True},
        },
        "notes": "Near-floor fixture (75 kg): weight branch is expected to still produce a "
        "number (domain is valid), but its accuracy is not asserted -- only that the branch "
        "does not gate. See ADR-010 / finding 7 in docs/metrics-plan.md.",
    },
)
results.append(("03", img_path))


# --- Scenario 5: off-dorsal view -> weight blocked, health still classified --------------
d = OUT / "05_offdorsal_view"
im = load_exif_upright(HEALTH / "IMG_9520.HEIC")
img_path = save_jpeg(im, d / "image.jpg", max_dim=1600, quality=90)
write_meta(
    d,
    {
        "scenario_id": 5,
        "title": "Side-view image -> weight blocked, visual health classified",
        "image_file": img_path.name,
        "source": {
            "origin": "health_pigs/IMG_9520.HEIC",
            "kind": "real_field_capture",
            "transform": "EXIF-upright, longest side resized to 1600px, re-encoded as JPEG q90",
            "notes": "real lateral/side-on capture -- not a dorsal stand-in. Closes the "
            "round-14 gap where no genuine off-dorsal photo existed in the corpus.",
        },
        "reference": {"provided": False, "physical_length_cm": None},
        "expected_outcome": {
            "view": "health_only",
            "weight_branch": {
                "expect_number": False,
                "expected_failure_reason": "weight_needs_reference_object",
            },
            "health_branch": {"expect_assessed": True},
        },
        "notes": "Expected view is a hypothesis (side-on framing should route health_only "
        "per the 3-class vocabulary in assets/ml/view/classes.json) pending Tier B "
        "confirmation in phase 4.",
    },
)
results.append(("05", img_path))


# --- Scenario 6: lesion close-up -> visual health classified with confidence -------------
d = OUT / "06_lesion_closeup"
im = load_exif_upright(HEALTH / "owaKvudb.jpg")
w, h = im.size
box = (int(w * 0.28), int(h * 0.08), int(w * 0.85), int(h * 0.62))
crop = im.crop(box)
img_path = save_jpeg(crop, d / "image.jpg", max_dim=1200, quality=90)
write_meta(
    d,
    {
        "scenario_id": 6,
        "title": "Close-up lesion image -> visual health classified with confidence",
        "image_file": img_path.name,
        "source": {
            "origin": "health_pigs/owaKvudb.jpg",
            "kind": "real_capture_cropped",
            "transform": f"EXIF-upright crop box {box} (fractional 0.28-0.85 x / 0.08-0.62 y) "
            "of the source image, longest side resized to 1200px, JPEG q90. Deterministic -- "
            "same box every run.",
            "notes": "the source photo has real red hand-drawn skin marks on the pig's "
            "flank/back (visible in the cropped region) resembling a lesion/marking "
            "close-up -- not a synthetic overlay.",
        },
        "reference": {"provided": False, "physical_length_cm": None},
        "expected_outcome": {
            "view": "health_only",
            "weight_branch": {
                "expect_number": False,
                "expected_failure_reason": "weight_needs_reference_object",
            },
            "health_branch": {"expect_assessed": True},
        },
        "notes": "Expected view is a hypothesis (a tight torso close-up is unlikely to pass "
        "the dorsal-valid gate) pending Tier B confirmation in phase 4.",
    },
)
results.append(("06", img_path))


# --- Scenario 8: blurry -> low-confidence / reject, prompts retake ------------------------
d = OUT / "08_blurry"
im = load_exif_upright(HEALTH / "kARi2pdr.jpg")
blurred = im.filter(ImageFilter.GaussianBlur(radius=8))
img_path = save_jpeg(blurred, d / "image.jpg", quality=85)
write_meta(
    d,
    {
        "scenario_id": 8,
        "title": "Blurry image -> low-confidence/reject state, prompts retake",
        "image_file": img_path.name,
        "source": {
            "origin": "health_pigs/kARi2pdr.jpg",
            "kind": "synthetic_degradation",
            "transform": "PIL ImageFilter.GaussianBlur(radius=8) applied to the full frame, "
            "re-encoded as JPEG q85. Deterministic.",
            "notes": "no genuinely blurry photo exists in the corpus, so this stays a "
            "deliberate synthetic degradation of a real capture -- the only remaining "
            "synthetic fixture after the 3.1 rebuild.",
        },
        "reference": {"provided": False, "physical_length_cm": None},
        "expected_outcome": {
            "view": "reject",
            "weight_branch": {"expect_number": False, "expected_failure_reason": None},
            "health_branch": {"expect_assessed": False},
        },
        "notes": "Expected view is a hypothesis (radius-8 Gaussian blur is intended to push "
        "the view classifier to 'reject') pending Tier B confirmation in phase 4. If the "
        "shipped model still passes it, the blur radius must be increased and this file "
        "regenerated.",
    },
)
results.append(("08", img_path))


# --- Scenario 9: partially cropped/truncated pig ------------------------------------------
d = OUT / "09_truncated_pig"
im = load_exif_upright(HEALTH / "VBYvVvwj.jpg")
w, h = im.size
crop_box = (int(w * 0.38), 0, w, h)
crop = im.crop(crop_box)
img_path = save_jpeg(crop, d / "image.jpg", max_dim=1600, quality=90)
write_meta(
    d,
    {
        "scenario_id": 9,
        "title": "Partially cropped pig -> truncation behaviour (gate is off as shipped)",
        "image_file": img_path.name,
        "source": {
            "origin": "health_pigs/VBYvVvwj.jpg",
            "kind": "real_capture_cropped",
            "transform": f"EXIF-upright crop box {crop_box} of the {w}x{h} source, removing "
            "the pig's head/snout region that extended past x="
            f"{crop_box[0]}. Longest side resized to 1600px, JPEG q90. Deterministic.",
            "notes": "real photo of a pig against a wall; crop removes the head/snout.",
        },
        "reference": {"provided": False, "physical_length_cm": None},
        "expected_outcome": {
            "view": None,
            "weight_branch": {"expect_number": None, "expected_failure_reason": None},
            "health_branch": {"expect_assessed": None},
        },
        "notes": "docs/metrics-plan.md finding 6: capabilities.weight.quality_gates."
        "truncation is false in the shipped manifest, so truncation_gate_rejected cannot "
        "fire as shipped. Phase 4 must run this fixture through the default manifest AND "
        "through a test copy with the truncation gate flipped on, and record both outcomes "
        "here before writing the Tier A body.",
    },
)
results.append(("09", img_path))


# --- Scenario 11: HEIC / JPEG / PNG containers, same content ------------------------------
d = OUT / "11_container_formats"
im = load_exif_upright(WEIGHT / "75kg_pig_meter_stick.HEIC")
im_small = im.copy()
im_small.thumbnail((900, 900), Image.LANCZOS)
heic_path = save_heic(im_small, d / "image.heic")
jpeg_path = save_jpeg(im_small, d / "image.jpg", quality=90)
png_path = save_png(im_small, d / "image.png")
write_meta(
    d,
    {
        "scenario_id": 11,
        "title": "HEIC / JPEG / PNG inputs supported and processed accurately",
        "image_files": {
            "heic": heic_path.name,
            "jpeg": jpeg_path.name,
            "png": png_path.name,
        },
        "source": {
            "origin": ".pig_pictures/75kg_pig_meter_stick.HEIC",
            "kind": "real_capture_transcoded",
            "transform": "EXIF-upright, longest side resized to 900px once, then the SAME "
            "resized RGB pixel buffer re-encoded three ways (HEIF q85, JPEG q90, PNG "
            "lossless) so the three files carry equivalent content and only the container "
            "differs. Same source as scenario 3.",
        },
        "reference": {
            "provided": True,
            "physical_length_cm": 100.0,
            "pixel_endpoints": None,
            "pixel_endpoints_note": "same meter tape visible in all three containers -- not "
            "yet hand-marked, see scenario 1's note.",
        },
        "expected_outcome": {
            "view": "dorsal_valid",
            "weight_branch": {"expect_number": True, "expected_failure_reason": None},
            "health_branch": {"expect_assessed": True},
            "cross_container_agreement": "all three files must decode to the same view "
            "label, health label, and (AGENTS.md rule 5) EXIF-corrected orientation.",
        },
        "notes": "The source image's orientation was already upright after exif_transpose "
        "in this script; no additional orientation tag is embedded in the derivatives, so "
        "this fixture does NOT exercise a rotated-EXIF case on its own -- only "
        "cross-container decode agreement. A rotated-EXIF case remains open for phase 4 to "
        "add if the decode path needs that coverage.",
    },
)
results.append(("11", heic_path))
results.append(("11", jpeg_path))
results.append(("11", png_path))

total_kb = sum(kb(p) for _, p in results)
print(f"Generated {len(results)} files across 9 scenarios, {total_kb / 1024:.2f} MB total.")
for sid, p in results:
    print(f"  [{sid}] {p.relative_to(REPO_ROOT)}  ({kb(p):.1f} KB)")
