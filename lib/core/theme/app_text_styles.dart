import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography tokens — Inter for body/headings, IBM Plex Mono for numeric readouts.
abstract final class AppTextStyles {
  static final headline = GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );
  static final label = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  static final body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static final subtext = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// Numeric / measurement readout
  static final numeric = GoogleFonts.ibmPlexMono(
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );
}
