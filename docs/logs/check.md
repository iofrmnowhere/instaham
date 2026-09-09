On device, with the current APK (envelope dump still in it):

1. Sweep the reference marking on 92kg_pig_meter_stick.HEIC across a wider band than last time — roughly ±8 px around 1547–1552, not ±3. For each mark, capture the envelope via logcat and record mask_area, content_scale, ladder_rung, kept_fraction, estimated_kg.
2. Compare that spread to the host baseline (11.45%, no cutter). Close if it's similar, or bigger if the cutter's adding jitter on top.
3. Repeat for the 118 kg and 96 kg photos — same data phase 2 needs anyway, so this doubles as phase 2's data collection.
4. Confirm the live-camera resolution from a real capture's widthPx/heightPx (one log line), since the "3× worse in the field" claim rests on the documented 720p preset, not a measurement.

That closes 2.1's open steps and hands phase 2 real numbers instead of single points.