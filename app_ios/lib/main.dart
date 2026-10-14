import 'package:mmcal_core/mmcal_core.dart';

/// iOS entry point: the shared MMCal app with NO advertising.
///
/// This app does not depend on google_mobile_ads, so the Google Mobile Ads
/// SDK is not linked into the binary at all - there is no ad code to run, no
/// ad identifiers and no SDK launch check that could abort the app.
void main() => runMmCalApp();
