# MMCal - Multi Market Calculator (Mobile)

A stock trading cost calculator for **11 markets** (Malaysia, Singapore, Hong Kong, United States, Thailand, Indonesia, United Kingdom, Australia, Japan, Canada, Germany). Calculates trading costs including brokerage, stamp duty, clearing fees, GST/SST, and foreign charges for buy/sell transactions.

Built with **Flutter** for **Android** and **iOS**.

## Features
- 11 market tabs with per-market fee structures
- Offline / Online trade modes
- Special brokerage rate support
- MIN RM12 option (Malaysia)
- No Stamp Duty option (Malaysia)
- Sett in local currency option (foreign markets)
- DF A/C with interest calculation (Malaysia)
- Breakeven price calculation
- Contra gain/loss calculation
- Dark / Light / System theme toggle
- AdMob banner ads
- Forced update mechanism

## Tech Stack
- Flutter (Dart 3.x)
- `shared_preferences` — settings persistence
- `intl` — number formatting
- `google_mobile_ads` — AdMob banner ads
- `package_info_plus` — app version
- `http` + `url_launcher` — forced update check

## Project Structure
```
lib/
├── main.dart                      # App entry, MaterialApp + TabBar (11 tabs)
├── config/
│   └── settings.dart              # kDefaultSettings (73 items), SettingsManager
├── engine/
│   └── engine.dart                # Market abstract, ForeignMarket base, rounding helpers
├── markets/
│   ├── malaysia.dart              # MalaysiaMarket (custom calculate + DF A/C)
│   ├── singapore.dart             # SingaporeMarket (HKD settlement support)
│   ├── hongkong.dart              # HongKongMarket (CCASS, levy, foreign stamp duty)
│   ├── united_states.dart         # UnitedStatesMarket (SEC fee, USD min brokerage)
│   ├── simple_markets.dart        # Thailand, Indonesia, UK, Australia, Japan, Canada, Germany
│   └── market_registry.dart       # getAllMarkets() factory
├── screens/
│   ├── market_screen.dart         # Per-market tab: buy/sell inputs, chips, results
│   ├── settings_screen.dart       # Expandable settings by market group
│   └── update_required_screen.dart # Blocking forced-update screen
└── services/
    ├── admob_service.dart         # AdMob banner ad service
    └── update_check.dart          # Forced update checker
```

## Building

### Android
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS (requires macOS + Xcode)
```bash
flutter build ios --release
# Output: build/ios/iphoneos/Runner.app
```

> **Note:** iOS builds require a Mac with Xcode. This repo includes a **GitHub Actions workflow** (`.github/workflows/ios.yml`) that builds the iOS app automatically on every push to `main` using a macOS runner. The build is unsigned (`--no-codesign`); download the artifact from the Actions tab.

## GitHub Actions CI
The `.github/workflows/ios.yml` workflow runs on every push to `main`:
1. Sets up Flutter on a macOS runner
2. Runs `flutter analyze` and `flutter test`
3. Builds the iOS app (`flutter build ios --release --no-codesign`)
4. Uploads `Runner.app` as a downloadable artifact

## Testing
```bash
flutter test
```
30 tests pass (29 engine parity tests mirroring the Python desktop test suites + 1 smoke test).

## App Store / iOS Signing
To install on a device or publish to the App Store, you need:
- An **Apple Developer account** ($99/year)
- A signing certificate + provisioning profile
- Set up code signing in Xcode or via GitHub Actions secrets

## License
© 2026 Hemerjit. All rights reserved.
