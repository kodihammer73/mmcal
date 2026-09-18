import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portfolio_store.dart';

/// One row of the symbol dictionary.
class SymbolEntry {
  final String market;
  final String code;
  final String name;

  const SymbolEntry({
    required this.market,
    required this.code,
    required this.name,
  });

  /// What to show the user. Three markets (Indonesia, Thailand and the USA)
  /// ship codes only, so those entries carry no short name.
  String get displayName => name.isEmpty ? code : name;

  @override
  String toString() => '$market/$code/$name';
}

/// Code <-> name lookup used by the portfolio entry sheet.
///
/// Sources, in order of preference:
///  1. the hosted copy of `mmcal_symbols.json` - the latest codes and short
///     names, refreshed in the background whenever the device is online,
///  2. the previously downloaded copy (a file in the app support directory,
///     with SharedPreferences as a fallback), so the app keeps working after
///     it goes offline,
///  3. the copy bundled at `assets/mmcal_symbols.json` - always available, even
///     on a first run with no network at all,
///  4. Yahoo Finance search, used only when all of the above miss.
///
/// Nothing here ever blocks saving: a miss just means the user types the code
/// or name themselves.
class SymbolLookup {
  /// Bundled fallback dictionary - present even with no network at all.
  static const String assetPath = 'assets/mmcal_symbols.json';

  /// Hosted copy of the same file, served from the project site. A 404 or a
  /// network failure simply falls back to the cached/bundled copy.
  /// https://gurdwarasahibmelaka.com/data/mmcal_symbols.json
  static const String remoteUrl =
      'https://www.gurdwarasahibmelaka.com/data/mmcal_symbols.json';

  static const String _cacheKey = 'mmcal_symbols_cache_v1';
  static const String _stampKey = 'mmcal_symbols_stamp_v1';
  static const String _cacheFileName = 'mmcal_symbols_cache.json';
  static const Duration _timeout = Duration(seconds: 15);
  static const Duration _refreshInterval = Duration(days: 1);

  static const String _yahooSearchUrl =
      'https://query1.finance.yahoo.com/v1/finance/search';

  final List<SymbolEntry> entries;

  /// market -> Yahoo Finance exchange suffix ('' for US listings).
  final Map<String, String> suffixes;

  /// market -> settlement currency.
  final Map<String, String> currencies;

  /// Identifies the exact payload this dictionary was parsed from, so
  /// re-downloading identical content is not treated as a change.
  final int fingerprint;

  /// Ready-made bridge for [PortfolioStore] identity matching.
  final SymbolAliases aliases;

  /// market -> its entries, so a keystroke only scans the market it is in
  /// rather than all ~41,000 rows.
  final Map<String, List<SymbolEntry>> _byMarket;

  SymbolLookup({
    required this.entries,
    required this.suffixes,
    required this.currencies,
    this.fingerprint = 0,
  })  : _byMarket = _indexByMarket(entries),
        aliases = SymbolAliases.build(
          entries.map((e) => (market: e.market, code: e.code, name: e.name)),
        );

  static Map<String, List<SymbolEntry>> _indexByMarket(
      List<SymbolEntry> entries) {
    final map = <String, List<SymbolEntry>>{};
    for (final e in entries) {
      (map[e.market] ??= <SymbolEntry>[]).add(e);
    }
    return map;
  }

  static final SymbolLookup empty = SymbolLookup(
    entries: const [],
    suffixes: const {},
    currencies: const {},
  );

  /// The dictionary currently installed for the whole process. Screens listen
  /// to this so a background refresh can swap in the newest published copy
  /// without anybody having to poll.
  static final ValueNotifier<SymbolLookup> current =
      ValueNotifier<SymbolLookup>(empty);

  static SymbolLookup? _shared;
  static Future<bool>? _refreshFuture;

  /// Offline-first instance: the downloaded copy when there is one, else the
  /// bundled asset. Never touches the network, so it is safe to await before
  /// showing the sheet; [refresh] picks up the published copy separately.
  static Future<SymbolLookup> instance() async {
    final existing = _shared;
    if (existing != null) return existing;
    final loaded = await load(allowRemote: false);
    _shared = loaded;
    if (!identical(current.value, loaded)) current.value = loaded;
    return loaded;
  }

  /// Clears the process-wide instance (used by tests).
  static void resetShared() {
    _shared = null;
    _refreshFuture = null;
    if (!identical(current.value, empty)) current.value = empty;
  }

  /// Installs a prepared instance so tests never touch the network or the
  /// asset bundle. Pass null to go back to lazy loading.
  static void debugSetShared(SymbolLookup? lookup) {
    _shared = lookup;
    if (lookup != null && !identical(current.value, lookup)) {
      current.value = lookup;
    }
  }

  /// Parses dictionary JSON - the same shape `tools/build_symbols.py` writes.
  /// Malformed input yields [empty] rather than throwing. A row without a name
  /// is kept: the Indonesia, Thailand and USA lists publish codes only.
  static SymbolLookup parse(String raw) {
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return empty;
    }
    if (data is! Map) return empty;

