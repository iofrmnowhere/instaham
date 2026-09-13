# Native unit tests (ctest). Slice 0 shipped only the ABI smoke test; add the rest as
# slices land.
add_executable(test_abi test_abi.cpp)
target_link_libraries(test_abi PRIVATE instaham_ml)
add_test(NAME test_abi COMMAND test_abi)

# Gate D (ML_implementation_plan.md revision 7, section 10; carried forward by
# docs/plan-phase/2-native-cutter-chen16.md). stages/cutter.cpp is no longer the header-only
# identity dummy -- it wraps the ported vendor V176/V144 stack, which is unconditionally
# OpenCV-dependent, so unlike the old stub this only builds under INSTAHAM_ML_WITH_OPENCV.
# The top-level CMakeLists.txt now defaults that ON everywhere (host included), so in
# practice this is not expected to be skipped; it stays conditional so a build that
# explicitly disables OpenCV still configures instead of failing.
if(INSTAHAM_ML_WITH_OPENCV)
  add_executable(test_cutter_identity
    ../stages/cutter.cpp
    ${INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES}
    ${INSTAHAM_ML_VENDOR_V176_CUTTER_SOURCES}
    test_cutter_identity.cpp
  )
  target_include_directories(test_cutter_identity PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/instaham_v176/include)
  target_link_libraries(test_cutter_identity PRIVATE opencv_imgproc opencv_core)
  add_test(NAME test_cutter_identity COMMAND test_cutter_identity)

  # docs/plan-phase/2-native-cutter-chen16.md, "Two body-curve calls, not one".
  add_executable(test_body_curve_dual_call
    ../stages/cutter.cpp
    ${INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES}
    ${INSTAHAM_ML_VENDOR_V176_CUTTER_SOURCES}
    ../vendor/instaham_v176/src/features/BodyCurve.cpp
    test_body_curve_dual_call.cpp
  )
  target_include_directories(test_body_curve_dual_call PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/instaham_v176/include)
  target_link_libraries(test_body_curve_dual_call PRIVATE opencv_imgproc opencv_core)
  add_test(NAME test_body_curve_dual_call COMMAND test_body_curve_dual_call)
endif()

# ref_fix.md F8/F9: manifest.cpp's feature_domain.lower_multiplier and
# cm_per_px_target_uncertainty parsing. Pure JSON, no OpenCV/ORT dependency, so this
# builds unconditionally like test_abi/test_cutter_identity above.
add_executable(test_feature_domain ../manifest.cpp ../util/sha256.cpp test_feature_domain.cpp)
target_include_directories(test_feature_domain PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_feature_domain COMMAND test_feature_domain)

# docs/metrics-plan.md phase 4 task 3: pins the live values behind the §7 eligibility-check
# audit against the REAL shipped assets/ml/manifest.json, not a synthetic fixture. Pure JSON
# parsing like test_feature_domain above, so this builds unconditionally too. The path is
# baked in at configure time as an absolute path so the test runs correctly regardless of
# ctest's working directory.
get_filename_component(INSTAHAM_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
add_executable(test_shipped_manifest ../manifest.cpp ../util/sha256.cpp test_shipped_manifest.cpp)
target_include_directories(test_shipped_manifest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_compile_definitions(test_shipped_manifest PRIVATE
  INSTAHAM_SHIPPED_MANIFEST_PATH="${INSTAHAM_REPO_ROOT}/assets/ml/manifest.json")
add_test(NAME test_shipped_manifest COMMAND test_shipped_manifest)

# ref_fix.md F12: stages/mask_geometry.h's proto_box_bounds() + cropped_mask_area() -- the
# load-bearing regression test for the mask-selection fix. Header-only, pure array math, no
# OpenCV/ORT dependency, so this builds unconditionally too.
add_executable(test_mask_selection test_mask_selection.cpp)
target_include_directories(test_mask_selection PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_mask_selection COMMAND test_mask_selection)

# ref_fix.md F18: stages/canvas_scale.h's decide_canvas_scale() -- the round-4 fix's
# scale-aware canvas composition arithmetic. Header-only, pure array math, no OpenCV/ORT
# dependency, so this builds unconditionally too.
add_executable(test_segmentation_canvas test_segmentation_canvas.cpp)
target_include_directories(test_segmentation_canvas PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_segmentation_canvas COMMAND test_segmentation_canvas)

# add_executable(test_manifest test_manifest.cpp)          # slice 2
# add_executable(test_classifier_golden test_classifier_golden.cpp)  # slice 2
# add_executable(test_construction test_construction.cpp)   # revision 7, R2
# add_executable(test_feature_calculation test_feature_calculation.cpp)  # revision 7, R3
# add_executable(test_pipeline_routing test_pipeline_routing.cpp)  # revision 7, R4a

# TASKS.md W5/section 7.5: scale_mask_to_training_space() + extract_five_features()'s
# explicit RA denominator. Needs OpenCV like the rest of stages/, so it only builds when
# INSTAHAM_ML_WITH_OPENCV is on (Android via opencv-mobile, host via vcpkg -- see the
# top-level CMakeLists.txt).
if(INSTAHAM_ML_WITH_OPENCV)
  # stages/feature_calculation.cpp now also calls into the vendor Chen16 feature stack
  # (docs/plan-phase/2-native-cutter-chen16.md), so this target needs those sources +
  # include dir too, not just OpenCV itself.
  add_executable(test_scale_normalization
    ../stages/construction.cpp
    ../stages/feature_calculation.cpp
    ${INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES}
    ${INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES}
    test_scale_normalization.cpp
  )
  target_include_directories(test_scale_normalization PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/instaham_v176/include)
  target_link_libraries(test_scale_normalization PRIVATE opencv_imgproc opencv_core)
  add_test(NAME test_scale_normalization COMMAND test_scale_normalization)

  # docs/fix-3.md (round 7), phase 2: transform_mask_to_training_space() -- the single
  # composed 640 -> training-space transform. construction.cpp is pure OpenCV array math
  # (no vendor Chen16 / cutter sources needed here), so this target is lighter than
  # test_scale_normalization above.
  add_executable(test_mask_transform
    ../stages/construction.cpp
    test_mask_transform.cpp
  )
  target_include_directories(test_mask_transform PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
  target_link_libraries(test_mask_transform PRIVATE opencv_imgproc opencv_core)
  add_test(NAME test_mask_transform COMMAND test_mask_transform)

  # docs/plan-phase/2-native-cutter-chen16.md, "Add the feature-port gate test": a CLI
  # (not a ctest assertion) driven by ML/parity/chen16_feature_port_gate.py, which is the
  # actual comparison against the Python oracle. Built here so `ctest`/the build always
  # produces it, but it deliberately has no add_test() of its own -- Python is the driver.
  add_executable(chen16_feature_gate_cli
    ../stages/feature_calculation.cpp
    ../stages/construction.cpp
    ../util/image_io.cpp
    ${INSTAHAM_ML_VENDOR_V176_COMMON_SOURCES}
    ${INSTAHAM_ML_VENDOR_V176_FEATURE_SOURCES}
    chen16_feature_gate_cli.cpp
  )
  target_include_directories(chen16_feature_gate_cli PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/instaham_v176/include)
  target_link_libraries(chen16_feature_gate_cli PRIVATE opencv_imgproc opencv_core)
endif()
