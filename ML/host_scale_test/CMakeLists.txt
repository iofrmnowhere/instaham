cmake_minimum_required(VERSION 3.18)
project(host_scale_test LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# docs/test-plan-phase/1-host-toolchain.md: standalone host build of the app's real weight-
# branch C++ sources (not a reimplementation), for the cm_per_px_target 0.35 vs 0.3289 test.
# This file intentionally duplicates source lists from
# packages/instaham_ml_ffi/src/CMakeLists.txt rather than including it, because that file's
# INSTAHAM_ML_WITH_ORT branch hard-FATAL_ERRORs on non-Android and pulls in pipeline.cpp +
# the classifier/health branches this test does not need. The drift guard below is the
# mitigation for the duplication.

set(NATIVE_SRC ${CMAKE_CURRENT_SOURCE_DIR}/../../packages/instaham_ml_ffi/src)

# ---- drift guard: catch the vendor tree changing shape between sessions -------------
file(GLOB _V176_FEATURE_GLOB "${NATIVE_SRC}/vendor/instaham_v176/src/features/*.cpp")
list(LENGTH _V176_FEATURE_GLOB _V176_FEATURE_COUNT)
if(NOT _V176_FEATURE_COUNT EQUAL 19)
  message(FATAL_ERROR "expected 19 vendor feature sources, found ${_V176_FEATURE_COUNT} -- "
                       "packages/instaham_ml_ffi/src/CMakeLists.txt's "
                       "INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES list must be re-copied here")
endif()

file(GLOB _V176_CUTTER_GLOB "${NATIVE_SRC}/vendor/instaham_v176/src/cutter/*.cpp")
list(LENGTH _V176_CUTTER_GLOB _V176_CUTTER_COUNT)
if(NOT _V176_CUTTER_COUNT EQUAL 7)
  message(FATAL_ERROR "expected 7 vendor cutter sources, found ${_V176_CUTTER_COUNT} -- "
                       "packages/instaham_ml_ffi/src/CMakeLists.txt's "
                       "INSTAHAM_ML_VENDOR_V176_CUTTER_SOURCES list must be re-copied here")
endif()

# ---- explicit source list (copied from packages/instaham_ml_ffi/src/CMakeLists.txt) -----
set(APP_STAGE_SOURCES
  ${NATIVE_SRC}/manifest.cpp
  ${NATIVE_SRC}/onnx_runner.cpp
  ${NATIVE_SRC}/util/image_io.cpp
  ${NATIVE_SRC}/util/sha256.cpp
  ${NATIVE_SRC}/stages/segmentation.cpp
  ${NATIVE_SRC}/stages/construction.cpp
  ${NATIVE_SRC}/stages/cutter.cpp
  ${NATIVE_SRC}/stages/feature_calculation.cpp
  ${NATIVE_SRC}/stages/weight_prediction.cpp
)

set(VENDOR_COMMON_SOURCES
  ${NATIVE_SRC}/vendor/instaham_v176/src/MaskUtils.cpp
  ${NATIVE_SRC}/vendor/instaham_v176/src/preprocess/JiDuan.cpp
)

set(APP_INCLUDE_DIRS
  ${NATIVE_SRC}
  ${NATIVE_SRC}/include
  ${NATIVE_SRC}/vendor/instaham_v176/include
  ${NATIVE_SRC}/third_party/onnxruntime/include
  ${NATIVE_SRC}/third_party/nlohmann_json/single_include
)

# ---- ONNX Runtime (host-generated import lib, phase 1) -------------------------------
set(ORT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
add_library(host_onnxruntime SHARED IMPORTED)
set_target_properties(host_onnxruntime PROPERTIES
  IMPORTED_LOCATION "${ORT_ROOT}/onnxruntime.dll"
  IMPORTED_IMPLIB "${ORT_ROOT}/onnxruntime.lib")

# ---- OpenCV (vcpkg) -------------------------------------------------------------------
# imgcodecs: docs/fix-phase-4/5-debug-and-assertions.md's README section 16 image dumps
# (normalized RGB / BASE_MASK / FINAL_MASK), host-only per that phase's scoping -- core and
# imgproc alone (the app's own dependency set) cannot write a PNG.
find_package(OpenCV CONFIG REQUIRED COMPONENTS core imgproc imgcodecs)

# ---- phase 1: trivial smoke-test binary -----------------------------------------------
# Proves the toolchain (vcpkg OpenCV + generated ORT import lib + vendor sources) links.
# Kept alongside phase 2's real CLI as a cheap toolchain regression check.
add_executable(host_scale_smoke
  smoke_main.cpp
  ${APP_STAGE_SOURCES}
  ${VENDOR_COMMON_SOURCES}
  ${_V176_FEATURE_GLOB}
  ${_V176_CUTTER_GLOB}
)
target_include_directories(host_scale_smoke PRIVATE ${APP_INCLUDE_DIRS})
target_compile_definitions(host_scale_smoke PRIVATE INSTAHAM_ML_HAS_OPENCV=1 INSTAHAM_ML_HAS_JSON=1)
target_link_libraries(host_scale_smoke PRIVATE opencv_core opencv_imgproc host_onnxruntime)

add_custom_command(TARGET host_scale_smoke POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${ORT_ROOT}/onnxruntime.dll" "$<TARGET_FILE_DIR:host_scale_smoke>/onnxruntime.dll"
)

# ---- phase 2: the real weight-branch replication CLI -----------------------------------
# docs/test-plan-phase/2-host-cli.md. Same source set as the smoke target above.
add_executable(weight_branch_cli
  weight_branch_cli.cpp
  ${APP_STAGE_SOURCES}
  ${VENDOR_COMMON_SOURCES}
  ${_V176_FEATURE_GLOB}
  ${_V176_CUTTER_GLOB}
)
target_include_directories(weight_branch_cli PRIVATE ${APP_INCLUDE_DIRS})
target_compile_definitions(weight_branch_cli PRIVATE INSTAHAM_ML_HAS_OPENCV=1 INSTAHAM_ML_HAS_JSON=1)
target_link_libraries(weight_branch_cli PRIVATE opencv_core opencv_imgproc opencv_imgcodecs host_onnxruntime)

add_custom_command(TARGET weight_branch_cli POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${ORT_ROOT}/onnxruntime.dll" "$<TARGET_FILE_DIR:weight_branch_cli>/onnxruntime.dll"
)
