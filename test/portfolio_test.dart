import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_mmcal/services/portfolio_store.dart';
import 'package:flutter_mmcal/services/quote_service.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('FIFO open lots and the displayed average price', () {
    // Costs stand in for the calculator's net amounts: RM50 on a RM10,000 buy.
    const netA = 10050.0;

    test('buy, sell then buy again shows the plain contract price', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 1000, total: netA, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', side: 'sell', qty: 1000,
            total: 10300, price: 10.30),
        tx(id: 'c', code: '1155', date: '2026-09-03', qty: 1000, total: netA, price: 10),
      ]).single;
      expect(p.qty, closeTo(1000, 1e-9));
      expect(p.avgPrice, closeTo(10.00, 1e-9), reason: 'avg is the buy price');
      expect(p.cost, closeTo(netA, 1e-6), reason: 'total keeps the net cost');
      expect(p.lots, hasLength(3));
    });

    test('two buys average their contract prices', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 1000, total: netA, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', qty: 1000, total: 10250,
            price: 10.20),
      ]).single;
      expect(p.qty, closeTo(2000, 1e-9));
      expect(p.avgPrice, closeTo(10.10, 1e-9));
      expect(p.cost, closeTo(20300, 1e-6));
    });

    test('a sell knocks off the oldest buy first', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 1000, total: netA, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', qty: 1000, total: 10250,
            price: 10.20),
        tx(id: 'c', code: '1155', date: '2026-09-03', side: 'sell', qty: 1000,
            total: 10300, price: 10.30),
      ]).single;
      expect(p.qty, closeTo(1000, 1e-9));
      expect(p.avgPrice, closeTo(10.20, 1e-9), reason: 'only the 10.20 lot is left');
      expect(p.cost, closeTo(10250, 1e-6));
      expect(p.openQtyByLot['a'], closeTo(0, 1e-9), reason: 'first buy is sold');
      expect(p.openQtyByLot['b'], closeTo(1000, 1e-9));
    });

    test('a partial sell keeps the lot price', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 1000, total: netA, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', side: 'sell', qty: 400,
            total: 4120, price: 10.30),
      ]).single;
      expect(p.qty, closeTo(600, 1e-9));
      expect(p.avgPrice, closeTo(10.00, 1e-9));
      expect(p.cost, closeTo(6030, 1e-6), reason: '60% of the net cost remains');
      expect(p.openQtyByLot['a'], closeTo(600, 1e-9));
    });

    test('a sell spanning two lots consumes in date order', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 1000, total: netA, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', qty: 1000, total: 10250,
            price: 10.20),
        tx(id: 'c', code: '1155', date: '2026-09-03', side: 'sell', qty: 1500,
            total: 15450, price: 10.30),
      ]).single;
      expect(p.qty, closeTo(500, 1e-9));
      expect(p.avgPrice, closeTo(10.20, 1e-9));
      expect(p.openQtyByLot['a'], closeTo(0, 1e-9));
      expect(p.openQtyByLot['b'], closeTo(500, 1e-9));
    });

    test('overselling is clamped and cannot go negative', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 100, total: 1005, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', side: 'sell', qty: 500,
            total: 5150, price: 10.30),
      ]);
      expect(p, isEmpty, reason: 'the holding is fully cleared, never negative');
    });

    test('entries saved before the price field fall back to total / qty', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', qty: 1000, total: netA),
      ]).single;
      expect(p.avgPrice, closeTo(10.05, 1e-9),
          reason: 'no stored price, so the cost-inclusive rate is the best guess');
    });

    test('unrealised P/L is measured against the cost-inclusive total', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', qty: 1000, total: netA, price: 10),
      ]).single;
      final q = Quote(
          price: 10.60,
          previousClose: 10.50,
          currency: 'MYR',
          symbol: '1155.KL',
          provider: 'yahoo',
          fetchedAt: DateTime(2026, 9, 18));
      // 1000 x 10.60 = 10,600 value less the 10,050 actually paid.
      expect(p.unrealisedPL(q), closeTo(550, 1e-6));
    });

    test('a sell then re-buy of the same stock stays one line', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', date: '2026-09-01', qty: 1000, total: netA, price: 10),
        tx(id: 'b', code: '1155', date: '2026-09-02', side: 'sell', qty: 1000,
            total: 10300, price: 10.30),
        tx(id: 'c', code: '1155', date: '2026-09-03', qty: 1000, total: netA, price: 10),
      ]);
      expect(p, hasLength(1));
      expect(p.single.lots, hasLength(3));
    });
  });

  group('totals', () {
    test('all-MYR positions collapse to one currency total', () {
      final t = PortfolioStore.totals(PortfolioStore.aggregate([
        tx(id: 'a', market: 'Malaysia', code: '1155', qty: 1000, total: 9200),
        tx(id: 'b', market: 'Singapore', currency: 'MYR', code: 'D05',
            name: 'Singtel', qty: 500, total: 3000),
      ]));
      expect(t.isSingleCurrency, isTrue);
      expect(t.byCurrency, hasLength(1));
      final total = t.byCurrency.single;
      expect(total.currency, 'MYR');
      expect(total.cost, closeTo(12200, 1e-9));
      expect(total.lines, 2);
      expect(total.markets, 2);
    });

    test('each settlement currency gets its own unconverted total', () {
      final t = PortfolioStore.totals(PortfolioStore.aggregate([
        tx(id: 'a', market: 'Malaysia', code: '1155', qty: 1000, total: 9200),
        tx(id: 'b', market: 'United States (US)', currency: 'USD', code: 'AAPL',
            name: 'Apple', qty: 10, total: 3127.5),
        tx(id: 'c', market: 'United States (US)', currency: 'USD', code: 'MSFT',
            name: 'Microsoft', qty: 5, total: 2000),
      ]));
      expect(t.isSingleCurrency, isFalse);
      expect(t.byCurrency, hasLength(2));
      expect(t.byCurrency[0].currency, 'MYR', reason: 'MYR sorts first');
      expect(t.byCurrency[0].cost, closeTo(9200, 1e-9));
      expect(t.byCurrency[0].markets, 1);
      expect(t.byCurrency[1].currency, 'USD');
      expect(t.byCurrency[1].cost, closeTo(5127.5, 1e-9));
      expect(t.byCurrency[1].lines, 2);
      expect(t.byCurrency[1].markets, 1);
    });

    test('three currencies order MYR first then alphabetical', () {
      final t = PortfolioStore.totals(PortfolioStore.aggregate([
        tx(id: 'a', market: 'Hong Kong', currency: 'HKD', code: '700',
            name: 'TENCENT', total: 20000),
        tx(id: 'b', market: 'Malaysia', code: '1155', total: 100),
        tx(id: 'c', market: 'Japan', currency: 'JPY', code: '7203',
            name: 'TOYOTA', total: 50000),
      ]));
      expect(t.byCurrency.map((e) => e.currency).toList(),
          ['MYR', 'HKD', 'JPY']);
    });

    test('empty ledger yields no totals', () {
      expect(PortfolioStore.totals([]).byCurrency, isEmpty);
    });

    test('quotes add market value and unrealised P/L per currency', () {
      final positions = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 1000, total: 9200),
        tx(id: 'b', code: 'D05', name: 'Singtel', currency: 'MYR',
            market: 'Singapore', qty: 500, total: 3000),
      ]);
      final quotes = <String, Quote>{
        positions[0].quoteKey: Quote(
            price: 10.36,
            previousClose: 10.42,
            currency: 'MYR',
            symbol: '1155.KL',
            provider: 'yahoo',
            fetchedAt: DateTime(2026, 9, 18)),
      };
      final t = PortfolioStore.totals(positions, quotes: quotes);
      final myr = t.byCurrency.single;
      expect(myr.cost, closeTo(12200, 1e-9));
      // Value covers only the quoted line: 1000 x 10.36.
      expect(myr.value, closeTo(10360, 1e-9));
      // P/L for the quoted line: (10.36 - 9.20) x 1000.
      expect(myr.pl, closeTo(1160, 1e-9));
      expect(myr.unquoted, 1, reason: 'D05 has no quote');
    });

    test('position helpers compute value and P/L from a quote', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 1000, total: 9200),
      ]).single;
      final q = Quote(
          price: 10.36,
          previousClose: 10.42,
          currency: 'MYR',
          symbol: '1155.KL',
          provider: 'yahoo',
          fetchedAt: DateTime(2026, 9, 18));
      expect(p.marketValue(q), closeTo(10360, 1e-9));
      expect(p.unrealisedPL(q), closeTo(1160, 1e-9));
    });
  });

  group('aggregate', () {
    test('single buy becomes one position', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 1000, total: 9200),
      ]);
      expect(p, hasLength(1));
      expect(p.first.qty, 1000);
      expect(p.first.cost, 9200);
      expect(p.first.avgPrice, closeTo(9.2, 1e-9));
      expect(p.first.lastDate, '2026-08-01');
      expect(p.first.lots, hasLength(1));
    });

    test('subsequent buy of same code averages the price', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: 'Maybank', date: '2026-08-12', qty: 1000, total: 9219.60),
        tx(id: 'b', code: '1155', name: 'Maybank', date: '2026-08-25', qty: 500, total: 4765.85),
      ]);
      expect(p, hasLength(1));
      expect(p.first.qty, closeTo(1500, 1e-9));
      expect(p.first.cost, closeTo(13985.45, 1e-6));
      expect(p.first.avgPrice, closeTo(13985.45 / 1500, 1e-9));
      expect(p.first.lastDate, '2026-08-25', reason: 'shows the latest txn date');
      expect(p.first.lots, hasLength(2));
    });

    test('matches on name when the code is blank', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '', name: 'Tenaga', qty: 100, total: 1000),
        tx(id: 'b', code: '', name: 'tenaga', date: '2026-08-02', qty: 200, total: 2000),
      ]);
      expect(p, hasLength(1));
      expect(p.first.qty, 300);
    });

    test('partial sell reduces qty at average cost and keeps the average', () {
      const bought = 14045.0;
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1023', name: 'CIMB', date: '2026-07-10', qty: 2000, total: bought),
        tx(id: 'b', code: '1023', name: 'CIMB', date: '2026-09-05', side: 'sell', qty: 800, total: 5884.80),
      ]);
      expect(p, hasLength(1));
      expect(p.first.qty, closeTo(1200, 1e-9));
      expect(p.first.cost, closeTo(bought - 800 * (bought / 2000), 1e-6));
      expect(p.first.avgPrice, closeTo(bought / 2000, 1e-9));
    });

    test('full sell clears the line', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: 'NVDA', name: 'NVIDIA', qty: 20, total: 2401),
        tx(id: 'b', code: 'NVDA', name: 'NVIDIA', date: '2026-08-20', side: 'sell', qty: 20, total: 2700),
      ]);
      expect(p, isEmpty);
    });

    test('sell with no purchase record creates nothing', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: 'TSLA', name: 'Tesla', side: 'sell', qty: 10, total: 3000),
      ]);
      expect(p, isEmpty);
    });

    test('oversell is clamped to the held qty', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: 'X', name: 'X', qty: 100, total: 1000),
        tx(id: 'b', code: 'X', name: 'X', date: '2026-08-02', side: 'sell', qty: 500, total: 6000),
      ]);
      expect(p, isEmpty);
    });

    test('same stock in two settlement currencies stays as two positions', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', market: 'United States (US)', currency: 'USD', code: 'AAPL', name: 'Apple', qty: 150, total: 31275),
        tx(id: 'b', market: 'United States (US)', currency: 'MYR', code: 'AAPL', name: 'Apple', qty: 100, total: 88410.50),
      ]);
      expect(p, hasLength(2));
      expect(p.map((e) => e.currency).toSet(), {'USD', 'MYR'});
    });

    test('excludeId omits one lot (used to validate an edit)', () {
      final lots = [
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 100, total: 900),
        tx(id: 'b', code: '1155', name: 'Maybank', date: '2026-08-02', qty: 100, total: 950),
      ];
      final without = PortfolioStore.aggregate(lots, excludeId: 'b');
      expect(without.single.qty, 100);
      expect(without.single.cost, 900);
    });
  });

  group('group', () {
    test('groups by market then currency', () {
      final positions = PortfolioStore.aggregate([
        tx(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', qty: 100, total: 900),
        tx(id: 'b', market: 'United States (US)', currency: 'USD', code: 'AAPL', name: 'Apple', qty: 10, total: 2000),
        tx(id: 'c', market: 'United States (US)', currency: 'MYR', code: 'AAPL', name: 'Apple', qty: 5, total: 5000),
      ]);
      final groups = PortfolioStore.group(positions);
      expect(groups, hasLength(3));
      expect(groups.first.market, 'Malaysia');
      final us = groups.where((g) => g.market == 'United States (US)').toList();
      expect(us.map((g) => g.currency).toList(), ['MYR', 'USD']);
      expect(us.firstWhere((g) => g.currency == 'USD').subtotal, 2000);
    });
  });

  group('persistence', () {
    test('add / load / update / delete round trip', () async {
      SharedPreferences.setMockInitialValues({});
      await PortfolioStore.clearAll();
      expect(await PortfolioStore.load(), isEmpty);

      await PortfolioStore.add(tx(id: 'a', code: '1155', name: 'Maybank', qty: 100, total: 900));
      var all = await PortfolioStore.load();
      expect(all, hasLength(1));
      expect(all.first.total, 900);
      expect(all.first.code, '1155');

      await PortfolioStore.update(all.first.copyWith(total: 950));
      all = await PortfolioStore.load();
      expect(all.first.total, 950);

      await PortfolioStore.delete('a');
      expect(await PortfolioStore.load(), isEmpty);
    });

    test('corrupt stored JSON is ignored, not thrown', () async {
      SharedPreferences.setMockInitialValues({PortfolioStore.prefKey: 'not-json'});
      expect(await PortfolioStore.load(), isEmpty);
    });

    test('applyPositionEdit renames / re-codes every lot', () {
      final all = [
        tx(id: 'a', code: 'OLD', name: 'Old Name', qty: 100, total: 900),
        tx(id: 'b', code: 'OLD', name: 'Old Name', date: '2026-08-02', qty: 50, total: 450),
      ];
      final pos = PortfolioStore.aggregate(all).single;
      final edited = PortfolioStore.applyPositionEdit(all, pos, code: 'NEW', name: 'New Name');
      expect(edited.every((e) => e.code == 'NEW' && e.name == 'New Name'), isTrue);
      final reAgg = PortfolioStore.aggregate(edited).single;
      expect(reAgg.code, 'NEW');
      expect(reAgg.qty, 150);
    });

    test('deletePosition removes every lot of that line', () async {
      SharedPreferences.setMockInitialValues({});
      final all = [
        tx(id: 'a', code: '1155', name: 'Maybank', qty: 100, total: 900),
        tx(id: 'b', code: '1155', name: 'Maybank', date: '2026-08-02', qty: 100, total: 950),
        tx(id: 'c', code: '5347', name: 'Tenaga', qty: 10, total: 140),
      ];
      final pos = PortfolioStore.aggregate(all).firstWhere((p) => p.code == '1155');
      final left = await PortfolioStore.deletePosition(all, pos);
      expect(left, hasLength(1));
      expect(left.single.code, '5347');
    });
  });

  group('identity matching', () {
    test('buy by code matches a sell typed as that code in the name field', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: '', qty: 1000, total: 9200),
        tx(id: 'b', code: '', name: '1155', date: '2026-09-05', side: 'sell', qty: 400, total: 4000),
      ]);
      expect(p, hasLength(1));
      expect(p.single.qty, closeTo(600, 1e-9));
    });

    test('buy by ticker matches a sell typed as the ticker in the name field',
        () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', market: 'United States (US)', currency: 'USD', code: 'AAPL', name: '', qty: 100, total: 21000),
        tx(id: 'b', market: 'United States (US)', currency: 'USD', code: '', name: 'aapl', date: '2026-09-05', side: 'sell', qty: 40, total: 9000),
      ]);
      expect(p, hasLength(1));
      expect(p.single.qty, closeTo(60, 1e-9));
    });

    test('leading zeros do not split a holding (0005 vs 5)', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', market: 'Hong Kong', currency: 'HKD', code: '0005', name: 'HSBC HOLDINGS', qty: 400, total: 20000),
        tx(id: 'b', market: 'Hong Kong', currency: 'HKD', code: '', name: '5', date: '2026-09-05', side: 'sell', qty: 100, total: 5000),
      ]);
      expect(p, hasLength(1));
      expect(p.single.qty, closeTo(300, 1e-9));
    });

    test('trailing-dot UK tickers match their plain form', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', market: 'United Kingdom (UK)', currency: 'GBP', code: 'RR.', name: 'ROLLS-ROYCE', qty: 100, total: 500),
        tx(id: 'b', market: 'United Kingdom (UK)', currency: 'GBP', code: 'RR', name: '', date: '2026-09-05', side: 'sell', qty: 40, total: 250),
      ]);
      expect(p, hasLength(1));
      expect(p.single.qty, closeTo(60, 1e-9));
    });

    test('never merges across markets or settlement currencies', () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'MAYBANK', qty: 100, total: 900),
        tx(id: 'b', market: 'Malaysia', currency: 'USD', code: '1155', name: 'MAYBANK', qty: 100, total: 900),
        tx(id: 'c', market: 'Singapore', currency: 'MYR', code: '1155', name: 'MAYBANK', qty: 100, total: 900),
      ]);
      expect(p, hasLength(3));
    });

    test('without aliases a code-only entry cannot link to a name-only entry',
        () {
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: '', qty: 1000, total: 9200),
        tx(id: 'b', code: '', name: 'MAYBANK', date: '2026-09-05', qty: 500, total: 4600),
      ]);
      // Documented limitation: bridging these needs the symbol dictionary.
      expect(p, hasLength(2));
    });

    test('with aliases a code-only entry links to a name-only entry', () {
      final aliases = SymbolAliases.build([
        (market: 'Malaysia', code: '1155', name: 'MAYBANK'),
      ]);
      final p = PortfolioStore.aggregate([
        tx(id: 'a', code: '1155', name: '', qty: 1000, total: 9200),
        tx(id: 'b', code: '', name: 'MAYBANK', date: '2026-09-05', qty: 500, total: 4600),
      ], aliases: aliases);
      expect(p, hasLength(1));
      expect(p.single.qty, closeTo(1500, 1e-9));
    });

    test('with aliases a sell typed by name validates against a code-only buy',
        () {
      final aliases = SymbolAliases.build([
        (market: 'Malaysia', code: '1155', name: 'MAYBANK'),
      ]);
      final all = [
        tx(id: 'a', code: '1155', name: '', qty: 1000, total: 9200),
      ];
      final pos = PortfolioStore.aggregate(all, aliases: aliases).single;
      final found = PortfolioStore.findPosition(
        PortfolioStore.aggregate(all, aliases: aliases),
        market: 'Malaysia',
        currency: 'MYR',
        code: '',
        name: 'Maybank',
        aliases: aliases,
      );
      expect(found, isNotNull);
      expect(found!.qty, pos.qty);
    });

    test('canonical() upper-cases and trims the code and name', () {
      final t = tx(id: 'a', code: '  aapl ', name: ' apple inc. ', qty: 1, total: 1)
          .canonical();
      expect(t.code, 'AAPL');
      expect(t.name, 'APPLE INC.');
    });

    test('entries are canonicalised on save', () async {
      SharedPreferences.setMockInitialValues({});
      await PortfolioStore.saveAll([
        tx(id: 'a', code: ' 1155 ', name: ' maybank ', qty: 10, total: 90),
      ]);
      final all = await PortfolioStore.load();
      expect(all.single.code, '1155');
      expect(all.single.name, 'MAYBANK');
    });
  });
}

