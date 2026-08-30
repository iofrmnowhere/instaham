# Fixing the `libinstaham_ml.so` link failure — round 3

**Status:** proposed, not applied. Written 2026-08-30 after the third `flutter build apk` attempt
(`build_error2.md`). Supersedes the previous revision of this file, whose fix **worked** — see §1.

---

## 1. Round 2 succeeded; this is a different, smaller failure

The previous plan (replace the hand-wired `IMPORTED` OpenCV targets with `find_package(OpenCV)`
against opencv-mobile's own ABI-specific config package, and stop flattening the SDK tree in
`fetch_deps.sh`) was applied and did what it claimed. Evidence from the new link line in
`build_error2.md`: it now carries everything the old one was missing —

```
libopencv_imgproc.a  libopencv_core.a  -fopenmp  -static-openmp  -ldl  -lm  -llog
libkleidicv_hal.a  libkleidicv_thread.a  libkleidicv.a
```

The ~20 undefined symbols from round 2 collapsed to **exactly one**:

```
ld.lld: error: undefined symbol: __kmpc_dispatch_deinit
>>> referenced by parallel.cpp
>>>               parallel.cpp.o:(cv::parallel_for_impl(...) (.omp_outlined))
>>>               in archive .../libopencv_core.a
```

KleidiCV, `-llog`, `dl`, `m`, and six of the seven OpenMP entry points all resolved. This is not a
CMake wiring problem any more.

## 2. Root cause: opencv-mobile was built with a newer toolchain than the local NDK

`__kmpc_dispatch_deinit` is an LLVM OpenMP runtime entry point that **does not exist in the OpenMP
runtime shipped with NDK 28.2**, but **is emitted by the compiler that built opencv-mobile**.

### 2.1 The NDK side — verified on this machine

`android/app/build.gradle.kts` and `packages/instaham_ml_ffi/android/build.gradle.kts` both pin
`ndkVersion = "28.2.13676358"`, whose toolchain is LLVM 19. Its OpenMP runtime lives at
`toolchains/llvm/prebuilt/windows-x86_64/lib/clang/19/lib/linux/aarch64/libomp.{a,so}`.
`llvm-nm --defined-only` over `libomp.a` lists every dispatch entry point **except** the one we
need:

```
__kmpc_dispatch_init_4  __kmpc_dispatch_init_4u  __kmpc_dispatch_init_8  __kmpc_dispatch_init_8u
__kmpc_dispatch_next_4  __kmpc_dispatch_next_4u  __kmpc_dispatch_next_8  __kmpc_dispatch_next_8u
__kmpc_dispatch_fini_4  __kmpc_dispatch_fini_4u  __kmpc_dispatch_fini_8  __kmpc_dispatch_fini_8u
```

There is `dispatch_fini`, but no `dispatch_deinit`. `libomp.so` does not export it either, so
dropping `-static-openmp` in favour of a dynamic link changes nothing. NDK **27.0.12077973** — the
only other NDK installed here — is LLVM 18 and also lacks it, so downgrading is not an escape.

### 2.2 The opencv-mobile side — verified from the shipped archive

Extracting `parallel.cpp.o` out of `sdk/native/staticlibs/arm64-v8a/libopencv_core.a` and dumping
its `.comment` section gives the compiler that produced it, verbatim:

```
Android (13989888, +pgo, +bolt, +lto, +mlgo, based on r563880c) clang version 21.0.0
(https://android.googlesource.com/toolchain/llvm-project 5e96669f06077099aa41290cdb4c5e6fa0f59349)
```

The NDK r29 changelog states that **r29 updated LLVM to `clang-r563880c`** — the same toolchain
string. So `opencv-mobile-4.13.0-android.zip` (release tag `v36`, the version
`scripts/fetch_deps.sh` pins) was built with the **NDK r29 / clang 21** toolchain, while we compile
and link with **NDK r28.2 / clang 19**.

Clang 21 emits an `__kmpc_dispatch_deinit` call to close out a dynamically-scheduled worksharing
loop; clang 19's runtime predates that call. That single generational gap is the entire failure.

### 2.3 It affects all three ABIs, not just arm64-v8a

Scanning the undefined symbols of `libopencv_core.a` + `libopencv_imgproc.a` per ABI gives an
identical OpenMP set for every one:

| ABI | undefined OpenMP symbols |
|---|---|
| `arm64-v8a` | `__kmpc_dispatch_deinit`, `__kmpc_dispatch_init_4u`, `__kmpc_dispatch_next_4u`, `__kmpc_fork_call`, `__kmpc_global_thread_num`, `__kmpc_push_num_threads`, `omp_get_max_threads`, `omp_get_thread_num` |
| `armeabi-v7a` | *(identical)* |
| `x86_64` | *(identical)* |

