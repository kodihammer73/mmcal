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
- AdMob banner ads (Android - the iOS build ships without ads)
- Forced update mechanism (Android - the iOS build never blocks on a remote screen)
- Per-market input persistence (reopens where you left off)
- Last-used market restore on launch
- Per-market flag emoji + accent color
- Copy / Share results summary
- Live inline validation (no more silent no-op Calculate)
- Animated results entry with auto scroll-to-results
- Portfolio tracking - add a trade from the results with `+`, grouped by market then settlement currency, with a per-currency net total (never converted across currencies), auto-averaged buy price, per-line and per-transaction editing, and JSON/CSV export + JSON import
- Holdings show the **actual buy price** (a weighted average of the purchases still held, excluding costs) plus the **net total** as calculated on the main screen (brokerage, clearing fee and stamp duty included). Sells knock off the **oldest purchase first** (FIFO), so the remaining average reflects what is genuinely still held, and each purchase is tagged open or sold in the expanded row.
- Last done prices - expanding a line (or "Refresh prices" in the menu, or pull-to-refresh) fetches the live price from Yahoo Finance with a Google Finance fallback, showing last price, market value and unrealised P/L with P/L % per line, plus per-currency Value/P/L totals. Cost totals stay cost-based and currencies are never converted.
- Sell what-if - inside an expanded holding, 25/50/75/100% chips estimate the net proceeds and realised P/L for selling a slice at the last reference price, using the market's real fee engine (estimate only, nothing is saved)
- 30-day sparkline in the expanded holding row
- Search (code or name) and sort (market / value / P/L %) across the portfolio
- Undo for line, transaction and clear-all deletions (6-second window)
- Haptic feedback on Calculate, Save and refresh completion
- Code / name suggestions while adding to the portfolio - a curated dictionary bundled offline, refreshed from the project website, with a Yahoo Finance fallback
- Stock codes and names are always stored upper-cased, and matching ignores case, leading zeros (`700` = `0700`) and trailing dots (`RR.` = `RR`)

## Tech Stack
- Flutter (Dart 3.x)
- `shared_preferences` — settings & per-market form persistence
- `intl` — number formatting
- `google_mobile_ads` — AdMob banner ads (**Android app only**; the iOS app has no advertising dependency, so no ad SDK is linked into the App Store binary)
- `share_plus` — share results summary + portfolio export
- `package_info_plus` — app version
- `file_selector` — pick a portfolio JSON file to import
- `path_provider` — temp file used for portfolio export
- `http` + `url_launcher` — forced update check + symbol dictionary refresh + Yahoo Finance fallback
- `assets/mmcal_symbols.json` — bundled symbol dictionary (~41,000 symbols across all 11 markets), generated from the per-market CSVs in `assets/` by `tools/build_symbols.py`

## Project Structure

The repo is a small monorepo: one shared library holds all the code, and two
thin app shells provide the platform entry points. **The iOS shell has no
advertising dependency at all**, which is what keeps the Google Mobile Ads SDK
out of the App Store binary.

```
packages/mmcal_core/               # shared library - ALL app code, no advertising
├── lib/
│   ├── mmcal_core.dart            # barrel export used by the app shells
│   ├── mmcal_app.dart             # App entry: MaterialApp + TabBar (11 tabs), runMmCalApp()
│   ├── config/settings.dart       # kDefaultSettings (118 items), SettingsManager
│   ├── engine/engine.dart         # Market abstract, ForeignMarket base, rounding helpers
│   ├── markets/                   # Malaysia, Singapore, Hong Kong, US + simple markets
│   ├── screens/                   # market tab, portfolio log, add sheet, settings, splash
│   ├── services/                  # form state, portfolio store/codec/transfer, symbols, quotes, update check
│   └── ui/                        # branding, stock identifier field, formatters, sparkline
├── assets/
│   ├── ListOfSecurities<Market>.csv  # Source of truth: one exchange export per market
│   ├── mmcal_symbols.json            # Generated dictionary (do not hand-edit)
│   └── MMCaltrans.png                # Logo used by the splash + header
└── test/                          # the whole test suite
app_android/                       # thin Android shell: mmcal_core + google_mobile_ads
├── lib/main.dart                  # runMmCalApp(onStartup: ..., bannerBuilder: ...)
├── lib/services/admob_service.dart
├── lib/widgets/admob_banner.dart
└── android/                       # Gradle project (com.mmcal.app)
app_ios/                           # thin iOS shell: mmcal_core ONLY - no ad SDK
├── lib/main.dart                  # runMmCalApp()
└── ios/                           # Xcode project (com.mmcal.app)
tools/
├── build_symbols.py               # assets/*.csv -> assets/mmcal_symbols.json
└── verify_symbols.py              # Checks each row against Yahoo Finance
```

## Building

### Android (from `app_android/`)
```bash
cd app_android
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```
The release build is signed with `app_android/android/key.properties` +
`app_android/android/app/mmcal-release.jks`; neither is committed (see
`.gitignore`).

### iOS (requires macOS + Xcode; from `app_ios/`)
```bash
cd app_ios
flutter build ios --release
# Output: build/ios/iphoneos/Runner.app
```

