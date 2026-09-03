Write a plan to TASKS.md

The app already has a "reference object point" feature: the user taps 2 points over a reference object (presets like "1 meter stick", or custom length), and it computes cm/px = known_length / pixel_distance between the points, live-updating as the points move. It's currently a dummy — the cm/px value isn't wired into anything downstream.

Resize formula: k = cm_per_px_actual / cm_per_px_target, where cm_per_px_target is a fixed constant representing the cm/px this same tool would compute at the 1.88m baseline height. This constant does not yet exist and needs to be established (e.g., by running the tool once on a calibration photo taken at exactly 1.88m) and stored somewhere the pipeline can read at inference time.

Here's what the flow looks like if the reference object logic was implemented

---

Segmentation Flow: Original RGB Image -> Resize while preserving aspect ratio -> Add padding/letterbox 
-> 640 x 640 YOLO input -> YOLO segmentation

---

Weight Prediction Flow: Remove padding/recover original coordinates -> Mask H x W (this is what goes downstream) 
-> Ji/Duan + body-masking -> Feature extraction -> RA, LC, BL, BW, E -> XGBoost

----

