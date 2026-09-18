import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'quote_service.dart';

/// A single portfolio transaction. This ledger is the ONLY thing persisted:
/// every position, average price, subtotal and grouping is derived from it, so
/// edits and imports can never leave the screen in an inconsistent state.
class PortfolioTxn {
  /// Stable unique id (also used to de-duplicate imports).
  final String id;

  /// Market name exactly as the engine names it, e.g. 'Malaysia',
  /// 'United States (US)'.
  final String market;

  /// Settlement currency of [total]: 'MYR' for Malaysia and for foreign markets
  /// settled in MYR, otherwise the market's local currency (USD, SGD, HKD, ...).
  /// The same stock settled in two currencies is intentionally kept as two
  /// separate positions, because totals in different currencies cannot be
  /// averaged together.
  final String currency;

  final String code;
  final String name;

  /// ISO date, yyyy-MM-dd.
  final String date;

  /// 'buy' or 'sell'.
  final String side;

  final double qty;

  /// Net total in [currency]: gross + costs for a buy, net proceeds for a sell.
  /// User-editable so a broker figure variance can be absorbed.
  final double total;

  final String note;

  const PortfolioTxn({
    required this.id,
    required this.market,
    required this.currency,
    this.code = '',
    this.name = '',
    required this.date,
    this.side = 'buy',
    required this.qty,
    required this.total,
    this.note = '',
  });

  bool get isBuy => side != 'sell';

  /// Trims and upper-cases the identifier fields so the same stock always has a
  /// single stored spelling. Applied on save and on import, which keeps the UI,
  /// the grouping and the exports consistent (lookup itself is
  /// case-insensitive regardless).
  PortfolioTxn canonical() => PortfolioTxn(
        id: id,
        market: market.trim(),
        currency: currency.trim().toUpperCase(),
        code: code.trim().toUpperCase(),
        name: name.trim().toUpperCase(),
        date: date.trim(),
        side: isBuy ? 'buy' : 'sell',
        qty: qty,
        total: total,
        note: note,
      );

