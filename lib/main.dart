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
import 'services/form_state.dart';
import 'services/update_check.dart';
import 'ui/branding.dart';

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

/// Brand palette used across the app.
class AppColors {
  AppColors._();

  // Primary blue / indigo identity
  static const Color primary = Color(0xFF1E3A8A); // deep indigo
  static const Color accent = Color(0xFF2563EB); // vivid blue
  static const Color accentLight = Color(0xFF60A5FA);
  static const Color darkPrimary = Color(0xFF0D2A66);

  // Gradient for the app bar
  static const List<Color> appBarGradient = [Color(0xFF1E3A8A), Color(0xFF2563EB)];
  static const List<Color> appBarGradientDark = [Color(0xFF0D2A66), Color(0xFF1E3A8A)];

  // Buy / Sell accents (light mode)
  static const Color buyLight = Color(0xFF15803D);
  static const Color sellLight = Color(0xFFB91C1C);
  static const Color totalLight = Color(0xFF1D4ED8);

  // Buy / Sell accents (dark mode)
  static const Color buyDark = Color(0xFF4ADE80);
  static const Color sellDark = Color(0xFFF87171);
  static const Color totalDark = Color(0xFF93C5FD);
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

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: isDark ? AppColors.accentLight : AppColors.primary,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        selectedColor: scheme.primary,
        backgroundColor: scheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        isDense: true,
        labelStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        thickness: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MMCal',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
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
    _restoreLastMarket();
    _tabController.addListener(_onTabChanged);
    _loadVersion();
    _loadBannerAd();
  }

  /// Reopens the app on the market the user was last viewing.
  Future<void> _restoreLastMarket() async {
    final idx = await FormStateStore.loadLastMarket();
    if (!mounted) return;
    if (idx != null && idx >= 0 && idx < markets.length) {
      _tabController.index = idx;
    }
    setState(() {});
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (!_tabController.indexIsChanging) {
      FormStateStore.saveLastMarket(_tabController.index);
      setState(() {});
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = isDark ? AppColors.appBarGradientDark : AppColors.appBarGradient;

    return Scaffold(
      body: Column(
        children: [
          // ── Gradient AppBar with rounded bottom ─────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        Image.asset(
                          'MMCaltrans.png',
                          width: 26,
                          height: 26,
                          cacheWidth: 96,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.calculate, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'MultiMarket Trade Calculator',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${marketFlag(markets[_tabController.index].name)} ${markets[_tabController.index].name}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          icon: Icon(
                            switch (widget.themeMode) {
                              ThemeMode.system => Icons.brightness_auto,
                              ThemeMode.light => Icons.light_mode,
                              ThemeMode.dark => Icons.dark_mode,
                            },
                            color: Colors.white,
                          ),
                          tooltip: 'Theme: ${widget.themeMode.name}',
                          onPressed: widget.onCycleThemeMode,
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          tooltip: 'Settings',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicatorColor: Colors.amber,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: markets.map<Widget>((m) => Tab(text: '${marketFlag(m.name)} ${m.name}')).toList(),
                  ),
                ],
              ),
            ),
          ),
          // ── Body ────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: markets.map<Widget>((m) => MarketScreen(market: m)).toList(),
            ),
          ),
          // ── Footer disclaimer ───────────────────────────────
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${DateTime.now().year} - Developed by Hemerjit - $_version',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
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
