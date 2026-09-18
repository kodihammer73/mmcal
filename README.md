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
- Per-market input persistence (reopens where you left off)
- Last-used market restore on launch
- Per-market flag emoji + accent color
- Copy / Share results summary
- Live inline validation (no more silent no-op Calculate)
- Animated results entry with auto scroll-to-results
- Portfolio tracking - add a trade from the results with `+`, grouped by market then settlement currency, with a per-currency net total (never converted across currencies), auto-averaged buy price, per-line and per-transaction editing, and JSON/CSV export + JSON import
- Last done prices - expanding a line (or "Refresh prices" in the menu) fetches the live price from Yahoo Finance with a Google Finance fallback, showing last price, day change, market value and unrealised P/L per line, plus per-currency Value/P/L totals. Cost totals stay cost-based and currencies are never converted.
- Code / name suggestions while adding to the portfolio - a curated dictionary bundled offline, refreshed from the project website, with a Yahoo Finance fallback
- Stock codes and names are always stored upper-cased, and matching ignores case, leading zeros (`700` = `0700`) and trailing dots (`RR.` = `RR`)

## Tech Stack
- Flutter (Dart 3.x)
- `shared_preferences` — settings & per-market form persistence
- `intl` — number formatting
- `google_mobile_ads` — AdMob banner ads
- `share_plus` — share results summary + portfolio export
- `package_info_plus` — app version
- `file_selector` — pick a portfolio JSON file to import
- `path_provider` — temp file used for portfolio export
- `http` + `url_launcher` — forced update check + symbol dictionary refresh + Yahoo Finance fallback
- `assets/mmcal_symbols.json` — bundled symbol dictionary (~41,000 symbols across all 11 markets), generated from the per-market CSVs in `assets/` by `tools/build_symbols.py`

## Project Structure
```
lib/
├── main.dart                      # App entry, MaterialApp + TabBar (11 tabs)
├── config/
│   └── settings.dart              # kDefaultSettings (118 items), SettingsManager
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
│   ├── portfolio_screen.dart      # Holdings grouped by market then currency
│   ├── add_portfolio_sheet.dart   # Add / edit a portfolio transaction sheet
│   ├── settings_screen.dart       # Expandable settings by market group
│   └── update_required_screen.dart # Blocking forced-update screen
├── services/
│   ├── admob_service.dart         # AdMob banner ad service
│   ├── form_state.dart            # Per-market input persistence + last market
│   ├── portfolio_store.dart       # Portfolio ledger + position aggregation
│   ├── portfolio_codec.dart       # Portfolio JSON/CSV encode + import decode
│   ├── portfolio_transfer.dart    # Portfolio export share / import file pick
│   ├── symbol_lookup.dart         # Code <-> name dictionary + Yahoo fallback
│   ├── quote_service.dart         # Last-done prices: Yahoo chart -> search -> Google Finance
│   └── update_check.dart          # Forced update checker
└── ui/
    ├── branding.dart              # Per-market flag emoji + accent colors
    ├── stock_identifier_field.dart # One code-or-name box + dictionary suggestions
    └── input_formatters.dart      # Upper-case formatter for stock code/name
assets/
├── ListOfSecurities<Market>.csv   # Source of truth: one exchange export per market
└── mmcal_symbols.json             # Generated dictionary (do not hand-edit)
tools/
├── build_symbols.py               # assets/*.csv -> assets/mmcal_symbols.json
└── verify_symbols.py              # Checks each row against Yahoo Finance
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
145 tests pass (engine parity tests mirroring the Python desktop test suites, plus unit/widget tests for the portfolio, the symbol dictionary and the UI features).

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
