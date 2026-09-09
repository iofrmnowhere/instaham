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
# docs/plan-phase/2-native-cutter-chen16.md added a third hard dependent: stages/cutter.cpp
# now wraps the ported vendor V176/V144 stack, which is unconditionally OpenCV-based, so
# unlike revision 7 this is no longer a default that a host ctest build can leave off --
# every INSTAHAM_ML_SOURCES translation unit needs it now. Defaults ON everywhere; NOTE:
# android/build.gradle.kts passes -DINSTAHAM_ML_WITH_OPENCV explicitly, which wins over
# this default; the two must be kept in agreement.
option(INSTAHAM_ML_WITH_OPENCV "Link OpenCV (stages/, revision 7 section 11.1; phase 2 cutter port)"
       ON)

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
  stages/cutter.cpp             # V176/V144 port -- docs/plan-phase/2-native-cutter-chen16.md
  stages/quality_gates.cpp      # truncation/posture gate wiring -- docs/plan-phase/3-manifest-pipeline.md
  stages/feature_calculation.cpp
  stages/weight_prediction.cpp  # slice R4 -- runs the XGBoost ONNX graph, nothing else
  util/image_io.cpp
  util/sha256.cpp
)

# docs/plan-phase/2-native-cutter-chen16.md, "Build wiring": the vendor V176/V144 cutter
# and Chen16 feature stack are unconditionally OpenCV-dependent (every file below includes
# opencv2/core.hpp or opencv2/imgproc.hpp), so they are only buildable -- and only added to
# INSTAHAM_ML_SOURCES -- when INSTAHAM_ML_WITH_OPENCV is on. stages/cutter.cpp and
# stages/feature_calculation.cpp (both already unconditional sources above) call into this
# vendor code and therefore also require OpenCV; that dependency pre-dates this phase for
# feature_calculation.cpp and is new for cutter.cpp as of this phase. Split into four
# variables (rather than one flat list) so test/CMakeLists.txt can link narrower slices --
# e.g. the cutter test needs the cutter set plus MaskUtils/JiDuan, but not the Chen16
# feature set.
set(INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/MaskUtils.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/preprocess/JiDuan.cpp
)
set(INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/MaskArea.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/ConvexHullArea.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Difference.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/DifMask.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/BodyCurve.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Perimeter.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/OutlineCurve.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/CenterCrossingAxesWork.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Longest.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Shortest.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/HuMomentsWork.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu1.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu2.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu3.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu4.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu5.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu6.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Hu7.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/features/Chen16Vector.cpp
)
set(INSTAHAM_ML_VENDOR_V176_CUTTER_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/OutlineBuilder.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/ShrinkingBall.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/SelleFilter.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/TerminalGeometry.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/Break1Fit.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/ShoulderSelectorV176.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/src/cutter/CircleCutterV144.cpp
)
set(INSTAHAM_ML_VENDOR_V176_GATE_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/quality_gates/truncation_gate/EdgeTruncationDetector.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/quality_gates/posture_gate/PostureGate.cpp
)
set(INSTAHAM_ML_VENDOR_V176_SOURCES
  ${INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES}
  ${INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES}
  ${INSTAHAM_ML_VENDOR_V176_CUTTER_SOURCES}
  ${INSTAHAM_ML_VENDOR_V176_GATE_SOURCES}
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
  if(ANDROID)
    set(_OPENCV_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/opencv")
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
    # NDK 28.2's libomp (LLVM 19) predates __kmpc_dispatch_deinit, which opencv-mobile's
    # NDK-r29-built libopencv_core.a references from cv::parallel_for_impl. Weak no-op shim,
    # inert once the NDK is bumped past r29. build_fix.md section 3, Option A.
    target_sources(instaham_ml PRIVATE util/openmp_compat.cpp)
  else()
    # docs/plan-phase/2-native-cutter-chen16.md: the host ctest build needs a real OpenCV
    # too now that stages/cutter.cpp wraps the vendor V176/V144 stack. opencv-mobile above
    # is an Android-only prebuilt (no desktop libs in that drop) so the host side goes
    # through a normal desktop OpenCV instead -- point CMAKE_TOOLCHAIN_FILE at vcpkg's
    # scripts/buildsystems/vcpkg.cmake (installed: `vcpkg install opencv4[core]`) and this
    # ordinary find_package resolves it via vcpkg's exported config, same module names
    # (opencv_core, opencv_imgproc) as the Android path.
    find_package(OpenCV CONFIG REQUIRED COMPONENTS core imgproc)
    target_link_libraries(instaham_ml PRIVATE opencv_imgproc opencv_core)
  endif()
  target_compile_definitions(instaham_ml PRIVATE INSTAHAM_ML_HAS_OPENCV=1)

  # docs/plan-phase/2-native-cutter-chen16.md, "Build wiring" -- vendor sources are
  # unconditionally OpenCV-dependent, so they are only ever compiled inside this guard.
  target_sources(instaham_ml PRIVATE ${INSTAHAM_ML_VENDOR_V176_SOURCES})
  target_include_directories(instaham_ml PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/quality_gates/truncation_gate"
    "${CMAKE_CURRENT_SOURCE_DIR}/vendor/instaham_v176/quality_gates/posture_gate")
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
