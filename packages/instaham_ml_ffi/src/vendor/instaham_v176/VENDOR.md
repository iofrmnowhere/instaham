# Vendor drop: instaham_v176 (V176/V144 cutter + Chen16 features + quality gates)

Source: `model_and_cutter/instaham_cpp_weight_runtime_v176_chen16/instaham_cpp_weight_runtime_v176_chen16/`
(gitignored, supplied by the user). Copied verbatim per `docs/plan-phase/2-native-cutter-chen16.md`
step 1. `PACKAGE_MANIFEST.json` in this directory is the vendor's file, byte-for-byte.

## What was copied

- `include/instaham/Common.hpp`, `include/instaham/MaskUtils.hpp`,
  `include/instaham/preprocess/JiDuan.hpp`
- `include/instaham/cutter/*.hpp` (7), `include/instaham/features/*.hpp` (19)
- `src/MaskUtils.cpp`, `src/preprocess/JiDuan.cpp`
- `src/features/*.cpp` (19), `src/cutter/*.cpp` (7)
- `quality_gates/truncation_gate/EdgeTruncationDetector.{hpp,cpp}`
- `quality_gates/posture_gate/PostureGate.{hpp,cpp}`

29 core `.cpp` sources + 2 quality-gate `.cpp` sources = 31 translation units, plus their
headers. (The plan's step list says "27 core sources" / "20 files" in the features count;
the vendor's own `features/` directory holds 19 `.cpp` files, not 20, and `src/MaskUtils.cpp`
plus `src/preprocess/JiDuan.cpp` bring the core total to 29, not 27. Recorded here as the
actual count rather than silently reconciled — the file list itself matches the plan
verbatim, only the arithmetic label attached to it was off.)

## What was NOT copied, and why

- `inference/YoloOnnx.{hpp,cpp}`, `model/XGBoostJsonPredictor.{hpp,cpp}`,
  `orchestrator/WeightPipelineOrchestrator.cpp`, `ffi/` — the app has its own segmentation
  stage, ONNX regressor path, pipeline order (`pipeline.cpp`), and C ABI. Taking these would
  duplicate `pipeline.cpp`, which AGENTS.md forbids and the vendor README calls the one file
  that owns execution order.
- `quality_gates/*/​*_ffi.{h,cpp,dart}` — the app has one consolidated native library and one
  C ABI; `README_AI_INTEGRATION.md` section 9 permits folding the gate sources into an
  existing native target so long as module boundaries hold.
- `models/`, `flutter/`, `tests/` — not part of the native port.

## Edits made to compile

