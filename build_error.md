PS C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham> flutter build apk

FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':instaham_ml_ffi:buildCMakeRelWithDebInfo[arm64-v8a]'.
> com.android.ide.common.process.ProcessException: ninja: Entering directory `C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\packages\instaham_ml_ffi\android\.cxx\RelWithDebInfo\1y4l3g5f\arm64-v8a'
  [1/13] Building CXX object CMakeFiles/instaham_ml.dir/stages/cutter.cpp.o
  [2/13] Building CXX object CMakeFiles/instaham_ml.dir/health_input.cpp.o
  [3/13] Building CXX object CMakeFiles/instaham_ml.dir/stages/feature_calculation.cpp.o
  [4/13] Building CXX object CMakeFiles/instaham_ml.dir/stages/segmentation.cpp.o
  [5/13] Building CXX object CMakeFiles/instaham_ml.dir/onnx_runner.cpp.o
  [6/13] Building CXX object CMakeFiles/instaham_ml.dir/stages/construction.cpp.o
  [7/13] Building CXX object CMakeFiles/instaham_ml.dir/util/sha256.cpp.o
  [8/13] Building CXX object CMakeFiles/instaham_ml.dir/classifier.cpp.o
  [9/13] Building CXX object CMakeFiles/instaham_ml.dir/instaham_ml.cpp.o
  [10/13] Building CXX object CMakeFiles/instaham_ml.dir/manifest.cpp.o
  [11/13] Building CXX object CMakeFiles/instaham_ml.dir/pipeline.cpp.o
  [12/13] Building CXX object CMakeFiles/instaham_ml.dir/util/image_io.cpp.o
  [13/13] Linking CXX shared library "C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\build\instaham_ml_ffi\intermediates\cxx\RelWithDebInfo\1y4l3g5f\obj\arm64-v8a\libinstaham_ml.so"
  FAILED: C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/build/instaham_ml_ffi/intermediates/cxx/RelWithDebInfo/1y4l3g5f/obj/arm64-v8a/libinstaham_ml.so 
  cmd.exe /C "cd . && C:\Android_Studio_Loc\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe --target=aarch64-none-linux-android24 --sysroot=C:/Android_Studio_Loc/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/sysroot -fPIC -g -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security  -std=c++17 -O2 -g -DNDEBUG  -Wl,--build-id=sha1 -Wl,--no-rosegment -Wl,--no-undefined-version -Wl,--fatal-warnings -Wl,--no-undefined -Qunused-arguments  -Wl,--gc-sections   "-Wl,--version-script=C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/instaham_ml.map" -Wl,--gc-sections -shared -Wl,-soname,libinstaham_ml.so -o "C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\build\instaham_ml_ffi\intermediates\cxx\RelWithDebInfo\1y4l3g5f\obj\arm64-v8a\libinstaham_ml.so" CMakeFiles/instaham_ml.dir/instaham_ml.cpp.o CMakeFiles/instaham_ml.dir/manifest.cpp.o CMakeFiles/instaham_ml.dir/onnx_runner.cpp.o CMakeFiles/instaham_ml.dir/classifier.cpp.o CMakeFiles/instaham_ml.dir/health_input.cpp.o CMakeFiles/instaham_ml.dir/pipeline.cpp.o CMakeFiles/instaham_ml.dir/stages/segmentation.cpp.o CMakeFiles/instaham_ml.dir/stages/construction.cpp.o CMakeFiles/instaham_ml.dir/stages/cutter.cpp.o CMakeFiles/instaham_ml.dir/stages/feature_calculation.cpp.o CMakeFiles/instaham_ml.dir/util/image_io.cpp.o CMakeFiles/instaham_ml.dir/util/sha256.cpp.o  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/onnxruntime/lib/android/arm64-v8a/libonnxruntime.so"  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_imgproc.a"  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a"  -latomic -lm && cd ."
  ld.lld: error: undefined symbol: __kmpc_global_thread_num
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_(cv::Range const&, cv::ParallelLoopBody const&, double)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: __kmpc_push_num_threads
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_(cv::Range const&, cv::ParallelLoopBody const&, double)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: __kmpc_fork_call
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_(cv::Range const&, cv::ParallelLoopBody const&, double)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: __kmpc_dispatch_init_4u
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_impl(cv::Range const&, cv::ParallelLoopBody const&, double) (.omp_outlined)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: __kmpc_dispatch_next_4u
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_impl(cv::Range const&, cv::ParallelLoopBody const&, double) (.omp_outlined)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv::hal::transpose(unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, int)
  >>> referenced by matrix_transform.cpp
  >>>               matrix_transform.cpp.o:(cv::transpose(cv::_InputArray const&, cv::_OutputArray const&)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: __android_log_print
  >>> referenced by system.cpp
  >>>               system.cpp.o:(cv::error(cv::Exception const&)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by logger.cpp
  >>>               logger.cpp.o:(cv::utils::logging::internal::writeLogMessage(cv::utils::logging::LogLevel, char const*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: __kmpc_dispatch_deinit
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_impl(cv::Range const&, cv::ParallelLoopBody const&, double) (.omp_outlined)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: omp_get_max_threads
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(_GLOBAL__sub_I_parallel.cpp) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv::hal::convertScale(unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, int, int, double, double)
  >>> referenced by convert.dispatch.cpp
  >>>               convert.dispatch.cpp.o:(cv::Mat::convertTo(cv::_OutputArray const&, int, double, double) const) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by convert.dispatch.cpp
  >>>               convert.dispatch.cpp.o:(cv::Mat::convertTo(cv::_OutputArray const&, int, double, double) const) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_add_u8
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add8u(unsigned char const*, unsigned long, unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add8u(unsigned char const*, unsigned long, unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_add_s8
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add8s(signed char const*, unsigned long, signed char const*, unsigned long, signed char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add8s(signed char const*, unsigned long, signed char const*, unsigned long, signed char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_add_u16
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add16u(unsigned short const*, unsigned long, unsigned short const*, unsigned long, unsigned short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add16u(unsigned short const*, unsigned long, unsigned short const*, unsigned long, unsigned short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_add_s16
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add16s(short const*, unsigned long, short const*, unsigned long, short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::add16s(short const*, unsigned long, short const*, unsigned long, short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_sub_u8
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub8u(unsigned char const*, unsigned long, unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub8u(unsigned char const*, unsigned long, unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_sub_s8
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub8s(signed char const*, unsigned long, signed char const*, unsigned long, signed char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub8s(signed char const*, unsigned long, signed char const*, unsigned long, signed char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_sub_u16
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub16u(unsigned short const*, unsigned long, unsigned short const*, unsigned long, unsigned short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub16u(unsigned short const*, unsigned long, unsigned short const*, unsigned long, unsigned short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv_saturating_sub_s16
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub16s(short const*, unsigned long, short const*, unsigned long, short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::sub16s(short const*, unsigned long, short const*, unsigned long, short*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: undefined symbol: kleidicv::hal::resize(int, unsigned char const*, unsigned long, int, int, unsigned char*, unsigned long, int, int, double, double, int)
  >>> referenced by resize.cpp
  >>>               resize.cpp.o:(cv::hal::resize(int, unsigned char const*, unsigned long, int, int, unsigned char*, unsigned long, int, int, double, double, int)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_imgproc.a

  ld.lld: error: undefined symbol: kleidicv_saturating_absdiff_u8
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::absdiff8u(unsigned char const*, unsigned long, unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a
  >>> referenced by arithm.dispatch.cpp
  >>>               arithm.dispatch.cpp.o:(cv::hal::absdiff8u(unsigned char const*, unsigned long, unsigned char const*, unsigned long, unsigned char*, unsigned long, int, int, void*)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/lib/android/arm64-v8a/libopencv_core.a

  ld.lld: error: too many errors emitted, stopping now (use --error-limit=0 to see all errors)
  clang++: error: linker command failed with exit code 1 (use -v to see invocation)
  ninja: build stopped: subcommand failed.

  C++ build system [build] failed while executing:
      @echo off
      "C:\\Android_Studio_Loc\\cmake\\3.22.1\\bin\\ninja.exe" ^
        -C ^
        "C:\\Users\\Adrian Jared Sido\\OneDrive\\Documents\\Instaham_Proj\\instaham\\packages\\instaham_ml_ffi\\android\\.cxx\\RelWithDebInfo\\1y4l3g5f\\arm64-v8a" ^
        instaham_ml
    from C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\packages\instaham_ml_ffi\android

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to generate a Build Scan (Powered by Develocity).
> Get more help at https://help.gradle.org.

BUILD FAILED in 41s
Running Gradle task 'assembleRelease'...                           42.8s
Gradle task assembleRelease failed with exit code 1
PS C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham> 