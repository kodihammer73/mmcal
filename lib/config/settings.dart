import 'package:shared_preferences/shared_preferences.dart';

const Map<String, double> kDefaultSettings = {
  // General
  'offlinebrk': 40.00,
  'onlinebrk': 28.00,
  'minstampduty': 1.00,
  'maxstampduty': 200.00,
  'gstrate': 8.00,
  'rmbrkamt': 100000,
  // Malaysia
  'malclrfeerate': 0.03,
  'malstmpdutyrate': 0.10,
  'maloffbrkrate1': 0.60,
  'maloffbrkrate2': 0.30,
  'malonbrkrate1': 0.42,
  'malonbrkrate2': 0.21,
  'malminbrk': 12.00,
  // USA
  'usaforchrgrate': 0.03,
  'usaminbrk': 0.00,
  'usasecfeerate': 0.00218,
  'usastmpdutyrate': 0.1015,
  'usaoffminrmbrkrate': 0.57,
  'usaoffmaxrmbrkrate': 0.37,
  'usaonminrmbrkrate': 0.37,
  'usaonmaxrmbrkrate': 0.27,
  // Singapore
  'sinforchrgrate': 0.05,
  'sinminbrk': 0,
  'sintrdfeerate': 0.007517,
  'sinclrfeerate': 0.0325,
  'sinoffminrmbrkrate': 0.55,
  'sinoffmaxrmbrkrate': 0.25,
  'sinonminrmbrkrate': 0.35,
  'sinonmaxrmbrkrate': 0.20,
  'sinstmpdutyrate': 0.10,
  // Hong Kong
  'hkdforchrgrate': 0.05,
  'hkdminbrk': 0,
  'hkdtrdfeerate': 0.0056,
  'hkdlevyfeerate': 0.00285,
  'hkdccassfeerate': 0.0042,
  'hkdminccassfee': 2.00,
  'hkdstampdutyrate': 0.001,
  'hkdlocalstampdutyrate': 0.10025,
  'hkdoffminrmbrkrate': 0.55,
  'hkdoffmaxrmbrkrate': 0.25,
  'hkdonminrmbrkrate': 0.37,
  'hkdonmaxrmbrkrate': 0.20,
  // Thailand
  'thaforchrgrate': 0.05,
  'thaminbrk': 0,
  'thagstrate': 0.0049,
  'thaoffminrmbrkrate': 0.65,
  'thaoffmaxrmbrkrate': 0.45,
  // Indonesia
  'indforchrgrate': 0.05,
  'indminbrk': 0,
  'indgstrate': 0.013,
  'indassfund': 0.01,
  'indexchfee': 0.03,
  'indsalestax': 0.10,
  'indoffminrmbrkrate': 0.65,
  'indoffmaxrmbrkrate': 0.35,
  // UK
  'ukdforchrgrate': 0.10,
  'ukdminbrk': 0,
  'ukdgstrate': 0.50,
  'ukdoffminrmbrkrate': 0.65,
  'ukdoffmaxrmbrkrate': 0.50,
  // Australia
  'ausforchrgrate': 0.10,
  'ausminbrk': 0,
  'ausoffminrmbrkrate': 0.65,
  'ausoffmaxrmbrkrate': 0.55,
  // Japan
  'japforchrgrate': 0.20,
  'japminbrk': 0,
  'japoffminrmbrkrate': 0.70,
  'japoffmaxrmbrkrate': 0.45,
  // Canada
  'canforchrgrate': 0.35,
  'canminbrk': 0,
  'canoffminrmbrkrate': 0.90,
  'canoffmaxrmbrkrate': 0.65,
  // Germany
  'gerforchrgrate': 0.15,
  'germinbrk': 0,
  'geroffminrmbrkrate': 1.05,
  'geroffmaxrmbrkrate': 0.75,
};

class SettingsManager {
  static SettingsManager? _instance;
  static SettingsManager get instance => _instance!;

  final Map<String, double> _settings = {};

  static Future<SettingsManager> init() async {
    _instance = SettingsManager._();
    await _instance!._load();
    return _instance!;
  }

  /// Creates a SettingsManager with default values (no persistence).
  SettingsManager() {
    _settings.addAll(kDefaultSettings);
  }

  SettingsManager._();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in kDefaultSettings.entries) {
      _settings[entry.key] = prefs.getDouble(entry.key) ?? entry.value;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _settings.entries) {
      await prefs.setDouble(entry.key, entry.value);
    }
  }

  double get(String key) => _settings[key] ?? kDefaultSettings[key] ?? 0.0;

  void set(String key, double value) {
    _settings[key] = value;
  }

  Future<void> resetToDefaults() async {
    for (final entry in kDefaultSettings.entries) {
      _settings[entry.key] = entry.value;
    }
    await save();
  }

  Map<String, double> get all => Map.unmodifiable(_settings);
}