> **Note:** iOS builds require a Mac with Xcode, so they run in a **GitHub Actions workflow** (`.github/workflows/ios.yml`) on a macOS runner. On a `v*` tag it signs the build and uploads it to App Store Connect.
>
> **Android is built locally on the PC and is deliberately NOT in CI** (the release keystore and `key.properties` are not in the repo). A tag push therefore starts exactly one workflow. See the release checklist in `memory-bank/mobile-app-guide.md`.

## GitHub Actions CI
One workflow - `.github/workflows/ios.yml` (macOS) - triggered by `v*` tags,
pull requests to `main`, and manual dispatch:

1. analyzes and tests `packages/mmcal_core` (`flutter pub get`, `flutter analyze`,
   `flutter test`),
2. analyzes `app_ios`,
3. builds the app (`flutter build ios --release --no-codesign`),
4. on a `v*` tag: imports the signing cert + profile, signs the IPA, uploads it
   to App Store Connect and attaches it to a GitHub release.

> **There is deliberately NO Android CI.** Android is built on the developer's
> PC (`cd app_android && flutter build appbundle --release`) because the release
> keystore / `key.properties` are not committed. A tag push starts exactly one
> workflow (iOS).

## Testing
Run the suite in the shared package - that is where the code and the tests
live:
```bash
cd packages/mmcal_core
flutter test
```
179 tests pass (engine parity tests mirroring the Python desktop test suites, plus unit/widget tests for the portfolio, the symbol dictionary and the UI features).

## Symbol dictionary

One box in the portfolio sheet takes a **stock code or a name**. As you type, the
dictionary for the market being traded is searched and the matches are offered for
tapping; picking one stores the dictionary's code **and** short name. Typing
something the dictionary does not know is fine — the entry is saved exactly as
typed. Lookups come from four sources, best first, and never block saving:

1. **Hosted** `https://www.gurdwarasahibmelaka.com/data/mmcal_symbols.json` —
   fetched in the background once per app run when the device is online, then
   cached on the device. Once published, this file **replaces** the bundled copy.
2. **Cached** copy from a previous session — a file in the app support directory
   (the payload is ~2 MB, too big for SharedPreferences; preferences are only a
   fallback), so the app keeps working after it goes offline.
3. **Bundled** `assets/mmcal_symbols.json` — always available, even on a first
   run with no network at all.
4. **Yahoo Finance** search — only when none of the above has an answer, and
   restricted to the exchange of the market being traded. It also covers the
   code-only markets below when you search by company name.

### Editing the dictionary

The per-market exchange exports in `assets/` are the source of truth — one file
per market (`ListOfSecuritiesMalaysia.csv`, `ListOfSecuritiesHongKong.csv`, …),
each row `code,name`. Some markets publish codes only (Indonesia, Thailand, the
USA). Whenever a fresh list arrives for **any** market, drop it in `assets/` and
regenerate the dictionary:

```bash
python tools/build_symbols.py
```

The script merges every list into `assets/mmcal_symbols.json` (~41,000 symbols),
prints a per-market report (rows kept, duplicates, codes normalised), and
normalises the quirks of the raw exports: header rows are skipped, Singapore's
padding and `$`-prefixed names are cleaned, names containing commas are
re-joined, Thailand's Yahoo `.BK` suffix (and its `^SET` index row) is dropped,
and Japan's stray trailing zero (`7203.0` exported as `72030`) is removed. Add
`--out <path>` to also write a copy anywhere on your PC, e.g. for upload.

Then copy `assets/mmcal_symbols.json` into the site's `/data/` folder, i.e.
`https://gurdwarasahibmelaka.com/data/mmcal_symbols.json` — the URL
`SymbolLookup.remoteUrl` requests. Publishing keeps every installed app current;
without it they simply keep using the bundled copy.

> **Important:** a published file **replaces** the bundled dictionary, it does
> not merge with it. Always publish the complete generated file, never a partial
> delta, or the symbols it omits will disappear from suggestions. Installed apps
> pick changes up on their next online run.

### Verifying the dictionary

`tools/verify_symbols.py` checks the built dictionary against Yahoo Finance and
reports codes that do not resolve, plus names that differ:

```bash
python tools/verify_symbols.py                  # every row (~41,000 - slow)
python tools/verify_symbols.py --market Malaysia
python tools/verify_symbols.py --limit 20
python tools/verify_symbols.py --fix            # also write a suggested JSON
```

> **Provenance.** The codes come from the exchange exports in `assets/`, so they
> are the exchanges' own. The **short names are whatever those exports carry**:
> long registered names for Malaysia/Hong Kong/Canada, mixed-case names
> upper-cased for Japan/Germany, and *nothing at all* for Indonesia, Thailand and
> the USA (those markets publish codes only, so suggestions there show the code).
> A wrong or missing row is not fatal: the Yahoo fallback covers lookups the
> dictionary misses, and the user can always type the stock in by hand.

A `NAME?` result usually just means Yahoo uses the exchange's official short name
(`BABA-W`, `AIA`, `Tesla, Inc.`), which is often *less* friendly to type than the
plain name already in the dictionary — so review name differences rather than
bulk applying them. A `MISSING` result, or a `NAME?` pointing at a completely
different company (e.g. a code that has since been reassigned), is the real
signal to act on.

## App Store / iOS Signing
To install on a device or publish to the App Store, you need:
- An **Apple Developer account** ($99/year)
- A signing certificate + provisioning profile
- Set up code signing in Xcode or via GitHub Actions secrets

## License
© 2026 Hemerjit. All rights reserved.
