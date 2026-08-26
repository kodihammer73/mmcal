/// Per-market visual identity: flag emoji + an accent hue.
///
/// Kept in a Flutter-lib file (not the pure-Dart engine) so the engine
/// stays free of any Flutter imports. The accents are subtle country hues
/// that sit comfortably alongside the app's blue/indigo brand gradient.
library;

import 'package:flutter/material.dart';

String marketFlag(String marketName) =>
    _flags[marketName] ?? _flags['Malaysia']!;

Color marketAccent(String marketName) =>
    _accents[marketName] ?? _accents['United States (US)']!;

const Map<String, String> _flags = {
  'Malaysia': '🇲🇾',
  'Singapore': '🇸🇬',
  'Hong Kong': '🇭🇰',
  'United States (US)': '🇺🇸',
  'Thailand': '🇹🇭',
  'Indonesia': '🇮🇩',
  'United Kingdom (UK)': '🇬🇧',
  'Australia': '🇦🇺',
  'Japan': '🇯🇵',
  'Canada': '🇨🇦',
  'Germany': '🇩🇪',
};

const Map<String, Color> _accents = {
  'Malaysia': Color(0xFF15803D),
  'Singapore': Color(0xFFDC2626),
  'Hong Kong': Color(0xFFC026D3),
  'United States (US)': Color(0xFF2563EB),
  'Thailand': Color(0xFF1D4ED8),
  'Indonesia': Color(0xFFB91C1C),
  'United Kingdom (UK)': Color(0xFF475569),
  'Australia': Color(0xFF0D9488),
  'Japan': Color(0xFFBE123C),
  'Canada': Color(0xFFE11D48),
  'Germany': Color(0xFFCA8A04),
};