- `src/cutter/ShoulderSelectorV176.cpp`, line 14: `auto cr=crosses(d),all=maxima(b);` split
  into two statements (`auto cr=crosses(d);auto all=maxima(b);`). A single `auto`
  declaration with multiple declarators must deduce the *same* type for every declarator;
  `crosses()` returns `std::vector<Cross>` and `maxima()` returns `std::vector<double>`, so
  this failed to compile under NDK r28's clang (`'auto' deduced as 'std::vector<Cross>' ...
  and deduced as 'std::vector<double>' ...`). Confirms `VALIDATION.md`'s own statement that
  this package has never been compiled -- this is not a cross-compiler quirk, it is
  ill-formed C++ that no conforming compiler accepts. No behavior change; purely a
  declaration-syntax fix.

## body_curve parity patch (phase 2, applied after the initial copy above)

`src/features/BodyCurve.cpp` was replaced wholesale with the version from
`model_and_cutter/instaham_weight_runtime_BODYCURVE_FIXED/src/features/BodyCurve.cpp`
(vendor-supplied fix, see that package's `PATCH_NOTES_BODY_CURVE.md`). The original
`skeletonize()` used the textbook 1984 Zhang-Suen A/B/m1/m2 algebraic removal conditions;
those conditions are geometrically correct but are **not** what
`skimage.morphology.skeletonize(..., method='zhang')` actually computes — skimage's
`method='zhang'` is a compiled 256-entry neighborhood classification LUT that does not
reduce to the A/B/m1/m2 form, so the two produced different skeletons on real masks despite
sharing the "Zhang-Suen" name. This was the entire cause of the `body_curve` feature-port
gate's 17/20-mask mismatch recorded below in Results; the 1px zero-border pad the original
code carried was already correct and is unchanged by this patch.

The replacement reproduces skimage 0.26.0's exact LUT (`kSkimage026ZhangLut`, bit order
`NW,N,NE,E,SE,S,SW,W = 1,2,4,8,16,32,64,128`; pass 1 deletes classes 1 and 3, pass 2 deletes
classes 2 and 3, each subpass reading the pre-subpass skeleton and committing deletions only
after a full scan). Nothing after skeleton generation changed — endpoint detection, centroid,
farthest-pair selection, PCA fallback, and the angle formula are byte-identical to the
pre-patch file. Verified against `skimage.morphology.skeletonize` on the same 20 `MASK_3394`
masks the feature-port gate uses: 0 XOR skeleton-pixel differences and 0.000000% `body_curve`
relative error on all 20 (Python transcription of the LUT/loop, not yet the rebuilt C++ CLI
— see `docs/plan-phase/2-native-cutter-chen16.md` Results for the full account).

`ShoulderSelectorV176.cpp` from the same `BODYCURVE_FIXED` drop was **not** taken — it
reverts the `auto cr=…,all=…;` compile fix above back to the ill-formed declaration.

## Per-file sha256 (of the copy in this tree, at copy time)

```
a0f0a95bf5eb5a910ecb33b387f58a8e302c5bdc181124ded074a97f2ebc2e9b  include/instaham/Common.hpp
311e1e310f7e7646bfbdc4e433fe24e326f7d23cd4c213865fab5c9de38ea06f  include/instaham/cutter/Break1Fit.hpp
2e60cf47e2622f0af3ae922d9c48cf5fb89f090df1fecf7cef823aed827a51fe  include/instaham/cutter/CircleCutterV144.hpp
b9045c102954ce5e657c5ca4b9324c3cfb9c148a390771c7d74379e88988b1b3  include/instaham/cutter/CutterTypes.hpp
1ab4cbfdbe2d9557fc89931e07f930393ba1d635dd222e6342d3369e41a95537  include/instaham/cutter/OutlineBuilder.hpp
fb4bddb6218e09eb00ab69565be8537af741a7973e47c98699b5af6884ed7159  include/instaham/cutter/SelleFilter.hpp
8342b601080a1f6af2af7e55ff873d5fbcd6ec8bc1c1a3d7fac2c8045eb7d502  include/instaham/cutter/ShoulderSelectorV176.hpp
93128a540f18697a9fd67c8107610b4213b9948ca92a5b3a2986808f422b93c6  include/instaham/cutter/ShrinkingBall.hpp
55e5db0824bc568de1b8a0335bec66ae6fed5b5326d2c4094e68a4c8ad8b7d16  include/instaham/cutter/TerminalGeometry.hpp
29be1fdb4ad7654d7caf9f8df6a8591f787d9bc1f63926d933e128ee833ac32d  include/instaham/features/BodyCurve.hpp
c7c66e000dd61e890b4effbcfee258e9bd83e55ceddc06377fe087b9fa7953fc  include/instaham/features/CenterCrossingAxesWork.hpp
1c0d480f08d2d4b098409741e804cdc0a4e7f055755d047e619f7ce24b0ef4a0  include/instaham/features/Chen16Vector.hpp
5bd1b5d2f3d229b60cea9c7edd9b91f39bb2519ae7ab6436b548d2a6315c96fb  include/instaham/features/ConvexHullArea.hpp
fd3153049abbdeca0eb9e8025ead55559999a0840c7a2055b595edf09eb18105  include/instaham/features/Difference.hpp
8ff6b13527dd9b50e1cd19062c9e74d7cb297562af3f4b76a44dc33522e6bc48  include/instaham/features/DifMask.hpp
e231a154fa63bb1bb6e2baedc3137f665ac6d06aa2fb7b6315985a815bd50115  include/instaham/features/Hu1.hpp
9bfa0058dd8bd4df78bb08c214b804efc147bdbb3bb8ff2b0b5bf0a4d7a55a17  include/instaham/features/Hu2.hpp
26a42f04567d85a3eac901f0e8d299f653c7e08d3abf92de264eb4420ec0237b  include/instaham/features/Hu3.hpp
f10d4895842a19f46af0b0a4479813e0ca0436c508572d1d7cf23ba5ed4159a1  include/instaham/features/Hu4.hpp
24dd78ad901d1612f7ed3f8efe922bd0b80c52b3613eb59e30b66c414b8d04c1  include/instaham/features/Hu5.hpp
2e8c2bdbf0d7df07d5e9c12eb6fee52728b8d1ba0ecfdc5ca8d03afdb5fd7087  include/instaham/features/Hu6.hpp
bd1ae27c102831beef67ef4ca0f712b2f0b17af88e97523a02f309ddf863e90b  include/instaham/features/Hu7.hpp
a50c06fc2edd3260472d446a58acc6d2d0602f7bae79491251a7768fc847d207  include/instaham/features/HuMomentsWork.hpp
33ef72483e0663641af362cd296c4a96455fb99ddfef635f491602b7d9dd7748  include/instaham/features/Longest.hpp
83a5ce8e26a00cf656df3d3ca8605b480b27b2eca740a1ce78f7d8a0a40b43e4  include/instaham/features/MaskArea.hpp
3e7e33fb7ed5d4bd063c47f00d9f96106af84cc7dc0806a5875311b13b77b789  include/instaham/features/OutlineCurve.hpp
473bebd176c7caa8c3e55fb192f14582c3d6e09150af343891a26a7af6c9262c  include/instaham/features/Perimeter.hpp
0ad30ab47b4d48347273fe3d52e31150451cda2900ad3baf9decdc2110d1ad8d  include/instaham/features/Shortest.hpp
224c6db021f4e70204f8b5201e879088d4415f616241f92e32105ad15b6afd57  include/instaham/MaskUtils.hpp
7142704bec44ccc4e9d2b5aace46b7516779b99ec635ce1d9cf144f42ab4f27c  include/instaham/preprocess/JiDuan.hpp
5d878413111b179d09d9e040e89af470662b71b65c7a704d86c4d23ba22e0225  quality_gates/posture_gate/PostureGate.cpp
5fee69cc7eed88621dfa71e342ee82eb112b3120a23a8bf931a1de8db43e0b68  quality_gates/posture_gate/PostureGate.hpp
36003878ff0d2742e56367694ec72d934cb2a12368cae0d484b457f67efceda4  quality_gates/truncation_gate/EdgeTruncationDetector.cpp
6d3e52eeccbdb4aea1b739aa14679256ff8d7227cbcaee94afc42d1af80408c5  quality_gates/truncation_gate/EdgeTruncationDetector.hpp
b29adac840be98ce423f8b1b8a20c1570e05dbabe02278f50e490bae7eb6cd6d  src/cutter/Break1Fit.cpp
381e12afe9965ac7cf0a2db4fe1b97a4af3b297dd58a1cd8e85c589da96e2079  src/cutter/CircleCutterV144.cpp
4bda236bb5b7f7fcdf9112da5a7ee076f53c3f97a9738bf1fd66df2226355681  src/cutter/OutlineBuilder.cpp
bdc01beecd73845ba85cdd73703479c955502594e2f85911443f0d9d6995a228  src/cutter/SelleFilter.cpp
3545170aec4380232ae830d60841b977b6402c1aba9c5fa999da1d6aaad047f4  src/cutter/ShoulderSelectorV176.cpp
fa873f6dd92d25bb59907ffbfc7216181d40bb51ed2787ce32a8bbfe24c1f277  src/cutter/ShrinkingBall.cpp
6dd15ed3c057f324eb9579bf351bbd85d1d6154abf9d814d3b987dc9d32787d9  src/cutter/TerminalGeometry.cpp
a2d8f916d5d5e5e9c7b0a30b88ff236a02a0704dc0d65f8dbd8a62727708d35c  src/features/BodyCurve.cpp  (post-patch, see "body_curve parity patch" above; pre-patch was e9d9d8103fe8ced903eb034a2357ba9373fbfe657fc9533470b1487bcf04218d)
20e711d34143e3138ca0d3ae8e295681439904124eea13633f3f9d4a9e1cec42  src/features/CenterCrossingAxesWork.cpp
3a9f5ca0f5d44ac682fa32a78edbf13e5b4725d4345661114587bd165fba5660  src/features/Chen16Vector.cpp
dfb508b79218848b852569ab444382e5294128e735dccfd27b37d9407f7c69f3  src/features/ConvexHullArea.cpp
c6282ed62ccf9538f8c306730d2e73308fc730101d8049a72a887f4d173ae390  src/features/Difference.cpp
ea17a08148154d209bfd16955963cf00f7490f2668e48fb515c237c22d14e01c  src/features/DifMask.cpp
9cb463247636686816143498049e97098b0c600b80e859b0d24e411f094ecfff  src/features/Hu1.cpp
4ccd0dd18327ddb96720b5fe0d4aaa41c35bc5b3fb65b3df613646150f90c12f  src/features/Hu2.cpp
1ffdb7268b4f5b3d72b4ca069b7d8ac7c4ddf1e75337afce957069eec9cb2dde  src/features/Hu3.cpp
a10cbfb899141f6d0f71b879650612bec80fdde9e32637dacade1c79d92d5341  src/features/Hu4.cpp
2cb66afef45f82a4fb29a155e29b446309c30a7d0c01dde28f10e576376bb3c8  src/features/Hu5.cpp
f6cdda9504c6c97baed13a1a8a9cc86abbd6d0233f1e5acd4afc68fafdab3e7a  src/features/Hu6.cpp
98439f6713fcd25dfd65748d5e3a0cdf16df97b9ee6dc17a877ac66427842774  src/features/Hu7.cpp
65e223da442cfd6061679485e90d22bb7ed8c3013b96628c91b621db74a7ccda  src/features/HuMomentsWork.cpp
b6690bd5c85479c9e3159e58b02a4d9d89f81409d6cf09afa4106144716bb2d6  src/features/Longest.cpp
901399ddc439953e0cb03a601cfbfd60084aad7c1cf06301901baa766988af53  src/features/MaskArea.cpp
c6230559ee542c948147b210e2ebd89d05a746bef3153a2d4d00cb6944c37b20  src/features/OutlineCurve.cpp
5f719b98b1295013b17774bd04a50efa73beabe69bf03724bb718e223ec4c438  src/features/Perimeter.cpp
dc6575355aae65a0eceeb49638fae80dcce8456531c75112eceda5e4fb886a11  src/features/Shortest.cpp
72140b3c4dd2f81325bf5384234a49a637d2aeb56d50af2db0c89c114c010007  src/MaskUtils.cpp
2c1f9204823ddd620a1f39f193580ae300719e19ef058fdeb0b881b49099ff40  src/preprocess/JiDuan.cpp
```

Regenerate with (from this directory): `find . -type f \( -name "*.cpp" -o -name "*.hpp" \) | sort | xargs sha256sum`
