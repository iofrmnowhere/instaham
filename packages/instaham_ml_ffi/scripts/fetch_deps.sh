#!/usr/bin/env bash
# Fetch pinned native prebuilts into src/third_party/. Run once per checkout / CI cache miss.
# Nothing here is committed; the URLs + sha256 are the source of truth.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TP="$HERE/src/third_party"
mkdir -p "$TP"

# ---- versions ----
# ORT_VERSION deliberately does NOT match ML/export/requirements-export.txt's onnxruntime
# pin (1.29.0, the workstation-side Python package used only to numerically self-check
# exports). This is the on-device C API runtime, pinned independently — see that file's
# DEVIATION note for why the export-side pin drifted from the original plan.
ORT_VERSION="1.17.1"
OPENCV_MOBILE_VERSION="4.9.0"
NLOHMANN_JSON_VERSION="3.11.3"

verify() { echo "${2}  ${1}" | sha256sum -c -; }

fetch() {
  local url="$1" out="$2" sha="$3"
  if [ -f "$out" ] && verify "$out" "$sha" >/dev/null 2>&1; then
    echo "cached: $out"; return
  fi
  echo "fetch:  $url"
  curl -fsSL "$url" -o "$out"
  verify "$out" "$sha"
}

echo "== stb_image (classifier/segmenter image decode + resize; core/ layer, section 3) =="
mkdir -p "$TP/stb"
fetch "https://raw.githubusercontent.com/nothings/stb/master/stb_image.h" \
      "$TP/stb/stb_image.h" \
      "594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3"
fetch "https://raw.githubusercontent.com/nothings/stb/master/stb_image_resize2.h" \
      "$TP/stb/stb_image_resize2.h" \
      "173e654634f6ccaad98f603e686ea212eec1fe8ea6d2a5e5e8056efa10ae3880"

echo "== nlohmann/json =="
mkdir -p "$TP/nlohmann_json/single_include/nlohmann"
fetch "https://github.com/nlohmann/json/releases/download/v${NLOHMANN_JSON_VERSION}/json.hpp" \
      "$TP/nlohmann_json/single_include/nlohmann/json.hpp" \
      "9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"

echo "== ONNX Runtime ${ORT_VERSION} (android aar) =="
# Full onnxruntime-android (not -mobile): the mobile package ships a reduced op set
# built from a specific ops-config and does not reliably include every op the exported
# GhostNetV3 / YOLO graphs use. Revisit -mobile once a real ops-config is generated from
# the shipped graphs (section 6, APK-size hardening pass / slice 6).
ORT_AAR="$TP/onnxruntime/_android.aar"
fetch "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ORT_VERSION}/onnxruntime-android-${ORT_VERSION}.aar" \
      "$ORT_AAR" \
      "35fc867b4d50942da3058f196d74c5669b4b34228794702cf15a05a4bd0b77c4"

mkdir -p "$TP/onnxruntime/include"
for abi in arm64-v8a armeabi-v7a x86_64; do
  mkdir -p "$TP/onnxruntime/lib/android/$abi"
done
unzip -o -q "$ORT_AAR" -d "$TP/onnxruntime/_extract"
cp "$TP/onnxruntime/_extract/headers/"*.h "$TP/onnxruntime/include/"
for abi in arm64-v8a armeabi-v7a x86_64; do
  cp "$TP/onnxruntime/_extract/jni/$abi/libonnxruntime.so" "$TP/onnxruntime/lib/android/$abi/"
done
rm -rf "$TP/onnxruntime/_extract" "$ORT_AAR"

echo "  (iOS xcframework: fetched at slice 4/5 iOS bring-up, not needed for the Android-first pass)"

echo "== opencv-mobile ${OPENCV_MOBILE_VERSION} =="
# fetch "https://github.com/nihui/opencv-mobile/releases/download/v${OPENCV_MOBILE_VERSION}/opencv-mobile-${OPENCV_MOBILE_VERSION}-android.zip" \
#       "$TP/opencv/android.zip" "REPLACE_WITH_SHA256"
echo "  (slice 4: uncomment once opencv-mobile is wired)"

echo "done."
