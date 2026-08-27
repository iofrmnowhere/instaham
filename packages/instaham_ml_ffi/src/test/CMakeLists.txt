# Native unit tests (ctest). Slice 0 ships only the ABI smoke test; add the rest as slices land.
add_executable(test_abi test_abi.cpp)
target_link_libraries(test_abi PRIVATE instaham_ml)
add_test(NAME test_abi COMMAND test_abi)

# add_executable(test_manifest test_manifest.cpp)          # slice 2
# add_executable(test_classifier_golden test_classifier_golden.cpp)  # slice 2
# add_executable(test_five_features test_five_features.cpp)  # slice 4
# add_executable(test_letterbox test_letterbox.cpp)        # slice 4
