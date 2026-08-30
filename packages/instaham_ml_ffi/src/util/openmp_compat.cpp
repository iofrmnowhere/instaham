// opencv-mobile 4.13.0's prebuilt archives were compiled with the NDK r29 toolchain
// (clang 21, "based on r563880c" per their .comment section), whose codegen closes a
// dynamically-scheduled OpenMP worksharing loop with a call to __kmpc_dispatch_deinit.
// We build with NDK 28.2 (clang 19), whose libomp predates that entry point, so
// cv::parallel_for_impl's .omp_outlined region leaves it undefined at link time.
//
// Upstream's own definition is empty -- llvm-project llvmorg-21.1.0,
// openmp/runtime/src/kmp_dispatch.cpp:3017:
//
//     void __kmpc_dispatch_deinit(ident_t *loc, kmp_int32 gtid) {}
//
// so this shim is behaviourally identical, not a stub. It is declared weak: if the NDK is
// ever bumped to r29+, libomp.a's own (strong) definition simply wins and this becomes
// dead weight rather than a duplicate-symbol error. See build_fix.md section 2.
//
// Signature note: the parameters are (ident_t*, kmp_int32) = (pointer, int32). We do not
// have <kmp.h>, but the symbol has C linkage and no name mangling, and void*/int are ABI-
// identical to those types on every ABI we build, so the declaration below is compatible.
extern "C" __attribute__((weak, visibility("hidden")))
void __kmpc_dispatch_deinit(void* /*loc*/, int /*gtid*/) {}