Only `__kmpc_dispatch_deinit` is unsatisfiable. Gradle stops at the first failing ABI, so
`armeabi-v7a` and `x86_64` have not been reached yet — but they will fail identically.

### 2.4 Nothing else is missing

A full symbol-closure check was run for `arm64-v8a`: all 891 undefined symbols of the two archives
we link were diffed against the union of the OpenCV archives, the KleidiCV archives, NDK 28.2's
`libomp.a`, and the NDK sysroot libraries. Everything resolved except `__kmpc_dispatch_deinit` and
ordinary libc/libm/compiler-rt names (`memcpy`, `pow`, `__stack_chk_fail`, …) that the real link
line satisfies via the sysroot — consistent with `ld.lld` reporting one error and no others.

**In particular, there is no libc++ ABI drift.** The clang-21-built archives link cleanly against
NDK 28.2's `libc++_shared.so`. The previous revision of this file flagged possible `std::__ndk1`
symbol mismatches as "the next problem"; that concern is now measured and closed.

---

## 3. The fix

### Option A — weak no-op shim (recommended)

`__kmpc_dispatch_deinit` is **an empty function in LLVM itself**. From
`openmp/runtime/src/kmp_dispatch.cpp` at tag `llvmorg-21.1.0`, line 3017, verbatim:

```cpp
void __kmpc_dispatch_deinit(ident_t *loc, kmp_int32 gtid) {}
```

It is a forward-compatibility hook with no body in the very runtime opencv-mobile was compiled
against. Supplying our own empty definition is therefore not an approximation of the real
behaviour — it *is* the real behaviour, byte for byte.

**A1. New file `packages/instaham_ml_ffi/src/util/openmp_compat.cpp`:**

```cpp
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
```

**A2. `packages/instaham_ml_ffi/src/CMakeLists.txt` — add one line inside the existing
`if(INSTAHAM_ML_WITH_OPENCV)` block**, right after the `target_link_libraries(...)` call (line 101):

```cmake
  # NDK 28.2's libomp (LLVM 19) predates __kmpc_dispatch_deinit, which opencv-mobile's
  # NDK-r29-built libopencv_core.a references from cv::parallel_for_impl. Weak no-op shim,
  # inert once the NDK is bumped past r29. build_fix.md section 3, Option A.
  target_sources(instaham_ml PRIVATE util/openmp_compat.cpp)
```

Attaching it via `target_sources` inside this block — rather than adding it to
`INSTAHAM_ML_SOURCES` — keeps it out of the host `ctest` build, which does not link OpenCV and
therefore has no such reference.

**A3. Nothing else changes.** No `fetch_deps.sh` change, no Gradle change, no new download.

**Why the shim is safe against the version script.** `src/instaham_ml.map` is
`global: instaham_ml_*; local: *;`, and the target already sets `CXX_VISIBILITY_PRESET hidden`, so
the shim never appears in the `.so`'s dynamic symbol table. `-Wl,--no-undefined-version` only
errors on names *listed* in the version script that do not exist, so it is unaffected.
`--gc-sections` keeps the function because `parallel.cpp.o` references it.

**Residual risk, stated plainly.** This makes clang-21-compiled OpenMP object code call into
clang-19's OpenMP runtime. The `__kmpc_dispatch_init_4u` / `__kmpc_dispatch_next_4u` /
`__kmpc_fork_call` contracts are long-stable and unchanged between LLVM 19 and 21, and
`dispatch_deinit` is a no-op in both worlds (absent in 19, empty in 21), so the mixed pairing is
sound for these entry points. It is nevertheless a *mixed* pairing, which Option B removes.

### Option B — bump the NDK to r29 (the alignment fix)

Match the toolchain opencv-mobile was built with, and the mismatch stops existing rather than being
papered over.

```
sdkmanager "ndk;29.0.14206865"
```

`29.0.14206865` is the r29 **stable** release and is listed as available by the local
`sdkmanager --list` (rc1–rc4, and r30 rc1–rc3, are also listed; take stable). Then update **both**
pins, which must stay in agreement:

- `packages/instaham_ml_ffi/android/build.gradle.kts:19` — `ndkVersion = "29.0.14206865"`
- `android/app/build.gradle.kts:13` — `ndkVersion = "29.0.14206865"`

