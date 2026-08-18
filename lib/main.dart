import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'config/settings.dart';
import 'markets/market_registry.dart';
import 'screens/market_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/update_required_screen.dart';
import 'services/admob_service.dart';
import 'services/update_check.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsManager.init();
  // Initialize the AdMob SDK in the background WITHOUT blocking app launch.
  // On some real devices MobileAds.instance.initialize() can hang or throw,
  // which would prevent runApp() from ever being called (blank screen /
  // apparent crash on launch). Fire-and-forget so the UI renders immediately.
  // AdMobService.initialize() is idempotent and already guards against errors.
  unawaited(AdMobService.initialize());
  runApp(const MMCalApp());
}



class MMCalApp extends StatefulWidget {
  const MMCalApp({super.key});

  @override
  State<MMCalApp> createState() => _MMCalAppState();
}

class _MMCalAppState extends State<MMCalApp> {
  ThemeMode _themeMode = ThemeMode.system;

  /// Holds the update-check result. Null while the check is in progress.
  UpdateCheckResult? _updateResult;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  /// Reads the installed version and checks the remote config for a forced
  /// update. If one is required, [home] is replaced by the blocking
  /// [UpdateRequiredScreen].
  Future<void> _checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final result = await UpdateChecker.checkForUpdate(
      installedVersion: info.version,
    );
    if (mounted) {
      setState(() => _updateResult = result);
    }
  }

  void _cycleThemeMode() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MMCal',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: _updateResult?.updateRequired == true
          ? UpdateRequiredScreen(result: _updateResult!)
          : HomeScreen(
              themeMode: _themeMode,
              onCycleThemeMode: _cycleThemeMode,
            ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onCycleThemeMode;
  const HomeScreen({super.key, required this.themeMode, required this.onCycleThemeMode});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List markets;
  String _version = '';
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    markets = getAllMarkets(SettingsManager.instance);
    _tabController = TabController(length: markets.length, vsync: this);
    _loadVersion();
    _loadBannerAd();
  }

  /// Loads the AdMob banner ad in the background.
  Future<void> _loadBannerAd() async {
    await AdMobService.initialize();
    final ad = BannerAd(
      adUnitId: AdMobService.bannerAdUnitIdAndroid,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _bannerAd = ad as BannerAd;
              _bannerLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
        },
      ),
    );
    await ad.load();
  }



  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        // Show the full version from pubspec.yaml, e.g. "1.0.1" -> "v1.0.1".
        _version = 'v${info.version}';
      });
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MultiMarket Calculator - $_version', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              switch (widget.themeMode) {
                ThemeMode.system => Icons.brightness_auto,
                ThemeMode.light => Icons.light_mode,
                ThemeMode.dark => Icons.dark_mode,
              },
            ),
            tooltip: 'Theme: ${widget.themeMode.name}',
            onPressed: widget.onCycleThemeMode,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: markets.map<Widget>((m) => Tab(text: m.name)).toList(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: markets.map<Widget>((m) => MarketScreen(market: m)).toList(),
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '2026 - Made by Hemerjit',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Calculations are estimates for informational purposes only. Actual charges may vary depending on the broker, exchange, transaction type and applicable fees.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // AdMob banner ad at the bottom of the screen.
          // The AdWidget must be given a fixed height (AdSize.banner = 50
          // logical pixels) or the platform view gets an infinite size.
          if (_bannerLoaded && _bannerAd != null)
            Container(
              width: double.infinity,
              height: 50,
              color: Theme.of(context).colorScheme.surface,
              alignment: Alignment.center,
              child: AdWidget(ad: _bannerAd!),
            ),

        ],
      ),
    );
  }
}


