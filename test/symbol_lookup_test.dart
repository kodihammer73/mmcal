import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_mmcal/services/portfolio_store.dart';
import 'package:flutter_mmcal/services/symbol_lookup.dart';

/// Small offline dictionary that mirrors the shipped JSON shape.
const _sample = '''
{
  "version": 1,
  "markets": {
    "Malaysia": {"currency": "MYR", "suffix": ".KL"},
    "Hong Kong": {"currency": "HKD", "suffix": ".HK"},
    "United States (US)": {"currency": "USD", "suffix": ""}
  },
  "symbols": [
    {"m": "Malaysia", "c": "1155", "n": "MAYBANK"},
    {"m": "Malaysia", "c": "1023", "n": "CIMB"},
    {"m": "Malaysia", "c": "1066", "n": "RHB BANK"},
    {"m": "Malaysia", "c": "1295", "n": "PBBANK"},
    {"m": "Hong Kong", "c": "0700", "n": "TENCENT"},
    {"m": "United States (US)", "c": "AAPL", "n": "APPLE"}
  ]
}
''';

/// Stand-in for the file published on the project site at
/// `SymbolLookup.remoteUrl`. Note it deliberately omits `1155`: a published
/// file replaces the bundled dictionary rather than merging with it.
const _hosted = '''
{
  "version": 1,
  "updated": "2026-09-17",
  "markets": {
    "Malaysia": {"currency": "MYR", "suffix": ".KL"},
    "Hong Kong": {"currency": "HKD", "suffix": ".HK"}
  },
  "symbols": [
    {"m": "Malaysia", "c": "9999", "n": "HOSTED ONLY"},
    {"m": "Hong Kong", "c": "0005", "n": "HSBC"}
  ]
}
''';

