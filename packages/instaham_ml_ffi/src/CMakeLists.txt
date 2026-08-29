cmake_minimum_required(VERSION 3.18)
project(instaham_ml LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(INSTAHAM_ML_BUILD_TESTS "Build native ctest suite" OFF)
option(INSTAHAM_ML_WITH_ORT   "Link ONNX Runtime (slice 2+)"     OFF)
option(INSTAHAM_ML_WITH_OPENCV "Link opencv-mobile (slice 4+)"    OFF)

# ---- sources -----------------------------------------------------------------
# Slice 0 shipped only the skeleton. Slices 3/4 (Android-first pass) add the ORT-backed
# classifier/segmenter path; the cv/ geometry port (weight branch) is still deferred to
# its own slice per section 3.5 of ML_implementation_plan.md.
set(INSTAHAM_ML_SOURCES
  instaham_ml.cpp
  manifest.cpp
  onnx_runner.cpp
  classifier.cpp
  segmenter.cpp
  util/image_io.cpp
  util/sha256.cpp
  # xgboost_runner.cpp weight_pipeline.cpp                         # slice 5 decision point
  # cv/mask_cleanup.cpp cv/dorsal_core.cpp cv/five_features.cpp    # slice 5 decision point
  # cv/letterbox.cpp cv/body_mask_stub.cpp
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

if(INSTAHAM_ML_WITH_OPENCV)
  set(OpenCV_STATIC ON)
  find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)
  target_link_libraries(instaham_ml PRIVATE ${OpenCV_LIBS})
  target_compile_definitions(instaham_ml PRIVATE INSTAHAM_ML_HAS_OPENCV=1)
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
