# Libraries used by the INSTAHAM app

Scope: the Flutter app in `lib/`, its in-repo FFI plugin in `packages/instaham_ml_ffi/`, and
the native C++ libraries that plugin links. `instaham_ui/` is excluded — AGENTS.md marks it a
read-only Next.js visual reference, not part of the product.

Versions are the resolved versions from `pubspec.lock`, not the caret ranges in
`pubspec.yaml`. Every "how it is used" entry below was checked against the source rather than
inferred from the package's purpose.

## Runtime dependencies (Dart / Flutter)

### `go_router` 14.8.1

**What it is.** Declarative routing for Flutter, built on the Router API. Routes are described
as a tree of paths rather than imperative `Navigator.push` calls, and navigation happens
through URL-like strings.

**How it is used.** The single source of routing truth is `lib/core/router/app_router.dart`,
which builds one static `GoRouter` holding roughly fourteen `GoRoute` entries covering capture,
guidance, results, reject, records, analytics and privacy. It is the most widely imported
package in the codebase — fourteen files — because every screen that navigates calls
`context.go` or `context.push` rather than touching `Navigator` directly. `AppBottomNav`
(`lib/core/router/widgets/app_bottom_nav.dart`) drives tab switching through the same router.

### `drift` 2.31.0

**What it is.** A reactive persistence library for Dart that generates type-safe SQL query
code from Dart table definitions. It is the ORM layer over SQLite.

**How it is used.** Drift is the local source of truth for all app data, per AGENTS.md's
database rules. `lib/core/database/app_database.dart` declares the `@DriftDatabase` with nine
tables — `Pigs`, `ScanRecords`, `ReferenceAnnotations`, `WeightResults`, `HealthResults`,
`PipelineEvents`, `PrivacyPreferences`, `SyncOutboxEntries`, `CustomReferences` — and three
DAOs (`AnalyticsDao`, `RecordsDao`, `CustomReferencesDao`). The database is at
`schemaVersion` 4 with an explicit stepwise `MigrationStrategy`: version 2 added the custom
references table, version 3 added measurement mode and camera height columns, version 4 added
the 16-feature weight vector blob, its family discriminator, and two cutter telemetry columns.
`beforeOpen` enables SQLite foreign keys and seeds privacy defaults. Generated output lives in
`app_database.g.dart`, which is never hand-edited.

### `drift_flutter` 0.2.8

**What it is.** The Flutter integration layer for Drift — it supplies the platform-appropriate
`QueryExecutor` so the same database code runs on mobile, desktop and web.

**How it is used.** Exactly one call, `driftDatabase(...)` in `app_database.dart:229`, which
names the database `instaham`, points the native executor at
`getApplicationSupportDirectory`, and declares the web `sqlite3.wasm` / `drift_worker.dart.js`
pair. It pulls in `sqlite3` 2.9.4 and `sqlite3_flutter_libs` 0.5.42 transitively, which are
what actually ship the SQLite engine into the APK.

### `camera` 0.12.0+2

**What it is.** The Flutter team's plugin for direct camera access — device enumeration, a
live preview texture, and still capture.

**How it is used.** Only in `lib/features/capture/presentation/screens/capture_screen.dart`,
which is the sole screen that owns hardware. It calls `availableCameras()` to enumerate
devices, constructs a `CameraController` at `ResolutionPreset.high`, renders the live preview,
and calls `takePicture()` to produce the `XFile` that the rest of the capture flow consumes.
This is the front door of the whole pipeline: everything the models see originates here.

### `image` 4.9.1

**What it is.** A pure-Dart image codec and processing library — decode, encode, resize,
rotate, and EXIF handling, with no native dependency.

**How it is used.** In `lib/core/utils/image_service.dart`, and it implements one of the
project's hard correctness rules. AGENTS.md rule 5 requires EXIF orientation to be corrected
before any model receives an image; this is where that happens. The service calls
`img.decodeImage` on the raw bytes, `img.bakeOrientation` to physically rotate pixels so the
EXIF orientation flag becomes redundant, then `img.encodeJpg(quality: 92)` to write the
upright result. Because orientation is baked before anything downstream runs, reference-point
coordinates marked later stay valid against the stored file.

### `image_picker` 1.1.2 (resolved 1.2.3)

**What it is.** The Flutter team's plugin for selecting existing photos from the device
gallery or launching the system camera UI.

**How it is used.** A single static `ImagePicker` instance in `image_service.dart:10`,
providing the gallery-import path as an alternative to live capture. Both routes converge on
the same `XFile` type, so one processing function handles either origin.

### `path_provider` 2.1.5

**What it is.** Resolves platform-correct directories — documents, support, temporary —
instead of hardcoding filesystem paths.