**Cost and risk.** A multi-gigabyte download, and it swaps the toolchain for *everything* native in
the project — our twelve translation units, `libc++_shared.so`, and the linker — to chase one empty
function. ONNX Runtime 1.17.1 is a prebuilt `.so` and is unaffected. `minSdk = 24` is comfortably
above r29's floor. Still, the last two rounds each ended in an unforeseen failure, and a
whole-toolchain swap is the change most likely to produce a third.

**Option A and Option B compose.** The shim's `weak` attribute means that if B is done later,
`libomp.a`'s strong definition takes precedence and no cleanup is required. Landing A now does not
foreclose B.

### Option C — pin an older opencv-mobile (not recommended)

An opencv-mobile release built with NDK ≤ r28 would not emit the call. But the required release tag
is unknown without bisecting their download artifacts, it means giving up 4.13.0, and it trades a
measured problem for an unmeasured one. Recorded for completeness only.

---

## 4. Verification

1. `flutter build apk`. The link line already carries `-Wl,--no-undefined -Wl,--fatal-warnings`, so
   "it linked" remains a real signal rather than a deferred runtime `dlopen` crash.
2. Confirm **all three** ABIs link, not just `arm64-v8a`. Per §2.3 the other two carry the identical
   unresolved symbol and have never been reached; a fix that only cleared arm64 would fail
   immediately afterwards.
3. `llvm-nm -D --undefined-only libinstaham_ml.so | grep -E 'kmpc|kleidicv|android_log'` → expect
   empty.
4. `llvm-nm -D --defined-only libinstaham_ml.so` → expect only `instaham_ml_*`; the version script
   should have localised the shim along with everything else.
5. Install and run one scan. Expected: view + health + segmentation + mask work; **weight still
   reads "Unavailable"** (`cutter_identity_stub`) — correct per `ML_implementation_plan.md`
   section 3.4, not a regression.

## 5. What this plan does not claim

- **It does not make the native code correct, only linkable.** `stages/construction.cpp` and
  `stages/feature_calculation.cpp` have still never been executed. Gate B (C++ vs the Python
  reference, `ML_implementation_plan.md` section 10) has never run, and there is still no fixture
  corpus to run it against (section 11.2). A mask that decodes to the wrong shape will link and
  install perfectly.
- **It does not verify OpenMP behaviour at runtime.** The shim is argued correct from upstream
  source, and the surrounding entry points are argued stable, but no threaded OpenCV call
  (`morphologyEx`, `resize`, `findContours`) has been executed on-device under this mixed runtime.
  If a hang or a wrong result appears specifically inside a `cv::parallel_for_` body, Option B is
  the answer, not further shimming.
- **APK size is still unmeasured.** Section 11.1 estimated 3–6 MB per ABI for OpenCV; that estimate
  predates knowing KleidiCV is linked on arm64 and remains unverified.

---

## Plan rating: 9 / 10

**Pros**

- **The diagnosis is measured, not inferred.** The missing symbol was confirmed absent from the
  actual `libomp.a` on this machine; the offending compiler was read out of the shipped object's
  `.comment` section; the `clang-r563880c` string was matched against the published NDK r29
  changelog; and the fix's correctness comes from upstream's own source line, quoted exactly. None
  of the three chained claims rests on reading the error text.
- **The blast radius shrank to one file.** Round 2 was a dependency-graph problem spanning
  `fetch_deps.sh` and `CMakeLists.txt`; this is one new source file and one `target_sources` line.
- **The two options are complementary, not exclusive.** The `weak` attribute means Option A cannot
  block Option B later, so choosing the cheap fix now costs nothing if the principled one is wanted
  afterwards.
- **The "next problem" from the last round was closed rather than inherited.** The previous revision
  named libc++ ABI drift as a likely follow-on failure; the symbol-closure check in §2.4 shows there
  is none.
- **It catches the ABI trap again.** The log names only `arm64-v8a`; the per-ABI scan shows all
  three are equally broken.

**Cons**

- **It is still an unverified fix.** No build ran here. Three rounds, three failures not predicted
  in advance; a fourth remains possible.
- **Option A knowingly mixes toolchain generations.** The argument that this is safe rests on the
  stability of three OpenMP entry points across LLVM 19→21, reasoned from their contracts rather
  than tested. Option B is the honest fix and is deliberately not the recommendation, on cost
  grounds.
- **Defining a reserved runtime symbol is a maintenance hazard.** `__kmpc_*` belongs to libomp; a
  future opencv-mobile bump could reference a *different* missing entry point, and the same
  workaround would not obviously generalise — at which point Option B becomes mandatory anyway.
- **It still does nothing about the real open risk**, which is correctness, not linkage: mask
  decode, unletterbox arithmetic, and five-feature extraction remain untested against the Python
  reference. Getting the APK to build makes that gap testable, not smaller.
