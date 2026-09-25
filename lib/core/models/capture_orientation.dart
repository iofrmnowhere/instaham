/// The two orientations distinguished by the capture-orientation rule
/// (docs/fix-phase-4/6-capture-orientation.md, closing F65): portrait requires the pig's head
/// facing up, landscape requires it facing right. The two rules state the same downstream fact
/// -- README §4 rotates a portrait capture 90° clockwise, so head-up becomes head-right, while
/// landscape is not rotated and so must already be head-right. The app cannot verify head
/// direction (no head detector; §4 forbids adding one at preprocessing), so this is enforced by
/// instruction and user attestation, not detection.
enum CaptureOrientation {
  portrait,
  landscape;

  /// Derived from the final, EXIF-corrected image dimensions -- the orientation the capture is
  /// actually written with, matching README §4's own `normalizedHeight > normalizedWidth` test
  /// rather than the live sensor reading or `MediaQuery`, which can disagree with it when
  /// rotation lock is on.
  static CaptureOrientation fromDimensions(int widthPx, int heightPx) {
    return heightPx > widthPx
        ? CaptureOrientation.portrait
        : CaptureOrientation.landscape;
  }

  String get storageValue => name;
}

/// Parses a stored `capture_orientation` column value back into the enum. Returns null for
/// null/unrecognized input rather than throwing -- rows captured before this phase have no
/// value.
CaptureOrientation? captureOrientationFromStorage(String? value) {
  for (final orientation in CaptureOrientation.values) {
    if (orientation.storageValue == value) return orientation;
  }
  return null;
}

extension CaptureOrientationCopy on CaptureOrientation {
  /// The instruction shown to the user for this orientation, phrased for the orientation the
  /// phone is actually in rather than as a conditional the user has to evaluate.
  String get headDirectionInstruction => switch (this) {
    CaptureOrientation.portrait => "Portrait: keep the pig's head facing up.",
    CaptureOrientation.landscape =>
      "Landscape: keep the pig's head facing right.",
  };

  /// The attestation sentence shown on the post-capture confirm step.
  String get attestationLabel => switch (this) {
    CaptureOrientation.portrait =>
      "I confirm the pig's head is facing up in this photo.",
    CaptureOrientation.landscape =>
      "I confirm the pig's head is facing right in this photo.",
  };
}
