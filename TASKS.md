# INSTAHAM Development Tasks

A living document to track the implementation progress of the INSTAHAM Flutter application.

## 🟢 Completed
- [x] **Project Foundation:** Setup Flutter project and Next.js visual reference (`instaham_ui`).
- [x] **Local Database:** Define SQLite/Drift schema (`app_database.dart`) with tables for Pigs, ScanRecords, WeightResults, and HealthResults.
- [x] **Web Support:** Compile and integrate WASM SQLite engine (`sqlite3.wasm`) and Drift worker (`drift_worker.dart.js`) for Flutter Web compatibility.
- [x] **Navigation:** Implement `go_router` and a responsive 5-item `AppBottomNav` (Home, Analytics, Scan, Records, Privacy).
- [x] **Core Screens:** Build `PrivacyScreen`, `RecordsScreen` (driven by `RecordsDao` with proper modular DI and empty states), and `ResultsScreen` (fixing async `setState` exceptions).
- [x] **Analytics Module:** Build `AnalyticsScreen` with three tabs (Overview, Weight, Health), driven by live Drift streams via `AnalyticsDao`. Features line/bar graphs (`fl_chart`), date range filtering, pig search autocomplete, proper modular DI, and resilient error state handling.
- [x] **Unit Testing:** Implement unit tests for SQLite database methods, `AnalyticsDao`, and `RecordsDao` queries.

- [x] **Capture Mode Selector:** Added persistent toggle for "Reference Mode" vs "Height Mode" during capture, removing the deprecated "Health Only" mode.
- [x] **Custom Reference Objects:** Implemented in-place UI form for adding custom reference objects and persisted them locally in Drift via `CustomReferencesDao`.
- [x] **Height Mode Persistence & UI:** Cleaned up height mode capture UI, migrated database to track `measurementMode` and `cameraHeightCm`, and added height mode card to scan details.

## 🟡 In Progress / Next Up
- [ ] **Camera Flow:** Implement `CaptureScreen` and `CaptureGuidanceScreen` with `camera` plugin.

## 🔴 To Do (ML Pipeline & Inference)
- [ ] **Pipeline Orchestration:** Implement the `InferencePipeline` class to manage the sequence of models.
- [ ] **View Suitability:** Integrate MobileNetV4 model to classify `dorsal_valid`, `health_only`, or `reject`.
- [ ] **Instance Segmentation:** Integrate YOLO model to extract pig masks and bounding boxes.
- [ ] **Geometric Eligibility:** Implement logic to reject bounding boxes touching image edges (Rule 3) and verify minimum dimensions.
- [ ] **Feature Extraction:** Extract `RA, LC, BL, BW, E` features from the mask and user-provided reference coordinates.
- [ ] **Weight Regression:** Integrate XGBoost model to predict weight in kg.
- [ ] **Health Classification:** Integrate health MobileNetV4/ShuffleNet model to output health status/confidence.
- [ ] **Integration:** Replace `MockHealthRepository` and `MockAnalyticsRepository` with the real end-to-end pipeline.

## 🔴 To Do (Refinement)
- [ ] **State Management:** Ensure ML pipeline results cleanly hand off to `ResultsScreen` and save correctly to Drift.
- [ ] **Error Handling:** Graceful recovery for ML model loading failures or memory exhaustion.
- [ ] **Cleanup:** Remove debug buttons (like "Insert sample record") before production release.
