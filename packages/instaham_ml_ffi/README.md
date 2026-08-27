# instaham_ml_ffi

Native C++ ML runtime for INSTAHAM, called from Flutter via `dart:ffi`.

- **Stable C ABI:** `src/include/instaham_ml.h` (only `instaham_ml_*` symbols are exported).
- **Payloads:** UTF-8 JSON strings, never C structs — fields can be added without an ABI break.
- **Runtime:** ONNX Runtime Mobile (view/health classifiers + XGBoost + later YOLO) plus
  opencv-mobile for the classical-CV feature path. The Python files in `../../ML/` are the
  reference implementation.

## Slice status

| Slice | State |
|---|---|
| 0 — toolchain skeleton | **this commit** — stub `.cpp`, all inference entrypoints return `ERR_UNAVAILABLE`; `ctest` `test_abi` |
| 1 — export + manifest | Python side under `../../ML/export/` |
| 2 — view classifier E2E | not started (`INSTAHAM_ML_WITH_ORT=ON`, `context.cpp` / `classifier.cpp`) |
| 3 — health + `health_only` | not started |
| 4 — XGBoost + provisional features | not started (`INSTAHAM_ML_WITH_OPENCV=ON`, `cv/*.cpp`) |
| 5 — YOLO segmentation | not started |

## Local dev

```bash
# fetch pinned prebuilts (slice 2+)
scripts/fetch_deps.sh

# native unit tests
cmake -S src -B build -DINSTAHAM_ML_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build --output-on-failure

# regenerate the ffigen bindings after editing instaham_ml.h
dart run ffigen --config ffigen.yaml
```

`lib/instaham_ml_bindings_generated.dart` is currently hand-authored; replace it with the
`ffigen` output once a local libclang is available.