  PortfolioTxn copyWith({
    String? id,
    String? market,
    String? currency,
    String? code,
    String? name,
    String? date,
    String? side,
    double? qty,
    double? total,
    String? note,
  }) {
    return PortfolioTxn(
      id: id ?? this.id,
      market: market ?? this.market,
      currency: currency ?? this.currency,
      code: code ?? this.code,
      name: name ?? this.name,
      date: date ?? this.date,
      side: side ?? this.side,
      qty: qty ?? this.qty,
      total: total ?? this.total,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'market': market,
        'currency': currency,
        'code': code,
        'name': name,
        'date': date,
        'side': side,
        'qty': qty,
        'total': total,
        'note': note,
      };

  static PortfolioTxn? tryFromJson(Map<String, Object?> j) {
    final market = j['market']?.toString().trim() ?? '';
    final currency = j['currency']?.toString().trim() ?? '';
    final date = j['date']?.toString().trim() ?? '';
    final code = j['code']?.toString().trim() ?? '';
    final name = j['name']?.toString().trim() ?? '';
    final qty = _asDouble(j['qty']);
    final total = _asDouble(j['total']);
    if (market.isEmpty || currency.isEmpty || date.isEmpty) return null;
    if (qty == null || qty <= 0) return null;
    if (total == null || total <= 0) return null;
    if (code.isEmpty && name.isEmpty) return null;

    final rawSide = j['side']?.toString().trim().toLowerCase();
    final rawId = j['id']?.toString().trim() ?? '';
    return PortfolioTxn(
      id: rawId.isEmpty ? PortfolioStore.newId() : rawId,
      market: market,
      currency: currency,
      code: code,
      name: name,
      date: date,
      side: rawSide == 'sell' ? 'sell' : 'buy',
      qty: qty,
      total: total,
      note: j['note']?.toString() ?? '',
    ).canonical();
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}

/// A derived holding: one (market, currency, stock) line on the portfolio
/// screen. Never stored - always recomputed from the transaction ledger.
class PortfolioPosition {
  final String market;
  final String currency;
  final String code;
  final String name;

  /// Remaining quantity after buys and sells.
  final double qty;

  /// Remaining cost basis in [currency]. Selling reduces this at the running
  /// average cost, so a sale never changes the average price.
  final double cost;

  /// Most recent transaction date (yyyy-MM-dd) for this position.
  final String lastDate;

  /// The underlying transactions, oldest first.
  final List<PortfolioTxn> lots;

  const PortfolioPosition({
    required this.market,
    required this.currency,
    required this.code,
    required this.name,
    required this.qty,
    required this.cost,
    required this.lastDate,
    required this.lots,
  });

  /// Average price per unit = remaining cost / remaining qty.
  double get avgPrice => qty > 0 ? cost / qty : 0.0;

  /// Market value at the last done price, in [currency].
  double marketValue(Quote q) => qty * q.price;

  /// Unrealised profit/loss at the last done price, in [currency]. Selling
  /// reduces cost at the running average, so partially-sold lines stay correct.
  double unrealisedPL(Quote q) => (q.price - avgPrice) * qty;

  /// Key used to store this position's fetched quote.
  String get quoteKey => '$market/$code';

  String get displayCode => code.isNotEmpty ? code : '-';
  String get displayName => name.isNotEmpty ? name : '-';
}

/// Positions of one market + settlement currency, e.g. 'United States (US)' /
/// 'USD' or 'United States (US)' / 'MYR'.
class PortfolioGroup {
  final String market;
  final String currency;
  final List<PortfolioPosition> positions;

  const PortfolioGroup({
    required this.market,
    required this.currency,
    required this.positions,
  });

  double get subtotal => positions.fold(0.0, (a, p) => a + p.cost);
}

/// Optional bridge between a stock's code and its name, built from the symbol
/// dictionary. Without it, matching falls back to comparing raw codes/names, so
/// an entry typed with only a code cannot link to one typed with only a name.
/// With it, `1155` and `MAYBANK` resolve to the same holding.
class SymbolAliases {
  /// market -> normalised value (code or name) -> canonical code.
  final Map<String, Map<String, String>> byMarket;

  const SymbolAliases(this.byMarket);

  static const SymbolAliases empty = SymbolAliases({});

  bool get isEmpty => byMarket.isEmpty;

  /// Canonical code for [value] in [market], where [value] may be either the
  /// stock code or its name. Null when unknown.
  String? canonicalCode(String market, String value) {
    final index = byMarket[market];
    if (index == null || index.isEmpty) return null;
    final key = PortfolioStore.normalizeValue(value);
    if (key.isEmpty) return null;
    final direct = index[key];
    if (direct != null) return direct;
    // Numeric fallback so '5' still finds '0005'.
    if (RegExp(r'^[0-9]+$').hasMatch(key)) {
      return index[key.replaceFirst(RegExp(r'^0+(?=\d)'), '')];
    }
    return null;
  }

  /// Builds the index from (market, code, name) triples, registering both the
  /// raw and the zero-stripped code form.
  static SymbolAliases build(
    Iterable<({String market, String code, String name})> entries,
  ) {
    final byMarket = <String, Map<String, String>>{};
    for (final e in entries) {
      final code = e.code.trim();
      if (code.isEmpty) continue;
      final index = byMarket.putIfAbsent(e.market, () => <String, String>{});
      final normCode = PortfolioStore.normalizeValue(code);
      if (normCode.isNotEmpty) index[normCode] = code;
      final stripped = normCode.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (stripped.isNotEmpty) index[stripped] = code;
      final name = PortfolioStore.normalizeValue(e.name);
      if (name.isNotEmpty) index[name] = code;
    }
    return SymbolAliases(byMarket);
  }
}

/// Loads/saves the portfolio ledger and derives positions from it.
class PortfolioStore {
  PortfolioStore._();

  /// SharedPreferences key holding the JSON-encoded ledger.
  static const String prefKey = 'portfolio_txns_v1';

  /// Qty below this is treated as zero (floating point noise).
  static const double _qtyEpsilon = 1e-9;

  static int _seq = 0;

  /// A new unique id: microsecond timestamp plus a per-session counter so two
  /// entries created in the same microsecond still differ.
  static String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// Reads the ledger. Returns an empty list when nothing is stored or the
  /// stored JSON is corrupt (never throws).
  static Future<List<PortfolioTxn>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PortfolioTxn>[];
      for (final item in decoded) {
        if (item is Map) {
          final txn = PortfolioTxn.tryFromJson(
              item.map((k, v) => MapEntry(k.toString(), v)));
          if (txn != null) out.add(txn);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Overwrites the stored ledger. Every transaction is canonicalised on the
  /// way in, so codes and names are always stored trimmed and upper-cased
  /// regardless of which caller wrote them.
  static Future<void> saveAll(List<PortfolioTxn> txns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefKey,
        jsonEncode(txns.map((t) => t.canonical().toJson()).toList()));
  }

  /// Appends [txn] and returns the new ledger.
  static Future<List<PortfolioTxn>> add(PortfolioTxn txn) async {
    final all = await load()
      ..add(txn);
    await saveAll(all);
    return all;
  }

  /// Replaces the transaction with the same id (appends when absent).
  static Future<List<PortfolioTxn>> update(PortfolioTxn txn) async {
    final all = await load();
    final i = all.indexWhere((t) => t.id == txn.id);
    if (i >= 0) {
      all[i] = txn;
    } else {
      all.add(txn);
    }
    await saveAll(all);
    return all;
  }

  /// Removes one transaction by id.
  static Future<List<PortfolioTxn>> delete(String id) async {
    final all = await load()
      ..removeWhere((t) => t.id == id);
    await saveAll(all);
    return all;
  }

  /// Removes every transaction belonging to [position] (same market, currency
  /// and stock) - i.e. deletes the whole line.
  static Future<List<PortfolioTxn>> deletePosition(
      List<PortfolioTxn> current, PortfolioPosition position) async {
    final ids = position.lots.map((t) => t.id).toSet();
    final all = current.where((t) => !ids.contains(t.id)).toList();
    await saveAll(all);
    return all;
  }

  /// Clears everything.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKey);
  }

  /// Returns [current] with every lot of [position] renamed / re-coded, so a
  /// position level edit keeps the whole line consistent.
  static List<PortfolioTxn> applyPositionEdit(
    List<PortfolioTxn> current,
    PortfolioPosition position, {
    required String code,
    required String name,
  }) {
    final ids = position.lots.map((t) => t.id).toSet();
    return current
        .map((t) => ids.contains(t.id) ? t.copyWith(code: code, name: name) : t)
        .toList();
  }

  // ----------------------------------------------------------------
  // Derivation
  // ----------------------------------------------------------------

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
  static final RegExp _lettersOnly = RegExp(r'^[A-Z]+$');

  /// Normalises an identifier: upper-case, single spaces, no trailing dots
  /// (so UK tickers like `RR.` and `RR` match, while `BRK.B` keeps its class).
  static String normalizeValue(String v) => v
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\.+$'), '');

  /// Code form: as [normalizeValue] but with leading zeros dropped when the
  /// remainder is numeric, so 0005 and 5 are the same code.
  static String _normalizedCode(String v) {
    final s = normalizeValue(v);
    if (_digitsOnly.hasMatch(s)) {
      return s.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    }
    return s;
  }

  /// Identity tokens for a transaction - the basis of all matching.
  ///
  /// Beyond the raw code and name, this covers the "bought by code, sold by
  /// name" case:
  ///  - a digits-only *name* is also treated as a code (Bursa/HK/JP codes)
  ///  - a letters-only *code* is also usable as a name (US-style tickers)
  ///  - when [aliases] is supplied, either value is bridged to the canonical
  ///    code from the symbol dictionary, so 1155 and MAYBANK link up.
  static Set<String> identityTokens(PortfolioTxn t, [SymbolAliases? aliases]) {
    final out = <String>{};
    final c = _normalizedCode(t.code);
    final n = normalizeValue(t.name);

    if (c.isNotEmpty) out.add('C:$c');
    if (n.isNotEmpty) {
      out.add('N:$n');
      if (_digitsOnly.hasMatch(n)) out.add('C:$n');
    }
    if (c.isNotEmpty && _lettersOnly.hasMatch(c)) out.add('N:$c');

    if (aliases != null) {
      for (final raw in [t.code, t.name]) {
        final canonical = aliases.canonicalCode(t.market, raw);
        if (canonical != null && canonical.isNotEmpty) {
          out.add('C:${_normalizedCode(canonical)}');
        }
      }
    }
    return out;
  }

  /// Two transactions belong to the same position when they share the market
  /// and settlement currency AND at least one identity token.
  static bool sameStock(String market, String currency, PortfolioTxn a,
      PortfolioTxn b, [SymbolAliases? aliases]) {
    if (a.market != market || b.market != market) return false;
    if (a.currency != currency || b.currency != currency) return false;
    return identityTokens(a, aliases)
        .intersection(identityTokens(b, aliases))
        .isNotEmpty;
  }

  /// Finds the position matching a stock the user is typing, using the same
  /// identity tokens as [sameStock]. Used to validate a sell before it is saved.
  static PortfolioPosition? findPosition(
    List<PortfolioPosition> positions, {
    required String market,
    required String currency,
    required String code,
    required String name,
    SymbolAliases? aliases,
  }) {
    final probe = PortfolioTxn(
      id: '_probe',
      market: market,
      currency: currency,
      code: code,
      name: name,
      date: '1970-01-01',
      qty: 1,
      total: 1,
    );
    final probeTokens = identityTokens(probe, aliases);
    if (probeTokens.isEmpty) return null;

    for (final p in positions) {
      if (p.market != market || p.currency != currency) continue;
      // Compare against every lot: one lot may carry only the code, another
      // only the name, and either should match what the user typed.
      for (final lot in p.lots) {
        if (identityTokens(lot, aliases).intersection(probeTokens).isNotEmpty) {
          return p;
        }
      }
    }
    return null;
  }

  /// Builds positions from [txns], oldest first. [excludeId] is used when the
  /// positions are needed *without* one lot (e.g. validating an edit of it).
  ///
  /// Buys add qty and cost. Sells reduce qty and cost at the running average,
  /// so a partial sale keeps the average price and a full sale clears the line
  /// (the position is dropped). Overselling is clamped to the held qty.
  static List<PortfolioPosition> aggregate(
    Iterable<PortfolioTxn> txns, {
    String? excludeId,
    SymbolAliases? aliases,
  }) {
    final ordered = txns.where((t) => t.id != excludeId).toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    final work = <_Working>[];

    for (final t in ordered) {
      final tTokens = identityTokens(t, aliases);
      _Working? target;
      for (final w in work) {
        if (w.market == t.market &&
            w.currency == t.currency &&
            w.tokens.intersection(tTokens).isNotEmpty) {
          target = w;
          break;
        }
      }
      if (target == null) {
        target = _Working(
          market: t.market,
          currency: t.currency,
          code: t.code.trim(),
          name: t.name.trim(),
          lastDate: t.date,
          tokens: tTokens,
        );
        work.add(target);
      } else {
        target.tokens.addAll(tTokens);
        // Fill in blanks discovered on a later lot, and keep the newest date.
        if (target.code.isEmpty && t.code.trim().isNotEmpty) {
          target.code = t.code.trim();
        }
        if (target.name.isEmpty && t.name.trim().isNotEmpty) {
          target.name = t.name.trim();
        }
        if (t.date.compareTo(target.lastDate) > 0) target.lastDate = t.date;
      }

      if (t.isBuy) {
        target.qty += t.qty;
        target.cost += t.total;
      } else {
        final avg = target.qty > 0 ? target.cost / target.qty : 0.0;
        var reduce = t.qty;
        if (reduce > target.qty) reduce = target.qty;
        target.qty -= reduce;
        target.cost -= avg * reduce;
        if (target.qty <= _qtyEpsilon) {
          target.qty = 0;
          target.cost = 0;
        }
      }
      target.lots.add(t);
    }

    final positions = work
        .where((w) => w.qty > _qtyEpsilon)
        .map((w) => PortfolioPosition(
              market: w.market,
              currency: w.currency,
              code: w.code,
              name: w.name,
              qty: w.qty,
              cost: w.cost,
              lastDate: w.lastDate,
              lots: List<PortfolioTxn>.unmodifiable(w.lots),
            ))
        .toList();

    positions.sort((a, b) {
      final byMarket = a.market.compareTo(b.market);
      if (byMarket != 0) return byMarket;
      final byCurrency = a.currency.compareTo(b.currency);
      if (byCurrency != 0) return byCurrency;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return positions;
  }

  /// Groups [positions] by market, then settlement currency.
  static List<PortfolioGroup> group(List<PortfolioPosition> positions) {
    final byKey = <String, List<PortfolioPosition>>{};
    final order = <String>[];
    for (final p in positions) {
      final k = '${p.market}\u0000${p.currency}';
      var list = byKey[k];
      if (list == null) {
        list = <PortfolioPosition>[];
        byKey[k] = list;
        order.add(k);
      }
      list.add(p);
    }
    final groups = order.map((k) {
      final parts = k.split('\u0000');
      return PortfolioGroup(
        market: parts[0],
        currency: parts[1],
        positions: byKey[k]!,
      );
    }).toList()
      ..sort((a, b) {
        final m = a.market.compareTo(b.market);
        return m != 0 ? m : a.currency.compareTo(b.currency);
      });
    return groups;
  }

  /// Totals the remaining cost basis of [positions] per settlement currency,
  /// optionally adding market value and unrealised P/L from [quotes]. A
  /// position without a quote contributes cost only - its value/P/L is simply
  /// absent, and [CurrencyTotal.unquoted] counts it. Currencies are never
  /// converted or combined: every distinct currency gets its own
  /// [CurrencyTotal], ordered MYR first then alphabetical.
  static PortfolioTotals totals(
    List<PortfolioPosition> positions, {
    Map<String, Quote>? quotes,
  }) {
    final cost = <String, double>{};
    final value = <String, double>{};
    final pl = <String, double>{};
    final lines = <String, int>{};
    final unquoted = <String, int>{};
    final markets = <String, Set<String>>{};
    for (final p in positions) {
      final cur = p.currency;
      cost[cur] = (cost[cur] ?? 0) + p.cost;
      lines[cur] = (lines[cur] ?? 0) + 1;
      markets.putIfAbsent(cur, () => <String>{}).add(p.market);
      final q = quotes?[p.quoteKey];
      if (q == null) {
        unquoted[cur] = (unquoted[cur] ?? 0) + 1;
      } else {
        value[cur] = (value[cur] ?? 0) + p.marketValue(q);
        pl[cur] = (pl[cur] ?? 0) + p.unrealisedPL(q);
      }
    }
    final keys = cost.keys.toList()
      ..sort((a, b) {
        if (a == 'MYR') return -1;
        if (b == 'MYR') return 1;
        return a.compareTo(b);
      });
    return PortfolioTotals(
      byCurrency: [
        for (final k in keys)
          CurrencyTotal(
            currency: k,
            cost: cost[k]!,
            lines: lines[k]!,
            markets: markets[k]!.length,
            value: value[k],
            pl: pl[k],
            unquoted: unquoted[k] ?? 0,
          ),
      ],
    );
  }
}

/// Remaining cost basis (and, when quotes are available, market value and
/// unrealised P/L) summed for one settlement currency. Never converted.
class CurrencyTotal {
  final String currency;
  final double cost;

  /// Number of open positions in this currency.
  final int lines;

  /// Number of distinct markets holding this currency.
  final int markets;

  /// Summed market value, or null when no line in this currency has a quote.
  final double? value;

  /// Summed unrealised P/L, or null when no line in this currency has a quote.
  final double? pl;

  /// Positions in this currency that had no quote.
  final int unquoted;

  const CurrencyTotal({
    required this.currency,
    required this.cost,
    required this.lines,
    required this.markets,
    this.value,
    this.pl,
    this.unquoted = 0,
  });
}

/// Per-currency totals of a portfolio.
class PortfolioTotals {
  /// One entry per settlement currency present, MYR first then alphabetical.
  final List<CurrencyTotal> byCurrency;

  const PortfolioTotals({required this.byCurrency});

  bool get isSingleCurrency => byCurrency.length <= 1;

  CurrencyTotal? get single =>
      byCurrency.isEmpty ? null : (isSingleCurrency ? byCurrency.first : null);
}

/// Mutable accumulator used while deriving positions.
class _Working {
  final String market;
  final String currency;
  String code;
  String name;
  String lastDate;
  double qty = 0;
  double cost = 0;
  final List<PortfolioTxn> lots = [];

  /// Accumulated identity tokens, so a later lot can match on either the code
  /// or the name seen on any earlier lot of the same holding.
  final Set<String> tokens = {};

  _Working({
    required this.market,
    required this.currency,
    required this.code,
    required this.name,
    required this.lastDate,
    Set<String>? tokens,
  }) {
    if (tokens != null) this.tokens.addAll(tokens);
  }
}



