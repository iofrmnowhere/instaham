// Was a Groovy-syntax `build.gradle` using Kotlin-DSL-only syntax (`apply(plugin = ...)`,
// `classpath(...)`) -- that never actually parsed as valid Groovy; it happened to be
// tolerated only because AGP 9 wasn't in the picture yet. Renamed to .kts and rewritten to
// use the plugins{} DSL (matching android/app/build.gradle.kts and the root
// settings.gradle.kts's centralized plugin management) instead of the legacy per-module
// buildscript{} classpath + apply(plugin = ...) pattern, which AGP 9 rejects outright
// ("Could not set unknown property 'plugin'").
plugins {
    id("com.android.library")
}

group = "com.instaham.instaham_ml_ffi"
version = "0.0.1"

android {
    namespace = "com.instaham.instaham_ml_ffi"
    compileSdk = 34
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 24  // ONNX Runtime floor
        ndk {
            // Only ABIs onnxruntime-android was fetched for (scripts/fetch_deps.sh).
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DINSTAHAM_ML_WITH_ORT=ON",      // slice 3: view + health classifiers
                    "-DINSTAHAM_ML_WITH_OPENCV=OFF",  // preprocessing done in Dart this pass; see AGENTS.md task note
                )
                cppFlags += "-std=c++17"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../src/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // libonnxruntime.so is a prebuilt IMPORTED target (fetched by fetch_deps.sh, not built
    // by CMake), so it is not gathered into the APK automatically -- bundle it explicitly.
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("../src/third_party/onnxruntime/lib/android")
        }
    }
}
