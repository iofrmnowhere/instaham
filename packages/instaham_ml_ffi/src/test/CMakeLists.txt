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

# docs/plan-phase-4/1-native-cascade.md: manifest.cpp's parsing of
# capabilities.health.cascade against a synthetic fixture. Pure JSON parsing, no OpenCV/ORT,
# same wiring as test_feature_domain above.
add_executable(test_health_cascade_manifest ../manifest.cpp ../util/sha256.cpp
  test_health_cascade_manifest.cpp)
target_include_directories(test_health_cascade_manifest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_health_cascade_manifest COMMAND test_health_cascade_manifest)

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

# docs/fix-phase-4/5-debug-and-assertions.md: stages/invariants.h -- README section 17's
# required assertions. Header-only, pure scalar/array math, no OpenCV/ORT dependency, so
# this builds unconditionally too.
add_executable(test_stage_invariants test_stage_invariants.cpp)
target_include_directories(test_stage_invariants PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_stage_invariants COMMAND test_stage_invariants)

# docs/fix-phase-6/1-native-route-override.md: stages/view_route.h's resolve_view_route().
# Header-only, pure scalar/string logic, no OpenCV/ORT dependency, so this builds
# unconditionally too.
add_executable(test_view_route test_view_route.cpp)
target_include_directories(test_view_route PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_view_route COMMAND test_view_route)

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
  # docs/plan-phase-3/2-parity-gate-and-tests.md: health_input.{h,cpp}'s non-pixel
  # behaviour -- coordinate recovery, aspect preservation, degradation, mean fill, and
  # the region_source/protocol_applied reporting fields. Needs OpenCV (health_input.cpp
  # includes opencv2/core.hpp / opencv2/imgproc.hpp for the mask resample), so this is
  # gated the same as test_mask_transform above rather than unconditional like
  # test_stage_invariants.
  add_executable(test_health_input
    ../health_input.cpp
    ../util/image_io.cpp
    test_health_input.cpp
  )
  target_include_directories(test_health_input PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
  target_link_libraries(test_health_input PRIVATE opencv_imgproc opencv_core)
  add_test(NAME test_health_input COMMAND test_health_input)

  # docs/plan-phase-3/2-parity-gate-and-tests.md: pixel-parity gate against
  # ML/parity/reference_health_input.py, driven by ML/parity/test_health_input.py --
  # Python is the driver, matching chen16_feature_gate_cli's own comment below, so this
  # is add_executable only, no add_test.
  add_executable(health_input_gate_cli
    ../health_input.cpp
    ../util/image_io.cpp
    health_input_gate_cli.cpp
  )
  target_include_directories(health_input_gate_cli PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
  target_link_libraries(health_input_gate_cli PRIVATE opencv_imgproc opencv_core)

  # docs/plan-phase-3/3-measurement.md: host CLI that runs the real health classifier three
  # times (full_frame/segmentation_crop/segmentation_masked) over the same real capture and
  # segmentation mask, through the shipped stages -- not a Python reimplementation. Needs
  # ONNX Runtime (classifier.cpp, stages/segmentation.cpp, onnx_runner.cpp), so unlike
  # health_input_gate_cli above this also requires INSTAHAM_ML_WITH_ORT; the top-level
  # CMakeLists.txt defaults the host build to have it on (see manifest.health.model.path).
  # No add_test() -- this is a measurement tool phase 3's own script drives, not a ctest
  # assertion, matching chen16_feature_gate_cli's own comment.
  if(INSTAHAM_ML_WITH_ORT)
    add_executable(health_protocol_measure_cli
      ../classifier.cpp
      ../health_input.cpp
      ../manifest.cpp
      ../onnx_runner.cpp
      ../util/image_io.cpp
      ../util/sha256.cpp
      ../stages/segmentation.cpp
      ../stages/construction.cpp
      health_protocol_measure_cli.cpp
    )
    target_include_directories(health_protocol_measure_cli PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/..
      ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/nlohmann_json/single_include)
    # imgcodecs (cv::imwrite) only -- the `[dump_dir]` debug-image path (docs comment at
    # this file's own top). No other target in this tree writes images; find_package is
    # re-invoked here, scoped to this one target, rather than widening the top-level
    # CMakeLists.txt's `COMPONENTS core imgproc` (which also configures the Android build).
    find_package(OpenCV CONFIG REQUIRED COMPONENTS imgcodecs)
    target_link_libraries(health_protocol_measure_cli PRIVATE opencv_imgproc opencv_core
                                                                opencv_imgcodecs onnxruntime)
    target_include_directories(health_protocol_measure_cli PRIVATE
      "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/onnxruntime/include")
    target_compile_definitions(health_protocol_measure_cli PRIVATE INSTAHAM_ML_HAS_ORT=1
                                                                     INSTAHAM_ML_HAS_JSON=1)
  endif()

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
