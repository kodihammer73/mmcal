import 'dart:convert';

import 'package:http/http.dart' as http;

import 'symbol_lookup.dart';

/// A last-done price fetched from a public quote source.
class Quote {
  final double price;
  final double previousClose;

  /// Currency the price is quoted in, as reported by the source.
  final String currency;

  /// The resolved symbol, e.g. `1155.KL` - used for the session cache key.
  final String symbol;

  /// Which provider answered: 'yahoo' or 'google'.
  final String provider;

  final DateTime fetchedAt;

  const Quote({
    required this.price,
    required this.previousClose,
    required this.currency,
    required this.symbol,
    required this.provider,
    required this.fetchedAt,
  });

  double get change => previousClose > 0 ? price - previousClose : 0.0;

  double get changePercent =>
      previousClose > 0 ? (price - previousClose) / previousClose * 100 : 0.0;
}

/// Last-done prices for portfolio positions, from a chain of free public
/// sources, in order:
///
/// 1. Yahoo Finance chart API (`v8/finance/chart/{symbol}`) - clean JSON with
///    price, previous close and currency, addressed by local code + the
///    market's exchange suffix.
/// 2. Yahoo symbol search + chart - resolves odd spellings via the same
///    search endpoint the suggestion fallback uses, and learns Yahoo's short
///    name for the Google fallback below.
/// 3. Google Finance quote page - HTML fallback for letter tickers the
///    numeric code cannot address (e.g. `MAYBANK:KLSE`); the code is tried
///    as the ticker first, then Yahoo's short name.
///
/// Every failure returns null: the UI simply shows no price for that line.
/// Bloomberg and other terminal-grade sources are deliberately not used -
/// they block scraping and have no free endpoint.
class QuoteService {
  /// Master switch so tests and offline mode never touch the network.
  static bool networkEnabled = true;

  static const Duration _timeout = Duration(seconds: 6);

  /// Session cache lifetime - quotes are only ever a reference price.
  static const Duration _cacheTtl = Duration(seconds: 60);

  static const String _yahooChartUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart/';

  /// market -> Google Finance exchange tokens, tried in order.
  static const Map<String, List<String>> _googleExchanges = {
    'Malaysia': ['KLSE'],
    'Singapore': ['SGD'],
    'Hong Kong': ['HKG'],
    'United States (US)': ['NYSE', 'NASDAQ'],
    'Thailand': ['TBG'],
    'Indonesia': ['IDX'],
    'United Kingdom (UK)': ['LON'],
    'Australia': ['ASX'],
    'Japan': ['TYO'],
    'Canada': ['TSE'],
    'Germany': ['ETR'],
  };

  final SymbolLookup? lookup;

  /// Optional default client - lets tests inject a mock without threading a
  /// client through every call.
  final http.Client? _defaultClient;

  /// market/code -> cached quote with its fetch time.
  final Map<String, ({Quote quote, DateTime at})> _cache = {};

  QuoteService(this.lookup, {http.Client? httpClient})
      : _defaultClient = httpClient;

  static QuoteService? _shared;

  /// Process-wide instance built from the installed dictionary, so the screen
  /// keeps one session cache across rebuilds.
  static QuoteService shared(SymbolLookup? lookup) =>
      _shared ??= QuoteService(lookup);

  /// Installs a prepared instance so tests never touch the network.
  static void debugSetShared(QuoteService? service) => _shared = service;

  /// Fetches the last done price for [code] in [market]. [name] is the stored
  /// short name, used only as a Google ticker hint. Null on any failure.
  Future<Quote?> fetch(
    String market,
    String code, {
    String name = '',
    http.Client? client,
  }) async {
    if (!networkEnabled || code.trim().isEmpty) return null;

    final key = '$market/$code';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) {
      return hit.quote;
    }

