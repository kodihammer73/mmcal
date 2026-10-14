import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-market calculator input (quantity, prices, rates, toggles)
/// so switching tabs or restarting the app doesn't lose progress.
///
/// Each market's form state is stored as one JSON string under a prefixed
/// key, e.g. `formstate_Malaysia`. Also tracks the last-used market index
/// so the app can reopen on the market the user was on.
class FormStateStore {
  FormStateStore._();

  static const String _lastMarketKey = 'last_market_index';

  static String _key(String marketName) => 'formstate_$marketName';

  /// Loads the persisted form state for [marketName]. Returns an empty map
  /// when nothing has been saved yet.
  static Future<Map<String, Object>> load(String marketName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(marketName));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v as Object));
      }
    } catch (_) {
      // Corrupt / stale data — treat as empty.
    }
    return {};
  }

  /// Persists the given form fields for [market].
  static Future<void> save(String marketName, Map<String, Object> fields) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(marketName), jsonEncode(fields));
  }

  /// Clears any saved form for [market].
  static Future<void> clear(String marketName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(marketName));
  }

  /// Last-used market index (0-based into the market list), or null.
  static Future<int?> loadLastMarket() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_lastMarketKey);
    return idx;
  }

  static Future<void> saveLastMarket(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastMarketKey, index);
  }
}