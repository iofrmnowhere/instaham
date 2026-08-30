PS C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham> flutter build apk

FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':instaham_ml_ffi:buildCMakeRelWithDebInfo[arm64-v8a]'.
> com.android.ide.common.process.ProcessException: ninja: Entering directory `C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\packages\instaham_ml_ffi\android\.cxx\RelWithDebInfo\1y4l3g5f\arm64-v8a'
  [1/1] Linking CXX shared library "C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\build\instaham_ml_ffi\intermediates\cxx\RelWithDebInfo\1y4l3g5f\obj\arm64-v8a\libinstaham_ml.so"
  FAILED: C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/build/instaham_ml_ffi/intermediates/cxx/RelWithDebInfo/1y4l3g5f/obj/arm64-v8a/libinstaham_ml.so 
  cmd.exe /C "cd . && C:\Android_Studio_Loc\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe --target=aarch64-none-linux-android24 --sysroot=C:/Android_Studio_Loc/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/sysroot -fPIC -g -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security  -std=c++17 -O2 -g -DNDEBUG  -Wl,--build-id=sha1 -Wl,--no-rosegment -Wl,--no-undefined-version -Wl,--fatal-warnings -Wl,--no-undefined -Qunused-arguments  -Wl,--gc-sections   "-Wl,--version-script=C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/instaham_ml.map" -Wl,--gc-sections -shared -Wl,-soname,libinstaham_ml.so -o "C:\Users\Adrian Jared Sido\OneDrive\Documents\Instaham_Proj\instaham\build\instaham_ml_ffi\intermediates\cxx\RelWithDebInfo\1y4l3g5f\obj\arm64-v8a\libinstaham_ml.so" CMakeFiles/instaham_ml.dir/instaham_ml.cpp.o CMakeFiles/instaham_ml.dir/manifest.cpp.o CMakeFiles/instaham_ml.dir/onnx_runner.cpp.o CMakeFiles/instaham_ml.dir/classifier.cpp.o CMakeFiles/instaham_ml.dir/health_input.cpp.o CMakeFiles/instaham_ml.dir/pipeline.cpp.o CMakeFiles/instaham_ml.dir/stages/segmentation.cpp.o CMakeFiles/instaham_ml.dir/stages/construction.cpp.o CMakeFiles/instaham_ml.dir/stages/cutter.cpp.o CMakeFiles/instaham_ml.dir/stages/feature_calculation.cpp.o CMakeFiles/instaham_ml.dir/util/image_io.cpp.o CMakeFiles/instaham_ml.dir/util/sha256.cpp.o  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/onnxruntime/lib/android/arm64-v8a/libonnxruntime.so"  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/sdk/native/staticlibs/arm64-v8a/libopencv_imgproc.a"  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/sdk/native/staticlibs/arm64-v8a/libopencv_core.a"  -fopenmp  -static-openmp  -ldl  -lm  -llog  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/sdk/native/3rdparty/libs/arm64-v8a/libkleidicv_hal.a"  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/sdk/native/3rdparty/libs/arm64-v8a/libkleidicv_thread.a"  "C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/sdk/native/3rdparty/libs/arm64-v8a/libkleidicv.a"  -latomic -lm && cd ."
  ld.lld: error: undefined symbol: __kmpc_dispatch_deinit
  >>> referenced by parallel.cpp
  >>>               parallel.cpp.o:(cv::parallel_for_impl(cv::Range const&, cv::ParallelLoopBody const&, double) (.omp_outlined)) in archive C:/Users/Adrian Jared Sido/OneDrive/Documents/Instaham_Proj/instaham/packages/instaham_ml_ffi/src/third_party/opencv/sdk/native/staticlibs/arm64-v8a/libopencv_core.a
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

BUILD FAILED in 1m 5s
Running Gradle task 'assembleRelease'...                           66.5s
Gradle task assembleRelease failed with exit code 1