Pod::Spec.new do |s|
  s.name             = 'instaham_ml_ffi'
  s.version          = '0.0.1'
  s.summary          = 'Native C++ ML runtime for INSTAHAM (dart:ffi).'
  s.description       = 'ONNX Runtime + opencv-mobile inference behind a stable C ABI.'
  s.homepage         = 'https://example.com/instaham'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'INSTAHAM' => 'dev@example.com' }
  s.source           = { :path => '.' }

  # Compile the C ABI + (as slices land) the implementation sources.
  s.source_files     = 'Classes/**/*', '../src/instaham_ml.cpp', '../src/include/**/*.h'
  s.public_header_files = '../src/include/**/*.h'
  s.preserve_paths   = '../src/**/*'

  # Slice 2+: vendor the ONNX Runtime xcframework and link opencv-mobile.
  # s.vendored_frameworks = '../src/third_party/onnxruntime/onnxruntime.xcframework'
  # s.vendored_frameworks << '../src/third_party/opencv/opencv2.xcframework'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src/include"',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
