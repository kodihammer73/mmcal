import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob configuration for the Android app.
///
/// This file lives in `app_android` on purpose: the iOS app does not depend on
/// `google_mobile_ads` at all, so no advertising SDK is ever linked into the
/// App Store binary.
class AdMobService {
  AdMobService._();

  /// Banner ad unit id (Android).
  static const String bannerAdUnitId =
      'ca-app-pub-7952779601826703/9359002306';

  /// AdMob app id - must match the APPLICATION_ID meta-data in
  /// AndroidManifest.xml.
  static const String admobAppId = 'ca-app-pub-7952779601826703~2032010773';

  static bool _isInitialized = false;

  /// Initialises the Google Mobile Ads SDK once. Never throws: a failure
  /// simply means no banner is shown.
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
}