**How it is used.** Three distinct call sites, each a different directory for a reason:
`getApplicationSupportDirectory` for the Drift database file (`app_database.dart:232`),
`getTemporaryDirectory` for processed capture images (`image_service.dart:37`), and
`getApplicationDocumentsDirectory` in `lib/services/ml/ml_runtime.dart:73` for the staged ONNX
models. The models must land on a real filesystem path because the native runtime takes paths,
not asset keys — Flutter assets are not files on disk.

### `crypto` 3.0.7

**What it is.** Dart implementations of standard hash and HMAC algorithms.

**How it is used.** Narrowly, for `sha256` in `ml_runtime.dart`. Model assets have to be copied
out of the Flutter bundle onto the filesystem before ONNX Runtime can open them, and that copy
is expensive for a 68 MB bundle. The runtime hashes the bytes already on disk against the
bundle's bytes and skips the write when they match, so a warm start does no redundant I/O. The
same hashing discipline backs the manifest's per-model `sha256` traceability fields.

### `shared_preferences` 2.5.5

**What it is.** A thin wrapper over the platform key-value stores — `SharedPreferences` on
Android, `NSUserDefaults` on iOS — for small scalar settings.

**How it is used.** Only in `lib/features/capture/data/capture_preferences.dart`, persisting the
user's last-used reference object (type, display name, and length in centimetres) and their
preferred weight unit. This is deliberately not in Drift: it is per-device UI preference, not
scan data, and it carries no relational meaning. Anything that is a record of a measurement
goes to Drift instead.

### `fl_chart` 1.2.0

**What it is.** A charting library for Flutter that draws on canvas, supporting line, bar, pie
and scatter charts with detailed axis and tooltip control.

**How it is used.** Two widgets in the analytics feature, and nowhere else.
`weight_line_chart.dart` maps scan records into `FlSpot` points for a `LineChart` showing
weight over time; `health_bar_chart.dart` builds `BarChartGroupData` / `BarChartRodData` for a
`BarChart` of health class counts. Both are assembled into `overview_panel.dart` and
`health_panel.dart`. They render only values read back from Drift — per AGENTS.md, no invented
scores.

### `google_fonts` 6.3.3

**What it is.** Fetches and caches Google Fonts at runtime, or uses bundled copies, exposing
each family as a `TextStyle` factory.

**How it is used.** One file, `lib/core/theme/app_text_styles.dart`, which defines the app's
whole type scale: `GoogleFonts.inter` for `headline`, `label`, `body` and `subtext`, and
`GoogleFonts.ibmPlexMono` for `numeric`. The monospace face is a deliberate choice for measured
values — weights and confidences — so digits align in columns and do not shift width between
readings. `docs/design-system.md` is the contract these styles implement.

### `cupertino_icons` 1.0.9

**What it is.** The iOS-style icon font used by Flutter's Cupertino widget set.

**How it is used.** **It is not.** No file in `lib/` imports it or references `CupertinoIcons`;
the app draws entirely on Material icons via `uses-material-design: true`. It is the
placeholder dependency that `flutter create` writes into every new project and it was never
removed. Harmless, but it is dead weight and could be dropped.

### `instaham_ml_ffi` (in-repo, path dependency, version 0.0.1)

**What it is.** This project's own Flutter FFI plugin, living at `packages/instaham_ml_ffi/`.
It is not published; it wraps the native C++ inference runtime and exposes it to Dart.

**How it is used.** Imported by exactly one file, `lib/services/ml/ml_runtime.dart`, which is
the process-wide gatekeeper: it stages model assets to disk, verifies them, owns the single
`InstahamMlContext`, and exposes `runPipeline(imagePath)`. That method is synchronous — it
returns a `(MlStatus, Map<String, dynamic>)` record, not a `Future` — because the native call
blocks. Keeping the FFI surface behind one Dart file is what lets AGENTS.md's rule hold that
UI widgets never touch the ML runtime directly. The plugin itself declares `ffi` ^2.1.0 and
resolves the library per platform in `instaham_ml_ffi.dart` via `DynamicLibrary.open`
(`libinstaham_ml.so` on Android, `instaham_ml.dll` on Windows, `DynamicLibrary.process()` on
iOS, where the code is statically linked).

## Development dependencies

### `drift_dev` 2.31.0 and `build_runner` 2.15.1

**What they are.** `build_runner` is Dart's general code-generation driver; `drift_dev` is the
Drift generator that plugs into it.

**How they are used.** Together they produce `lib/core/database/app_database.g.dart` from the
table and DAO declarations. Per AGENTS.md, this runs only when the Drift schema actually
changes, via `dart run build_runner build --delete-conflicting-outputs`, and the generated file
is never edited by hand. Any schema change also requires a `schemaVersion` bump, an explicit
migration, and a migration test.

### `flutter_lints` 6.0.0

**What it is.** The Flutter team's recommended lint rule set, consumed through
`analysis_options.yaml`.