    final suffixes = <String, String>{};
    final currencies = <String, String>{};
    final markets = data['markets'];
    if (markets is Map) {
      markets.forEach((k, v) {
        if (v is Map) {
          suffixes[k.toString()] = (v['suffix'] ?? '').toString();
          currencies[k.toString()] = (v['currency'] ?? '').toString();
        }
      });
    }

    final entries = <SymbolEntry>[];
    final symbols = data['symbols'];
    if (symbols is List) {
      for (final row in symbols) {
        if (row is! Map) continue;
        final market = (row['m'] ?? '').toString().trim();
        final code = (row['c'] ?? '').toString().trim();
        final name = (row['n'] ?? '').toString().trim().toUpperCase();
        if (market.isEmpty || code.isEmpty) continue;
        entries.add(SymbolEntry(market: market, code: code, name: name));
      }
    }

    return SymbolLookup(
      entries: entries,
      suffixes: suffixes,
      currencies: currencies,
      fingerprint: raw.hashCode,
    );
  }

  static SymbolLookup? _ifNotEmpty(SymbolLookup lookup) =>
      lookup.entries.isEmpty ? null : lookup;

  /// Loads the best available dictionary. Never throws - worst case it returns
  /// [empty] and the sheet simply stops offering suggestions.
  static Future<SymbolLookup> load({
    http.Client? client,
    bool allowRemote = true,
  }) async {
    SymbolLookup? bundled;
    try {
      bundled = _ifNotEmpty(parse(await rootBundle.loadString(assetPath)));
    } catch (_) {
      bundled = null;
    }

    final cached = await _loadCache();

    if (!allowRemote) return bundled ?? cached ?? empty;

    if (cached != null && !await _isStale()) return cached;

    final raw = await _download(client: client);
    if (raw != null) {
      final fresh = _ifNotEmpty(parse(raw));
      if (fresh != null) {
        await _saveCache(raw);
        return fresh;
      }
    }
    // Hosted copy unavailable - prefer the bundled asset over a stale cache,
    // because the asset at least matches the shipped app.
    return bundled ?? cached ?? empty;
  }

  /// Downloads the newest published dictionary and installs it when it differs
  /// from the copy already loaded, then publishes it via [current]. Runs at
  /// most once per app run, never throws, and returns true only when a newer
  /// copy was installed. This is what keeps the app current while online.
  static Future<bool> refresh({http.Client? client}) {
    return _refreshFuture ??= _refresh(client: client);
  }

  static Future<bool> _refresh({http.Client? client}) async {
    final raw = await _download(client: client);
    if (raw == null) return false;
    final fresh = _ifNotEmpty(parse(raw));
    if (fresh == null) return false;

    final existing = _shared;
    if (existing != null && existing.fingerprint == fresh.fingerprint) {
      return false; // identical content - nothing to swap in
    }
    await _saveCache(raw);
    _shared = fresh;
    current.value = fresh;
    return true;
  }

  /// Downloads the published dictionary body. Null on any failure.
  static Future<String?> _download({http.Client? client}) async {
    final ownsClient = client == null;
    final http.Client c = client ?? http.Client();
    try {
      final res = await c.get(Uri.parse(remoteUrl)).timeout(_timeout);
      return res.statusCode == 200 ? res.body : null;
    } catch (_) {
      return null;
    } finally {
      // ignore: unawaited_futures
      if (ownsClient) c.close();
    }
  }

  /// Where the downloaded dictionary is kept. A file, not SharedPreferences:
  /// the dictionary is several megabytes, which would be a poor fit for the
  /// preferences store.
  static Future<File?> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_cacheFileName');
  }

  static Future<SymbolLookup?> _loadCache() async {
    final raw = await _readCache();
    if (raw == null || raw.isEmpty) return null;
    return _ifNotEmpty(parse(raw));
  }

  /// Reads the cached payload from the file cache, falling back to the
  /// SharedPreferences copy - which is also what keeps this class testable,
  /// because the path_provider plugin is absent under `flutter test`.
  static Future<String?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) return raw;
      }
    } catch (_) {
      // No file cache available - try preferences instead.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_cacheKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCache(String raw) async {
    var savedToFile = false;
    try {
      final file = await _cacheFile();
      if (file != null) {
        await file.writeAsString(raw);
        savedToFile = true;
      }
    } catch (_) {
      // Fall through to the preferences copy.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (savedToFile) {
        // Never keep two copies of a multi-megabyte payload.
        await prefs.remove(_cacheKey);
      } else {
        await prefs.setString(_cacheKey, raw);
      }
      await prefs.setInt(_stampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // A cache write failure is not worth surfacing.
    }
  }

  static Future<bool> _isStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stamp = prefs.getInt(_stampKey);
      if (stamp == null) return true;
      final saved = DateTime.fromMillisecondsSinceEpoch(stamp);
      return DateTime.now().difference(saved) >= _refreshInterval;
    } catch (_) {
      return true;
    }
  }

  /// Dictionary search for [query] within [market], best match first.
  ///
  /// Ranking: exact code, code prefix, name prefix, name containing, code
  /// containing. Codes are compared ignoring leading zeros so `700` finds
  /// Tencent's `700` and `0700` alike. Markets that publish codes without
  /// names (Indonesia, Thailand, USA) simply never match on name.
  List<SymbolEntry> suggest(String market, String query, {int limit = 8}) {
    final q = PortfolioStore.normalizeValue(query);
    if (q.length < 2) return const [];
    final candidates = _byMarket[market];
    if (candidates == null || candidates.isEmpty) return const [];
    final qLoose = _stripZeros(q);

    final scored = <List<Object>>[];
    for (final e in candidates) {
      final code = PortfolioStore.normalizeValue(e.code);
      final codeLoose = _stripZeros(code);
      final name = PortfolioStore.normalizeValue(e.name);

      int rank;
      if (code == q || codeLoose == qLoose) {
        rank = 0;
      } else if (code.startsWith(q) || codeLoose.startsWith(qLoose)) {
        rank = 1;
      } else if (name.startsWith(q)) {
        rank = 2;
      } else if (name.contains(q)) {
        rank = 3;
      } else if (code.contains(q)) {
        rank = 4;
      } else {
        continue;
      }
      scored.add([rank, e]);
    }

    scored.sort((a, b) {
      final byRank = (a[0] as int).compareTo(b[0] as int);
      if (byRank != 0) return byRank;
      return (a[1] as SymbolEntry).code.compareTo((b[1] as SymbolEntry).code);
    });

    return scored
        .take(limit)
        .map((row) => row[1] as SymbolEntry)
        .toList(growable: false);
  }

  /// The entry whose code or name is exactly [query] - `1155`, `MAYBANK`, or
  /// `0700` for Tencent's `700` - or null when nothing matches. Codes win over
  /// names. Used when the user saves without tapping a suggestion, so a stock
  /// the dictionary knows still stores its official code and short name.
  SymbolEntry? exactMatch(String market, String query) {
    final q = PortfolioStore.normalizeValue(query);
    if (q.isEmpty) return null;
    final candidates = _byMarket[market];
    if (candidates == null || candidates.isEmpty) return null;
    final qLoose = _stripZeros(q);

    SymbolEntry? byName;
    for (final e in candidates) {
      final code = PortfolioStore.normalizeValue(e.code);
      if (code == q || _stripZeros(code) == qLoose) return e;
      if (byName == null &&
          e.name.isNotEmpty &&
          PortfolioStore.normalizeValue(e.name) == q) {
        byName = e;
      }
    }
    return byName;
  }

  /// Dictionary first, Yahoo Finance only when the dictionary has no answer.
  /// Returns an empty list when offline - callers must never block on this.
  Future<List<SymbolEntry>> suggestWithFallback(
    String market,
    String query, {
    int limit = 8,
    http.Client? client,
    bool allowNetwork = true,
  }) async {
    final local = suggest(market, query, limit: limit);
    if (local.isNotEmpty || !allowNetwork) return local;
    return _yahooSearch(market, query, limit: limit, client: client);
  }

  /// Yahoo Finance symbol search, restricted to [market]'s exchange suffix.
  Future<List<SymbolEntry>> _yahooSearch(
    String market,
    String query, {
    int limit = 8,
    http.Client? client,
  }) async {
    final suffix = (suffixes[market] ?? '').toUpperCase();
    final ownsClient = client == null;
    final http.Client c = client ?? http.Client();
    try {
      final uri = Uri.parse('$_yahooSearchUrl'
          '?q=${Uri.encodeQueryComponent(query)}'
          '&quotesCount=10&newsCount=0&lang=en-US&region=US');
      final res = await c.get(uri, headers: const {
        // Yahoo rejects the default Dart user agent.
        'User-Agent': 'Mozilla/5.0',
      }).timeout(_timeout);
      if (res.statusCode != 200) return const [];

      final dynamic data = jsonDecode(res.body);
      if (data is! Map) return const [];
      final quotes = data['quotes'];
      if (quotes is! List) return const [];

      final out = <SymbolEntry>[];
      for (final dynamic raw in quotes) {
        if (raw is! Map) continue;
        final symbol = (raw['symbol'] ?? '').toString().trim().toUpperCase();
        if (symbol.isEmpty) continue;
        final name =
            (raw['shortname'] ?? raw['longname'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        // Keep only listings from the market the user is trading in, then
        // strip the exchange suffix to recover the local code.
        if (suffix.isNotEmpty) {
          if (!symbol.endsWith(suffix)) continue;
          final code = symbol.substring(0, symbol.length - suffix.length);
          if (code.isEmpty) continue;
          out.add(SymbolEntry(
              market: market, code: code, name: name.toUpperCase()));
        } else {
          out.add(SymbolEntry(
              market: market, code: symbol, name: name.toUpperCase()));
        }
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      // Offline, blocked or rate limited - no suggestions is fine.
      return const [];
    } finally {
      if (ownsClient) c.close();
    }
  }

  static String _stripZeros(String v) =>
      v.replaceFirst(RegExp(r'^0+(?=\d)'), '');
}