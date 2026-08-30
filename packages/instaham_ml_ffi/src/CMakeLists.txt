cmake_minimum_required(VERSION 3.18)
project(instaham_ml LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(INSTAHAM_ML_BUILD_TESTS "Build native ctest suite" OFF)
option(INSTAHAM_ML_WITH_ORT   "Link ONNX Runtime (slice 2+)"     OFF)
# ML_implementation_plan.md revision 7, section 11.1: OpenCV is a HARD dependency for
# stages/construction.cpp and stages/feature_calculation.cpp -- morphologyEx, findContours,
# minAreaRect, fitEllipse are not hand-rollable inside gate B's 1% feature tolerance.
#
# Defaults ON for Android (the only platform wired below) and OFF elsewhere, so a host
# ctest build -- which only needs the header-only stages/cutter.cpp for gate D -- neither
# requires the fetched prebuilts nor trips the non-Android FATAL_ERROR further down.
# NOTE: android/build.gradle.kts passes -DINSTAHAM_ML_WITH_OPENCV explicitly, which wins
# over this default; the two must be kept in agreement.
if(ANDROID)
  set(_INSTAHAM_ML_OPENCV_DEFAULT ON)
else()
  set(_INSTAHAM_ML_OPENCV_DEFAULT OFF)
endif()
option(INSTAHAM_ML_WITH_OPENCV "Link opencv-mobile (stages/, revision 7 section 11.1)"
       ${_INSTAHAM_ML_OPENCV_DEFAULT})

# ---- sources -----------------------------------------------------------------
# Slice 0 shipped only the skeleton. Slices 3/4 (Android-first pass) added the ORT-backed
# classifier path. ML_implementation_plan.md revision 7 reorganises the weight-branch
# geometry by PROCESS (section 3.2): segmenter.cpp becomes stages/segmentation.cpp (now
# emitting mask coefficients + prototype, not just boxes), and stages/{construction,
# feature_calculation}.cpp are new. stages/cutter.cpp is the IDENTITY DUMMY moved from
# this directory's old cutter.cpp, unchanged (section 3.4) -- there is nothing to port.
set(INSTAHAM_ML_SOURCES
  instaham_ml.cpp
  manifest.cpp
  onnx_runner.cpp
  classifier.cpp
  health_input.cpp   # protocol seam; only full_frame implemented (see health_input.h)
  pipeline.cpp       # THE FLOW -- section 3, revision 7. Nowhere else knows the order.
  stages/segmentation.cpp
  stages/construction.cpp
  stages/cutter.cpp             # identity dummy -- not ported, by design (section 3.4)
  stages/feature_calculation.cpp
  # stages/weight_prediction.cpp                                   # slice R4b, deferred
  util/image_io.cpp
  util/sha256.cpp
)

add_library(instaham_ml SHARED ${INSTAHAM_ML_SOURCES})

target_include_directories(instaham_ml
  PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# ---- optional third-party (pinned prebuilts fetched by scripts/fetch_deps.sh) ----
# No CMake config package ships for onnxruntime-android — it is a raw .so + C API
# headers extracted from the Maven AAR, so it is wired as an IMPORTED target by hand
# rather than via find_package().
if(INSTAHAM_ML_WITH_ORT)
  set(_ORT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/onnxruntime")
  if(ANDROID)
    set(_ORT_LIB "${_ORT_ROOT}/lib/android/${ANDROID_ABI}/libonnxruntime.so")
    if(NOT EXISTS "${_ORT_LIB}")
      message(FATAL_ERROR "onnxruntime not fetched for ABI ${ANDROID_ABI} -- run scripts/fetch_deps.sh (${_ORT_LIB})")
    endif()
    add_library(onnxruntime SHARED IMPORTED)
    set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION "${_ORT_LIB}")
  else()
    message(FATAL_ERROR "INSTAHAM_ML_WITH_ORT is only wired for Android in this pass; iOS lands with the xcframework at slice 5 iOS bring-up")
  endif()
  target_include_directories(instaham_ml PRIVATE "${_ORT_ROOT}/include")
  target_link_libraries(instaham_ml PRIVATE onnxruntime)
  target_compile_definitions(instaham_ml PRIVATE INSTAHAM_ML_HAS_ORT=1)
endif()

# build_fix.md (2026-08-30): opencv-mobile DOES ship a CMake config package
# (sdk/native/jni/abi-<ABI>/OpenCVConfig.cmake), unlike onnxruntime above -- use it rather
# than hand-wiring IMPORTED targets. The hand-wired version linked only opencv_core/
# opencv_imgproc and silently dropped their real transitive deps: the OpenMP runtime
# (-fopenmp -static-openmp), three KleidiCV archives on arm64-v8a (opencv_core routes its
# HAL through them there), and -llog. All of that is declared in the config's own
# INTERFACE_LINK_LIBRARIES, which find_package() picks up automatically -- re-deriving it
# by hand is what produced the undefined-symbol link failure this replaces.
if(INSTAHAM_ML_WITH_OPENCV)
  set(_OPENCV_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/opencv")
  if(NOT ANDROID)
    message(FATAL_ERROR "INSTAHAM_ML_WITH_OPENCV is only wired for Android in this pass; iOS lands with opencv-mobile's xcframework at iOS bring-up")
  endif()
  # Point straight at the ABI-specific config rather than the dispatching top-level one
  # (sdk/native/jni/OpenCVConfig.cmake), which keys off the legacy ANDROID_NDK_ABI_NAME
  # variable rather than the ANDROID_ABI the modern NDK toolchain file actually sets.
  set(OpenCV_DIR "${_OPENCV_ROOT}/sdk/native/jni/abi-${ANDROID_ABI}")
  if(NOT EXISTS "${OpenCV_DIR}/OpenCVConfig.cmake")
    message(FATAL_ERROR "opencv-mobile not fetched for ABI ${ANDROID_ABI} -- run scripts/fetch_deps.sh (${OpenCV_DIR})")
  endif()
  find_package(OpenCV REQUIRED COMPONENTS core imgproc)
  # opencv_core/opencv_imgproc carry their full transitive link interface (dl, m, log,
  # the kleidicv archives where applicable, -fopenmp -static-openmp) as
  # INTERFACE_LINK_LIBRARIES -- linking the module targets is sufficient.
  target_link_libraries(instaham_ml PRIVATE opencv_imgproc opencv_core)
  target_compile_definitions(instaham_ml PRIVATE INSTAHAM_ML_HAS_OPENCV=1)
  # NDK 28.2's libomp (LLVM 19) predates __kmpc_dispatch_deinit, which opencv-mobile's
  # NDK-r29-built libopencv_core.a references from cv::parallel_for_impl. Weak no-op shim,
  # inert once the NDK is bumped past r29. build_fix.md section 3, Option A.
  target_sources(instaham_ml PRIVATE util/openmp_compat.cpp)
endif()

# nlohmann/json — header-only, fetched into third_party/ by scripts/fetch_deps.sh
set(_NLOHMANN_INC "${CMAKE_CURRENT_SOURCE_DIR}/third_party/nlohmann_json/single_include")
if(EXISTS "${_NLOHMANN_INC}/nlohmann/json.hpp")
  target_include_directories(instaham_ml PRIVATE "${_NLOHMANN_INC}")
  target_compile_definitions(instaham_ml PRIVATE INSTAHAM_ML_HAS_JSON=1)
endif()

# ---- symbol visibility -----------------------------------------------------
set_target_properties(instaham_ml PROPERTIES
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)

target_link_options(instaham_ml PRIVATE
  "$<$<PLATFORM_ID:Android>:-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/instaham_ml.map>"
  "$<$<PLATFORM_ID:Android>:-Wl,--gc-sections>")

# ---- tests ---------------------------------------------------------------
if(INSTAHAM_ML_BUILD_TESTS)
  enable_testing()
  add_subdirectory(test)
endif()
