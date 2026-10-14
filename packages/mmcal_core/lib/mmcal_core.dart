/// MMCal shared library.
///
/// Everything the app does lives here: the fee engine, the 11 market
/// definitions, the screens and the services. Advertising is deliberately NOT
/// part of this package - the host app injects its banner via
/// [runMmCalApp]'s `bannerBuilder`, which is how the iOS app can ship with no
/// ad SDK at all.
library;

export 'mmcal_app.dart';
