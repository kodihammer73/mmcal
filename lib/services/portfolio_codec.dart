import 'dart:convert';

import 'portfolio_store.dart';

/// Outcome of reading an exported portfolio file.
class ImportResult {
  /// Transactions that parsed cleanly (none when [fatal] is set).
  final List<PortfolioTxn> txns;

  /// How many rows were rejected.
  final int skipped;

  /// Human-readable reasons for skipped rows.
  final List<String> errors;

  /// Non-null when the file could not be read at all (e.g. wrong schema),
  /// in which case nothing should be imported.
  final String? fatal;

  const ImportResult({
    this.txns = const [],
    this.skipped = 0,
    this.errors = const [],
    this.fatal,
  });

  bool get ok => fatal == null;
  int get imported => txns.length;
}

/// JSON / CSV encoding and decoding for the portfolio ledger.
class PortfolioCodec {
  PortfolioCodec._();

  static const String appName = 'MMCal';

  /// Format marker so a future change can migrate old files.
  static const String schema = 'portfolio_v1';

  /// Versioned JSON envelope - the round-trippable export.
  static String encodeJson(List<PortfolioTxn> txns, {DateTime? at}) {
    final stamp = (at ?? DateTime.now()).toUtc().toIso8601String();
    return const JsonEncoder.withIndent('  ').convert({
      'app': appName,
      'schema': schema,
      'exportedAt': stamp,
      'count': txns.length,
      'transactions': txns.map((t) => t.toJson()).toList(),
    });
  }

  /// Spreadsheet-friendly CSV for viewing. Not re-importable - use JSON for
  /// round-trips.
  static String encodeCsv(List<PortfolioTxn> txns) {
    final b = StringBuffer();
    b.writeln('Market,Currency,Code,Name,Date,Side,Qty,Price,Total');
    for (final t in txns) {
      // Price is the contract price; Total is the net (cost-inclusive) amount,
      // so Total will not equal Price x Qty when fees were charged.
      final price = t.effectivePrice;
      b.writeln([
        _csv(t.market),
        _csv(t.currency),
        _csv(t.code),
        _csv(t.name),
        _csv(t.date),
        _csv(t.side),
        t.qty.toStringAsFixed(4),
        price.toStringAsFixed(4),
        t.total.toStringAsFixed(2),
      ].join(','));
    }
    return b.toString();
  }

  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// Suggested export file name, e.g. mmcal_portfolio_2026-09-17.json.
  static String fileName(String ext, {DateTime? at}) {
    final d = at ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return 'mmcal_portfolio_${d.year}-$mm-$dd.$ext';
  }

  /// Parses an exported file. Accepts the versioned envelope or a bare list of
  /// transactions. Invalid rows are skipped and reported, never silently kept.
  static ImportResult decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const ImportResult(fatal: 'The file is empty.');

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return const ImportResult(fatal: 'That file is not valid JSON.');
    }

    List<Object?> rows;
    if (decoded is List) {
      rows = decoded;
    } else if (decoded is Map) {
      final s = decoded['schema']?.toString();
      if (s != null && s.isNotEmpty && s != schema) {
        return ImportResult(fatal: 'Unsupported portfolio format "$s".');
      }
      final t = decoded['transactions'];
      if (t is! List) {
        return const ImportResult(fatal: 'No transactions found in the file.');
      }
      rows = t;
    } else {
      return const ImportResult(fatal: 'That file is not a portfolio export.');
    }

    final out = <PortfolioTxn>[];
    final errors = <String>[];
    var skipped = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map) {
        skipped++;
        errors.add('Row ${i + 1}: not an object');
        continue;
      }
      final txn = PortfolioTxn.tryFromJson(
          row.map((k, v) => MapEntry(k.toString(), v)));
      if (txn == null) {
        skipped++;
        errors.add('Row ${i + 1}: missing or invalid fields');
        continue;
      }
      out.add(txn);
    }
    return ImportResult(txns: out, skipped: skipped, errors: errors);
  }

  /// Appends [incoming] to [current], skipping ids that are already present so
  /// re-importing the same file cannot double the holdings.
  static List<PortfolioTxn> merge(
      List<PortfolioTxn> current, List<PortfolioTxn> incoming) {
    final ids = current.map((t) => t.id).toSet();
    final out = <PortfolioTxn>[...current];
    for (final t in incoming) {
      if (ids.add(t.id)) out.add(t);
    }
    return out;
  }
}

