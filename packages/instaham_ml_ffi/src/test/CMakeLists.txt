# Native unit tests (ctest). Slice 0 shipped only the ABI smoke test; add the rest as
# slices land.
add_executable(test_abi test_abi.cpp)
target_link_libraries(test_abi PRIVATE instaham_ml)
add_test(NAME test_abi COMMAND test_abi)

# Gate D (ML_implementation_plan.md revision 7, section 10). Header-only include of
# stages/cutter.h -- no ORT/OpenCV dependency, so this builds even when
# INSTAHAM_ML_WITH_ORT / INSTAHAM_ML_WITH_OPENCV are off.
add_executable(test_cutter_identity ../stages/cutter.cpp test_cutter_identity.cpp)
target_include_directories(test_cutter_identity PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_cutter_identity COMMAND test_cutter_identity)

# ref_fix.md F8/F9: manifest.cpp's feature_domain.lower_multiplier and
# cm_per_px_target_uncertainty parsing. Pure JSON, no OpenCV/ORT dependency, so this
# builds unconditionally like test_abi/test_cutter_identity above.
add_executable(test_feature_domain ../manifest.cpp ../util/sha256.cpp test_feature_domain.cpp)
target_include_directories(test_feature_domain PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME test_feature_domain COMMAND test_feature_domain)

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
# explicit RA denominator. Needs opencv-mobile like the rest of stages/, so it only builds
# when the Android toolchain provides it (see the top-level CMakeLists.txt comment on
# INSTAHAM_ML_WITH_OPENCV) -- there is no host OpenCV build in this tree to fall back to.
if(INSTAHAM_ML_WITH_OPENCV)
  add_executable(test_scale_normalization
    ../stages/construction.cpp
    ../stages/feature_calculation.cpp
    test_scale_normalization.cpp
  )
  target_include_directories(test_scale_normalization PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
  target_link_libraries(test_scale_normalization PRIVATE opencv_imgproc opencv_core)
  add_test(NAME test_scale_normalization COMMAND test_scale_normalization)
endif()
