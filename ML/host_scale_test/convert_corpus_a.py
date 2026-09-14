"""docs/sweep-phase/2-field-corpus.md, Route 2 (host-side fallback): approximates
lib/core/utils/image_service.dart's import path for the four `.pig_pictures/` photographs,
used only because no physical device was available for Route 1 (device-side, `adb pull` of
the app's own `instaham_cap_*.jpg`). This is a documented deviation, not the exact path --
see the phase 2 doc and docs/sweep-phase/2-corpus-a-results.md for what it approximates and
why the numbers it produces must be cross-checked against docs/logs/recorded.md before use.

Pipeline mirrored (image_service.dart's five steps):
  1. HEIC -> RGB decode (pillow_heif / libheif) + resize so the long edge is <= 3000 px,
     matching ImagePicker.pickImage(maxWidth: 3000, maxHeight: 3000, imageQuality: 92) --
     approximated here as decode-then-resize-then-encode rather than a single Android-side
     transcode, because that transcode cannot be reproduced on this host.
  2. JPEG-encode at quality 92 (the first of the two encodes image_service.dart performs).
  3. Decode that JPEG back (img.decodeImage).
  4. Bake orientation (img.bakeOrientation / PIL ImageOps.exif_transpose).
  5. JPEG-encode at quality 92 again (the second encode) -> written to corpus_a/.

Deliberately does NOT carry forward the source HEIC files' EXIF Orientation=6 tag into the
step-1 JPEG: all three HEIC files decode to already-upright 3024x4032 pixel data (libheif
applies the container-level `irot` rotation on decode), and Orientation=6 on top of already
-upright pixels is a stale/vestigial tag common in HEIC output from iOS -- baking it would
incorrectly rotate a correctly-oriented image. Not carrying it forward makes step 4 a no-op
for these files, which is what recorded.md's 2250x3000 (portrait, unrotated) confirms the
real device path also produced.

Usage: python convert_corpus_a.py   (run from anywhere; paths are repo-root-relative)
"""
import glob
import io
import os

import pillow_heif
from PIL import Image, ImageOps

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC_DIR = os.path.join(REPO_ROOT, ".pig_pictures")
OUT_DIR = os.path.join(os.path.dirname(__file__), "corpus_a")
MAX_DIM = 3000
JPEG_QUALITY = 92

DECODER_VERSIONS = {
    "pillow_heif": pillow_heif.__version__,
    "libheif": pillow_heif.libheif_version(),
    "Pillow": __import__("PIL").__version__,
}


def load_upright_rgb(path):
    """Decode source image to upright RGB pixels, ignoring any stale EXIF orientation tag
    on HEIC sources (see module docstring)."""
    if path.lower().endswith(".heic"):
        heif_file = pillow_heif.open_heif(path, convert_hdr_to_8bit=True)
        img = heif_file[0]
        return Image.frombytes(img.mode, img.size, img.data, "raw").convert("RGB")
    im = Image.open(path)
    return ImageOps.exif_transpose(im).convert("RGB")  # source JPEG carries orientation=1


def step1_resize_and_encode(im):
    """Approximates ImagePicker's Android-side maxWidth/maxHeight=3000, quality=92 encode."""
    w, h = im.size
    long_edge = max(w, h)
    if long_edge > MAX_DIM:
        scale = MAX_DIM / float(long_edge)
        im = im.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=JPEG_QUALITY)
    return buf.getvalue()


def steps2to5_decode_bake_reencode(jpeg_bytes):
    """image_service.dart: img.decodeImage -> img.bakeOrientation -> img.encodeJpg(q92)."""
    im = Image.open(io.BytesIO(jpeg_bytes))
    im = ImageOps.exif_transpose(im)  # bakeOrientation equivalent; no-op absent a tag
    buf = io.BytesIO()
    im.convert("RGB").save(buf, format="JPEG", quality=JPEG_QUALITY)
    return buf.getvalue()


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Decoder versions:", DECODER_VERSIONS)
    sources = sorted(glob.glob(os.path.join(SRC_DIR, "*")))
    for src in sources:
        name = os.path.basename(src)
        stem, _ = os.path.splitext(name)
        out_path = os.path.join(OUT_DIR, stem + ".jpg")

        upright = load_upright_rgb(src)
        step1_bytes = step1_resize_and_encode(upright)
        final_bytes = steps2to5_decode_bake_reencode(step1_bytes)

        with open(out_path, "wb") as f:
            f.write(final_bytes)

        final_im = Image.open(io.BytesIO(final_bytes))
        print("%-40s %s -> %s  size=%s" % (name, upright.size, out_path, final_im.size))


if __name__ == "__main__":
    main()
