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

# add_executable(test_manifest test_manifest.cpp)          # slice 2
# add_executable(test_classifier_golden test_classifier_golden.cpp)  # slice 2
# add_executable(test_construction test_construction.cpp)   # revision 7, R2
# add_executable(test_feature_calculation test_feature_calculation.cpp)  # revision 7, R3
# add_executable(test_pipeline_routing test_pipeline_routing.cpp)  # revision 7, R4a
