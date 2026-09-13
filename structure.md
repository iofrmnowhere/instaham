ORIGINAL IMAGE
    │
    ├─ save original W, H
    │
    ↓
LETTERBOX → 640×640
    │
    ↓
YOLO SEGMENTATION
    │
    ↓
160×160 FLOAT prototype mask
    │
    ↓
crop mask to detected box
(still FLOAT)
    │
    ↓
INTER_LINEAR → 640×640
(still FLOAT)
    │
    ↓
THRESHOLD > 0.5
    │
    ↓
640×640 BINARY MASK
    │
    ↓
ONE SINGLE GEOMETRIC TRANSFORM
    │
    │  simultaneously:
    │  • remove letterbox padding
    │  • undo YOLO resize
    │  • apply reference/camera scale k
    │
    ↓
FINAL PIGRGB-EQUIVALENT WORKING MASK
    │
    ↓
Posture gate
    ↓
Truncation gate
    ↓
Ji Duan / cutting
    ↓
Final post-cut mask
    ↓
16 feature extraction
    ↓
EXISTING XGBOOST