**How it is used.** It defines what `flutter analyze` enforces, which is step 2 of the
project's validation sequence and must come back clean before any Dart change is considered
done. Its `avoid_print` rule is why the benchmark metrics in `integration_test/` carry explicit
`// ignore: avoid_print` comments — those prints are the measurement transport to logcat, not
debugging leftovers.

### `flutter_test` and `integration_test` (Flutter SDK)

**What they are.** `flutter_test` is the host-side widget and unit test framework;
`integration_test` drives the same `testWidgets` API on a real device or emulator.

**How they are used.** `flutter_test` runs everything under `test/` on the Windows Dart VM.
`integration_test` backs `integration_test/benchmark_test.dart`, the device metrics suite, which
does **not** run under `flutter test` — it is executed on Firebase Test Lab per
`docs/device-testing-plan.md`, and needs the JUnit4 bridge at
`android/app/src/androidTest/kotlin/com/instaham/instaham/MainActivityTest.kt` to be
discoverable at all.

## Native libraries (C++, via `instaham_ml_ffi`)

None of these are committed. `packages/instaham_ml_ffi/scripts/fetch_deps.sh` fetches them by
pinned URL and verifies each against a recorded sha256, so the script is the source of truth for
versions.

### ONNX Runtime 1.17.1

**What it is.** Microsoft's cross-platform inference engine for ONNX models.

**How it is used.** It executes all four models in the bundle — the view classifier, the health
classifier, the YOLO segmentation network, and the XGBoost weight regressor exported to ONNX.
`onnx_runner.cpp` wraps session creation and tensor I/O. There is no CMake config package for
the Android build, so `CMakeLists.txt` imports the raw `.so` per ABI; the Windows host build
links a `.lib` generated from the pip wheel's DLL export table, which is what made
`flutter test` able to exercise the native pipeline at all. The version is deliberately pinned
independently of the `onnxruntime` version used for export in `ML/export/`.

### opencv-mobile 4.13.0

**What it is.** A size-reduced OpenCV build for mobile targets, packaging the core imaging
modules without the desktop-oriented extras.

**How it is used.** A hard dependency, not optional. The segmentation post-processing, the
cutter, and the entire Chen16 feature stack are unconditionally OpenCV-based — every file under
`src/stages/` includes `opencv2/core.hpp` or `opencv2/imgproc.hpp` — so those sources are only
added to the build when `INSTAHAM_ML_WITH_OPENCV` is on, and `android/build.gradle.kts` passes
that flag explicitly. It supplies contour extraction, morphology, moments and geometric
measurement, which is where the mask becomes the numbers the weight model consumes.

### nlohmann/json 3.11.3

**What it is.** A single-header modern C++ JSON library.

**How it is used.** Four translation units include it. It parses `assets/ml/manifest.json` on
the native side — which is how the model paths, the declared feature family and the gate
thresholds reach the pipeline without being hardcoded, per AGENTS.md rules 1 and 2 — and it
serializes the pipeline result object that crosses the FFI boundary back to Dart as a JSON
string.

### stb (`stb_image.h`, `stb_image_resize2.h`)

**What it is.** Sean Barrett's public-domain single-header image decode and resize routines.

**How it is used.** In `src/util/image_io.cpp`, for loading the capture file into native memory
independently of OpenCV's own codecs. The vendored copies are fetched from `master` by
`fetch_deps.sh` rather than pinned to a release tag, since stb publishes no versioned releases.

### Vendored: `instaham_v176`

**What it is.** Not a third-party library but the project's own vendored drop of the V176/V144
segmentation and feature stack, at `packages/instaham_ml_ffi/src/vendor/instaham_v176/`, with
its own `PACKAGE_MANIFEST.json`, `VENDOR.md`, and `quality_gates/`.

**How it is used.** It is the ported reference implementation the C++ stages are built from.
Per project convention, a suspected defect in this code is checked by diffing the shipped copy
against the source package in `model_and_cutter/` before anything is blamed on the port.

## Notable transitive dependencies

| package | version | why it matters |
|---|---|---|
| `sqlite3` | 2.9.4 | the actual SQLite bindings under Drift |
| `sqlite3_flutter_libs` | 0.5.42 | ships the SQLite native library into the APK |
| `ffi` | 2.2.0 | pointer and memory utilities used by the FFI plugin |

## Observations

- **`cupertino_icons` is unused.** It is `flutter create` boilerplate; nothing imports it.
- **`pubspec.yaml`'s `description` is still `"A new Flutter project."`** — also generator
  boilerplate, never updated.
- **The ML asset list carries a test-only entry.** `assets/ml/weight/xgboost.onnx` is noted in
  `pubspec.yaml` as enabled for testing rather than as the shipped default; the comment points
  at `ML/export/export_xgboost.py --enable-for-testing`.
- **The benchmark fixture is deliberately absent from the asset list.** Per
  `docs/metrics-phase/6.1-benchmark-fixture-asset.md`, the benchmark image is pushed to the
  device at run time so no test photograph ships in a production APK.