    final quote =
        await _fetchUncached(market, code.trim(), name, client ?? _defaultClient);
    if (quote != null) {
      _cache[key] = (quote: quote, at: DateTime.now());
    }
    return quote;
  }

  /// Drops the session cache, e.g. when the user taps Refresh prices.
  void clearCache() => _cache.clear();

  Future<Quote?> _fetchUncached(
    String market,
    String code,
    String name,
    http.Client? client,
  ) async {
    // 1. Yahoo chart, addressed directly by code + exchange suffix.
    final direct = yahooSymbol(market, code);
    final directQuote = await _yahooChart(direct, client);
    if (directQuote != null) return directQuote;

    // 2. Yahoo search resolves the code/name to a symbol, then chart it.
    var shortName = name;
    final lookup = this.lookup;
    if (lookup != null) {
      final hits = await lookup
          .suggestWithFallback(market, code, limit: 1, client: client);
      if (hits.isNotEmpty) {
        final resolved = yahooSymbol(market, hits.first.code);
        if (resolved != direct) {
          final resolvedQuote = await _yahooChart(resolved, client);
          if (resolvedQuote != null) return resolvedQuote;
        }
        if (hits.first.name.isNotEmpty) shortName = hits.first.name;
      }
    }

    // 3. Google Finance HTML, code ticker first then the short name.
    for (final ticker in _googleTickers(code, shortName)) {
      for (final exchange in _googleExchanges[market] ?? const <String>[]) {
        final q = await _googleQuote(ticker, exchange, client);
        if (q != null) return q;
      }
    }
    return null;
  }

  /// Yahoo symbol for a local code: exchange suffix appended, UK's trailing
  /// dot (`RR.` -> `RRL` + `.L`), US share classes dotted (`BRK.B` -> `BRK-B`)
  /// and Hong Kong codes padded back to Yahoo's 4-digit form (`700` -> `0700.HK`).
  String yahooSymbol(String market, String code) {
    var base = code.trim().toUpperCase();
    if (base.isEmpty) return base;
    if (market == 'Hong Kong' && RegExp(r'^\d+$').hasMatch(base)) {
      base = base.padLeft(4, '0');
    }
    base = base.replaceAll('.', market == 'United States (US)' ? '-' : '');
    final suffix = lookup?.suffixes[market] ?? '';
    return '$base$suffix';
  }

  /// Ticker candidates for Google Finance: the code itself (works for US, HK,
  /// Japan and Germany) plus the dictionary/Yahoo short name.
  List<String> _googleTickers(String code, String name) {
    final out = <String>[];
    void add(String t) {
      final ticker = t.trim().toUpperCase();
      if (ticker.isNotEmpty && !out.contains(ticker)) out.add(ticker);
    }

    add(code.replaceAll('.', '-'));
    add(name);
    return out;
  }

  Future<Quote?> _yahooChart(String symbol, http.Client? client) async {
    if (symbol.isEmpty) return null;
    final ownsClient = client == null;
    final http.Client c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse('$_yahooChartUrl$symbol?range=1d&interval=1d'),
              headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final dynamic data = jsonDecode(res.body);
      final result = _chain(data, ['chart', 'result']);
      if (result is! List || result.isEmpty) return null;
      final first = result.first;
      if (first is! Map) return null;
      final meta = first['meta'];
      if (meta is! Map) return null;
      final price = _toDouble(meta['regularMarketPrice']);
      if (price == null || price <= 0) return null;
      return Quote(
        price: price,
        previousClose:
            _toDouble(meta['chartPreviousClose'] ?? meta['previousClose']) ??
                price,
        currency: (meta['currency'] ?? '').toString(),
        symbol: (meta['symbol'] ?? symbol).toString(),
        provider: 'yahoo',
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null; // offline, throttled, malformed - no price is fine
    } finally {
      if (ownsClient) c.close();
    }
  }

  Future<Quote?> _googleQuote(
    String ticker,
    String exchange,
    http.Client? client,
  ) async {
    if (ticker.isEmpty || exchange.isEmpty) return null;
    final ownsClient = client == null;
    final http.Client c = client ?? http.Client();
    try {
      final uri =
          Uri.parse('https://www.google.com/finance/quote/$ticker:$exchange');
      final res = await c
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(_timeout);
      if (res.statusCode != 200 || res.body.isEmpty) return null;

      // The quote page embeds the live values in data attributes.
      final priceMatch =
          RegExp(r'data-last-price="([\d.,]+)"').firstMatch(res.body);
      if (priceMatch == null) return null;
      final price = double.tryParse(priceMatch.group(1)!.replaceAll(',', ''));
      if (price == null || price <= 0) return null;

      final currency = RegExp(r'data-currency-code="([A-Z]+)"')
              .firstMatch(res.body)
              ?.group(1) ??
          '';
      // The previous-close figure is hard to pin down reliably in the markup;
      // fall back to the last price so change() simply reports 0.
      final prevMatch =
          RegExp(r'Previous close</td>[\s\S]{0,200}?>([\d.,]+)<')
              .firstMatch(res.body);
      final prev =
          double.tryParse(prevMatch?.group(1)?.replaceAll(',', '') ?? '') ??
              price;

      return Quote(
        price: price,
        previousClose: prev,
        currency: currency,
        symbol: '$ticker:$exchange',
        provider: 'google',
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    } finally {
      if (ownsClient) c.close();
    }
  }

  static dynamic _chain(dynamic node, List<String> path) {
    dynamic cur = node;
    for (final key in path) {
      if (cur is! Map) return null;
      cur = cur[key];
    }
    return cur;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
