cmake_minimum_required(VERSION 3.18)
project(instaham_ml LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(INSTAHAM_ML_BUILD_TESTS "Build native ctest suite" OFF)
option(INSTAHAM_ML_WITH_ORT   "Link ONNX Runtime (slice 2+)"     OFF)
option(INSTAHAM_ML_WITH_OPENCV "Link opencv-mobile (slice 4+)"    OFF)

# ---- sources -----------------------------------------------------------------
# Slice 0 ships only the skeleton. Uncomment as each slice lands.
set(INSTAHAM_ML_SOURCES
  instaham_ml.cpp
  # context.cpp manifest.cpp onnx_runner.cpp classifier.cpp        # slice 2
  # xgboost_runner.cpp weight_pipeline.cpp                         # slice 4
  # cv/mask_cleanup.cpp cv/dorsal_core.cpp cv/five_features.cpp    # slice 4
  # cv/letterbox.cpp cv/body_mask_stub.cpp                        # slice 4
  # util/image_io.cpp util/sha256.cpp util/json_out.cpp util/errors.cpp
)

add_library(instaham_ml SHARED ${INSTAHAM_ML_SOURCES})

target_include_directories(instaham_ml
  PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# ---- optional third-party (pinned prebuilts fetched by scripts/fetch_deps.sh) ----
if(INSTAHAM_ML_WITH_ORT)
  find_package(onnxruntime REQUIRED)
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
