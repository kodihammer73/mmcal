import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_mmcal/services/portfolio_codec.dart';
import 'package:flutter_mmcal/services/portfolio_store.dart';

PortfolioTxn tx({
  String? id,
  String market = 'Malaysia',
  String currency = 'MYR',
  String code = '',
  String name = '',
  String date = '2026-08-01',
  String side = 'buy',
  double qty = 100,
  double total = 1000,
  double? price,
}) =>
    PortfolioTxn(
      id: id ?? PortfolioStore.newId(),
      market: market,
      currency: currency,
      code: code,
      name: name,
      date: date,
      side: side,
      qty: qty,
      total: total,
      price: price,
    );

void main() {
  group('encodeJson / decode', () {
    test('round trip preserves market, currency and stock fields', () {
      final txns = [
        tx(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', qty: 1500, total: 13985.45),
        tx(id: 'b', market: 'United States (US)', currency: 'USD', code: 'AAPL', name: 'Apple', qty: 150, total: 31275),
      ];
      final raw = PortfolioCodec.encodeJson(txns, at: DateTime.utc(2026, 9, 17));

      final envelope = jsonDecode(raw) as Map<String, Object?>;
      expect(envelope['schema'], 'portfolio_v1');
      expect(envelope['count'], 2);

      final res = PortfolioCodec.decode(raw);
      expect(res.ok, isTrue);
      expect(res.imported, 2);
      expect(res.skipped, 0);
      expect(res.txns.first.id, 'a');
      expect(res.txns.first.market, 'Malaysia');
      expect(res.txns.last.currency, 'USD');
      expect(res.txns.last.total, 31275);
    });

    test('accepts a bare JSON array', () {
      final raw = jsonEncode([
        tx(id: 'z', code: '1023', name: 'CIMB').toJson(),
      ]);
      final res = PortfolioCodec.decode(raw);
      expect(res.ok, isTrue);
      expect(res.imported, 1);
      expect(res.txns.single.name, 'CIMB');
    });

    test('rejects an unknown schema', () {
      final res = PortfolioCodec.decode('{"schema":"other_v9","transactions":[]}');
      expect(res.ok, isFalse);
      expect(res.fatal, contains('other_v9'));
      expect(res.txns, isEmpty);
    });

    test('rejects non-JSON and empty input', () {
      expect(PortfolioCodec.decode('').ok, isFalse);
      expect(PortfolioCodec.decode('hello').ok, isFalse);
      expect(PortfolioCodec.decode('42').ok, isFalse);
    });

    test('skips invalid rows and reports them', () {
      final res = PortfolioCodec.decode(jsonEncode({
        'schema': 'portfolio_v1',
        'transactions': [
          {
            'market': 'Malaysia', 'currency': 'MYR', 'code': '1155',
            'date': '2026-08-01', 'qty': 100, 'total': 900,
          },
          {'market': 'Malaysia'},
          {
            'market': 'Malaysia', 'currency': 'MYR', 'code': '1155',
            'date': '2026-08-01', 'qty': 0, 'total': 900,
          },
        ],
      }));
      expect(res.ok, isTrue);
      expect(res.imported, 1);
      expect(res.skipped, 2);
      expect(res.errors, hasLength(2));
    });

    test('defaults an unknown side to buy', () {
      final res = PortfolioCodec.decode(jsonEncode({
        'schema': 'portfolio_v1',
        'transactions': [
          {
            'market': 'Malaysia', 'currency': 'MYR', 'code': '1155',
            'date': '2026-08-01', 'qty': 100, 'total': 900, 'side': 'weird',
          },
        ],
      }));
      expect(res.txns.single.side, 'buy');
    });
  });

  group('merge', () {
    test('de-duplicates by id so re-importing cannot double holdings', () {
      final current = [tx(id: 'a', code: '1155', name: 'Maybank')];
      final incoming = [
        tx(id: 'a', code: '1155', name: 'Maybank'),
        tx(id: 'b', code: '5347', name: 'Tenaga'),
      ];
      final merged = PortfolioCodec.merge(current, incoming);
      expect(merged.map((t) => t.id).toList(), ['a', 'b']);
    });
  });

  group('encodeCsv', () {
    test('has a header and one row per transaction', () {
      final csv = PortfolioCodec.encodeCsv([
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 1000, total: 9200),
      ]);
      final lines = csv.trim().split('\n');
      expect(lines.first, 'Market,Currency,Code,Name,Date,Side,Qty,Price,Total');
      expect(lines, hasLength(2));
      expect(lines[1],
          startsWith('Malaysia,MYR,1155,Maybank,2026-08-01,buy,1000.0000,'));
    });

    test('price is the contract price while total stays cost-inclusive', () {
      final csv = PortfolioCodec.encodeCsv([
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 1000, total: 10050, price: 10),
      ]);
      final row = csv.trim().split('\n')[1].split(',');
      expect(row[7], '10.0000', reason: 'price excludes the costs');
      expect(row[8], '10050.00', reason: 'total is the net amount paid');
    });

    test('quotes fields containing commas', () {
      final csv = PortfolioCodec.encodeCsv([
        tx(id: 'a', code: 'ABC', name: 'Acme, Inc.'),
      ]);
      expect(csv, contains('"Acme, Inc."'));
    });
  });

  test('fileName embeds the date', () {
    expect(PortfolioCodec.fileName('json', at: DateTime(2026, 9, 17)),
        'mmcal_portfolio_2026-09-17.json');
    expect(PortfolioCodec.fileName('csv', at: DateTime(2026, 1, 5)),
        'mmcal_portfolio_2026-01-05.csv');
  });
}
