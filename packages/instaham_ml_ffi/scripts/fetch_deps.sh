#!/usr/bin/env bash
# Fetch pinned native prebuilts into src/third_party/. Run once per checkout / CI cache miss.
# Nothing here is committed; the URLs + sha256 are the source of truth.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TP="$HERE/src/third_party"
mkdir -p "$TP"

# ---- versions (keep in sync with ML/export/requirements-export.txt and the manifest) ----
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

echo "== nlohmann/json =="
mkdir -p "$TP/nlohmann_json/single_include/nlohmann"
fetch "https://github.com/nlohmann/json/releases/download/v${NLOHMANN_JSON_VERSION}/json.hpp" \
      "$TP/nlohmann_json/single_include/nlohmann/json.hpp" \
      "REPLACE_WITH_SHA256"

echo "== ONNX Runtime Mobile ${ORT_VERSION} (android aar + ios xcframework) =="
# fetch "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-mobile/${ORT_VERSION}/onnxruntime-mobile-${ORT_VERSION}.aar" \
#       "$TP/onnxruntime/android.aar" "REPLACE_WITH_SHA256"
# fetch "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-mobile-ios.xcframework.zip" \
#       "$TP/onnxruntime/ios.xcframework.zip" "REPLACE_WITH_SHA256"
echo "  (slice 2: uncomment once ORT is wired)"

echo "== opencv-mobile ${OPENCV_MOBILE_VERSION} =="
# fetch "https://github.com/nihui/opencv-mobile/releases/download/v${OPENCV_MOBILE_VERSION}/opencv-mobile-${OPENCV_MOBILE_VERSION}-android.zip" \
#       "$TP/opencv/android.zip" "REPLACE_WITH_SHA256"
echo "  (slice 4: uncomment once opencv-mobile is wired)"

echo "done."