PortfolioTxn txn({
  required String id,
  required String code,
  required String name,
  required String date,
  String side = 'buy',
  required double qty,
  required double total,
  String market = 'Malaysia',
  String currency = 'MYR',
}) =>
    PortfolioTxn(
      id: id,
      market: market,
      currency: currency,
      code: code,
      name: name,
      date: date,
      side: side,
      qty: qty,
      total: total,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parse', () {
    test('reads markets, currencies, suffixes and symbols', () {
      final l = SymbolLookup.parse(_sample);
      expect(l.entries, hasLength(6));
      expect(l.currencies['Malaysia'], 'MYR');
      expect(l.suffixes['Hong Kong'], '.HK');
      expect(l.suffixes['United States (US)'], '');
      expect(l.entries.first.code, '1155');
    });

    test('malformed payloads yield an empty lookup instead of throwing', () {
      expect(SymbolLookup.parse('not json at all').entries, isEmpty);
      expect(SymbolLookup.parse('[]').entries, isEmpty);
      expect(SymbolLookup.parse('{}').entries, isEmpty);
    });

    test('rows missing a market or code are skipped, a missing name is kept',
        () {
      final l = SymbolLookup.parse('''
      {"markets": {}, "symbols": [
        {"m": "Malaysia", "c": "", "n": "NO CODE"},
        {"m": "", "c": "1234", "n": "NO MARKET"},
        {"m": "Malaysia", "c": "1234", "n": ""},
        {"m": "Malaysia", "c": "1234", "n": "OK"},
        "junk"
      ]}
      ''');
      // Indonesia, Thailand and the USA publish codes without names, so an
      // empty name must not drop the row.
      expect(l.entries, hasLength(2));
      expect(l.entries.first.name, isEmpty);
      expect(l.entries.first.displayName, '1234');
      expect(l.entries.last.name, 'OK');
    });
  });

  group('suggest', () {
    final l = SymbolLookup.parse(_sample);

    test('an exact code ranks first', () {
      expect(l.suggest('Malaysia', '1155').first.code, '1155');
    });

    test('a code prefix matches', () {
      final codes = l.suggest('Malaysia', '10').map((e) => e.code).toList();
      expect(codes, containsAll(<String>['1023', '1066']));
    });

    test('a name prefix or substring matches', () {
      expect(l.suggest('Malaysia', 'MAYBANK').first.code, '1155');
      expect(l.suggest('Malaysia', 'maybank').first.code, '1155');
      expect(l.suggest('Malaysia', 'BANK').first.code, '1066');
    });

    test('leading zeros are ignored on both sides of the comparison', () {
      expect(l.suggest('Hong Kong', '700').first.code, '0700');
      expect(l.suggest('Hong Kong', '0700').first.code, '0700');
      expect(l.suggest('Hong Kong', 'TENCENT').first.code, '0700');
    });

    test('is scoped to the market being traded', () {
      expect(l.suggest('Malaysia', 'AAPL'), isEmpty);
      expect(l.suggest('United States (US)', 'AAPL'), hasLength(1));
    });

    test('needs at least two characters', () {
      expect(l.suggest('Malaysia', '1'), isEmpty);
      expect(l.suggest('Malaysia', ''), isEmpty);
    });

    test('honours the limit and returns nothing for unknown queries', () {
      expect(l.suggest('Malaysia', '10', limit: 1), hasLength(1));
      expect(l.suggest('Malaysia', 'ZZZZ'), isEmpty);
    });

    test('exactMatch resolves a code or a name and ignores affixes', () {
      expect(l.exactMatch('Malaysia', '1155')!.name, 'MAYBANK');
      expect(l.exactMatch('Malaysia', 'maybank')!.code, '1155');
      expect(l.exactMatch('Hong Kong', '0700')!.code, '0700');
      expect(l.exactMatch('Malaysia', 'may'), isNull);
      expect(l.exactMatch('Malaysia', 'ZZZZ'), isNull);
    });
  });

  group('Yahoo fallback', () {
    final l = SymbolLookup.parse(_sample);

    test('is used only when the dictionary has no answer', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(
          jsonEncode({
            'quotes': [
              {
                'symbol': '9999.KL',
                'shortname': 'SOMETHING BHD',
                'quoteType': 'EQUITY',
              },
            ],
          }),
          200,
        );
      });

      final hit =
          await l.suggestWithFallback('Malaysia', '1155', client: client);
      expect(hit.first.code, '1155');
      expect(calls, 0, reason: 'a dictionary hit must not touch the network');

      final miss =
          await l.suggestWithFallback('Malaysia', '9999', client: client);
      expect(calls, 1);
      expect(miss.single.code, '9999');
      expect(miss.single.name, 'SOMETHING BHD');
    });

    test('drops quotes belonging to another exchange', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'quotes': [
                {'symbol': '9999.HK', 'shortname': 'WRONG EXCHANGE'},
                {'symbol': '9999.KL', 'shortname': 'RIGHT EXCHANGE'},
              ],
            }),
            200,
          ));
      final out =
          await l.suggestWithFallback('Malaysia', '9999', client: client);
      expect(out, hasLength(1));
      expect(out.single.name, 'RIGHT EXCHANGE');
    });

    test('keeps the full symbol for markets without a suffix', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'quotes': [
                {'symbol': 'MSFT', 'shortname': 'MICROSOFT'},
              ],
            }),
            200,
          ));
      final out = await l.suggestWithFallback('United States (US)', 'MSFT',
          client: client);
      expect(out.single.code, 'MSFT');
      expect(out.single.market, 'United States (US)');
    });

    test('never throws when the request fails or is rejected', () async {
      final offline =
          MockClient((req) async => throw http.ClientException('offline'));
      final throttled = MockClient((req) async => http.Response('nope', 429));
      final garbage = MockClient((req) async => http.Response('<html>', 200));

      for (final client in [offline, throttled, garbage]) {
        expect(
          await l.suggestWithFallback('Malaysia', '9999', client: client),
          isEmpty,
        );
      }
    });

    test('can be switched off so the app stays fully offline', () async {
      expect(
        await l.suggestWithFallback('Malaysia', '9999', allowNetwork: false),
        isEmpty,
      );
    });
  });

  group('aliases', () {
    final l = SymbolLookup.parse(_sample);

    test('resolve a name to its code, a code to itself, and nothing else', () {
      expect(l.aliases.canonicalCode('Malaysia', 'maybank'), '1155');
      expect(l.aliases.canonicalCode('Malaysia', '1155'), '1155');
      expect(l.aliases.canonicalCode('Malaysia', '0'), isNull);
      expect(l.aliases.canonicalCode('Malaysia', 'unknown'), isNull);
      expect(l.aliases.canonicalCode('Nowhere', '1155'), isNull);
    });

    test('let a code-only buy match a name-only sell', () {
      final txns = [
        txn(id: 'a', code: '1155', name: '', date: '2026-08-01', qty: 1000, total: 9200),
        txn(id: 'b', code: '', name: 'MAYBANK', date: '2026-08-02', side: 'sell', qty: 400, total: 4000),
      ];
      // Unbridged, the sell finds no holding and is dropped, leaving the buy
      // untouched at its full quantity.
      final unbridged = PortfolioStore.aggregate(txns);
      expect(unbridged, hasLength(1));
      expect(unbridged.single.qty, closeTo(1000, 1e-9));

      final merged = PortfolioStore.aggregate(txns, aliases: l.aliases);
      expect(merged, hasLength(1));
      expect(merged.single.qty, closeTo(600, 1e-9));
    });

    test('also let a sell typed by name validate against a code-only buy', () {
      final txns = [
        txn(id: 'a', code: '1155', name: '', date: '2026-08-01', qty: 1000, total: 9200),
      ];
      final positions = PortfolioStore.aggregate(txns, aliases: l.aliases);
      final found = PortfolioStore.findPosition(
        positions,
        market: 'Malaysia',
        currency: 'MYR',
        code: '',
        name: 'Maybank',
        aliases: l.aliases,
      );
      expect(found, isNotNull);
      expect(found!.qty, closeTo(1000, 1e-9));
    });
  });

  group('hosted dictionary', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SymbolLookup.resetShared();
    });

    test('is fetched from the project site and replaces the bundled copy',
        () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), SymbolLookup.remoteUrl);
        return http.Response(_hosted, 200);
      });

      final l = await SymbolLookup.load(client: client);
      expect(l.suggest('Malaysia', '9999').first.name, 'HOSTED ONLY');
      // A published file is the source of truth, so what it omits is gone.
      expect(l.suggest('Malaysia', '1155'), isEmpty);
    });

    test('is cached, so later runs work without the network', () async {
      final online = MockClient((req) async => http.Response(_hosted, 200));
      await SymbolLookup.load(client: online);

      var called = false;
      final offline = MockClient((req) async {
        called = true;
        throw http.ClientException('offline');
      });
      final l = await SymbolLookup.load(client: offline);
      expect(called, isFalse, reason: 'a fresh cache must skip the network');
      expect(l.suggest('Malaysia', '9999').first.name, 'HOSTED ONLY');
    });

    test('falls back to the bundled copy when nothing is published yet',
        () async {
      final missing =
          MockClient((req) async => http.Response('not found', 404));
      final l = await SymbolLookup.load(client: missing);
      expect(l.suggest('Malaysia', '1155').first.name, 'MALAYAN BANKING BERHAD');
    });

    test('aliases from the published file drive code/name matching', () async {
      final client = MockClient((req) async => http.Response(_hosted, 200));
      final l = await SymbolLookup.load(client: client);

      final txns = [
        txn(id: 'a', code: '9999', name: '', date: '2026-08-01', qty: 100, total: 1000),
        txn(id: 'b', code: '', name: 'Hosted Only', date: '2026-08-02', side: 'sell', qty: 40, total: 400),
      ];
      final merged = PortfolioStore.aggregate(txns, aliases: l.aliases);
      expect(merged, hasLength(1));
      expect(merged.single.qty, closeTo(60, 1e-9));
    });
  });

  group('background refresh', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SymbolLookup.resetShared();
    });

    test('installs the published copy and announces it', () async {
      SymbolLookup.debugSetShared(SymbolLookup.parse(_sample));
      var notified = 0;
      void listener() => notified++;
      SymbolLookup.current.addListener(listener);

      final client = MockClient((req) async => http.Response(_hosted, 200));
      expect(await SymbolLookup.refresh(client: client), isTrue);
      expect(notified, 1);
      expect(SymbolLookup.current.value.suggest('Malaysia', '9999').first.name,
          'HOSTED ONLY');

      SymbolLookup.current.removeListener(listener);
    });

    test('does nothing when the published copy is identical', () async {
      final client = MockClient((req) async => http.Response(_sample, 200));
      SymbolLookup.debugSetShared(SymbolLookup.parse(_sample));
      expect(await SymbolLookup.refresh(client: client), isFalse);
    });

    test('stays on the loaded copy when the download fails', () async {
      SymbolLookup.debugSetShared(SymbolLookup.parse(_sample));
      final client = MockClient(
          (req) async => throw http.ClientException('offline'));

      expect(await SymbolLookup.refresh(client: client), isFalse);
      expect(SymbolLookup.current.value.suggest('Malaysia', '1155'), isNotEmpty);
    });
  });

  group('instance', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SymbolLookup.resetShared();
    });

    test('is resolved once per run and replaceable for tests', () async {
      SymbolLookup.debugSetShared(SymbolLookup.parse(_sample));
      final a = await SymbolLookup.instance();
      final b = await SymbolLookup.instance();
      expect(identical(a, b), isTrue);
      expect(a.entries, hasLength(6));
      SymbolLookup.resetShared();
      SymbolLookup.debugSetShared(SymbolLookup.empty);
    });
  });

  group('bundled asset', () {
    test('loads offline and covers every shipped market', () async {
      final l = await SymbolLookup.load(allowRemote: false);

      // Built from the exchange exports, so it is tens of thousands strong.
      expect(l.entries.length, greaterThan(40000));
      expect(l.currencies['Malaysia'], 'MYR');
      expect(l.suffixes['Japan'], '.T');
      for (final market in [
        'Malaysia',
        'Singapore',
        'Hong Kong',
        'United States (US)',
        'Thailand',
        'Indonesia',
        'United Kingdom (UK)',
        'Australia',
        'Japan',
        'Canada',
        'Germany',
      ]) {
        expect(l.suffixes.containsKey(market), isTrue, reason: market);
      }
    });

    test('answers the everyday lookups the sheet performs', () async {
      final l = await SymbolLookup.load(allowRemote: false);

      expect(l.suggest('Malaysia', '1155').first.name, 'MALAYAN BANKING BERHAD');
      expect(l.suggest('Malaysia', 'malayan').first.code, '1155');
      expect(l.suggest('Malaysia', 'CIMB').first.code, '1023');
      expect(l.suggest('Hong Kong', '700').first.code, '700');
      expect(l.suggest('Hong Kong', '0700').first.code, '700');
      expect(l.suggest('United States (US)', 'aapl').first.code, 'AAPL');
      expect(l.suggest('Japan', '7203').first.name, 'TOYOTA MOTOR CORPORATION');
      // Several Hong Kong warrants share the TENCENT prefix, so the exact code
      // is asserted rather than the first suggestion.
      expect(l.suggest('Hong Kong', 'tencent', limit: 40).map((e) => e.code),
          contains('700'));
      expect(l.exactMatch('Hong Kong', 'tencent')!.code, '700');
    });

    test('keeps code-only markets and repairs the source quirks', () async {
      final l = await SymbolLookup.load(allowRemote: false);

      // USA, Indonesia and Thailand ship codes without names.
      final apple = l.suggest('United States (US)', 'AAPL').first;
      expect(apple.name, isEmpty);
      expect(apple.displayName, 'AAPL');

      // Thailand's list carries the Yahoo '.BK' suffix and an index row.
      expect(l.suggest('Thailand', '1DIV').first.code, '1DIV');
      expect(l.suggest('Thailand', '^SET'), isEmpty);
      expect(l.entries.where((e) => e.code.endsWith('.BK')), isEmpty);

      // Japan exported '7203.0' as '72030'; the app stores the real code.
      expect(l.suggest('Japan', '7203').first.code, '7203');
      expect(l.suggest('Japan', '72030'), isEmpty);
    });

    test('resolves the buy-by-code / sell-by-name case end to end', () async {
      final l = await SymbolLookup.load(allowRemote: false);
      final txns = [
        txn(id: 'a', code: '1155', name: '', date: '2026-08-01', qty: 1000, total: 9200),
        txn(id: 'b', code: '', name: 'Malayan Banking Berhad', date: '2026-09-01', side: 'sell', qty: 400, total: 4000),
      ];
      final merged = PortfolioStore.aggregate(txns, aliases: l.aliases);
      expect(merged, hasLength(1));
      expect(merged.single.qty, closeTo(600, 1e-9));
    });
  });
}
