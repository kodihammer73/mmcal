import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Centralized AdMob configuration and banner ad management.
///
/// IMPORTANT: Replace the placeholder Ad Unit IDs below with your own
/// real Ad Unit IDs from the AdMob console (https://apps.admob.com).
///
/// - [bannerAdUnitIdAndroid]: Your Android banner ad unit ID.
/// - [bannerAdUnitIdIos]: Your iOS banner ad unit ID.
///
/// The test IDs shown here are Google's official test ad unit IDs, which
/// always return a test banner so you can verify the integration works
/// before you go live. They will NOT earn revenue — you must swap in your
/// real IDs for production.
class AdMobService {
  AdMobService._();

  /// Your real AdMob banner ad unit IDs go here.
  static const String bannerAdUnitIdAndroid =
      'ca-app-pub-7952779601826703/9359002306';
  static const String bannerAdUnitIdIos =
      'ca-app-pub-7952779601826703/3879508552';



  /// Your AdMob App ID (from the AdMob console "App settings" page).
  /// This must match the value in AndroidManifest.xml / Info.plist.
  static const String admobAppId = 'ca-app-pub-7952779601826703~2032010773';


  static BannerAd? _bannerAd;
  static bool _isInitialized = false;

  /// Returns the correct banner ad unit ID for the current platform.
  static String get _bannerAdUnitId {
    if (kIsWeb) return bannerAdUnitIdAndroid;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return bannerAdUnitIdAndroid;
      case TargetPlatform.iOS:
        return bannerAdUnitIdIos;
      default:
        return bannerAdUnitIdAndroid;
    }
  }

  /// Initializes the Google Mobile Ads SDK. Call this once at app startup.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      debugPrint('AdMob SDK initialized.');
    } catch (e) {
      debugPrint('AdMob SDK initialization failed: $e');
    }
  }

  /// Loads a banner ad. Call this after the SDK is initialized.
  static Future<void> loadBannerAd() async {
    if (!_isInitialized) {
      await initialize();
    }
    // Dispose any existing banner before loading a new one.
    await disposeBannerAd();

    final ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('Banner ad loaded.');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
        },
        onAdOpened: (ad) => debugPrint('Banner ad opened.'),
        onAdClosed: (ad) => debugPrint('Banner ad closed.'),
      ),
    );

    _bannerAd = ad;
    await ad.load();
  }

  /// Returns the loaded banner ad widget, or null if not loaded.
  static BannerAd? get bannerAd => _bannerAd;

  /// Disposes the banner ad to free resources.
  static Future<void> disposeBannerAd() async {
    _bannerAd?.dispose();
    _bannerAd = null;
  }
}
