import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_mmcal/services/quote_service.dart';
import 'package:flutter_mmcal/services/symbol_lookup.dart';

const _dict = '''
{
  "version": 1,
  "markets": {"Malaysia": {"currency": "MYR", "suffix": ".KL"}},
  "symbols": [
    {"m": "Malaysia", "c": "1155", "n": "MAYBANK"}
  ]
}
''';

const _yahooChart = '''
{"chart":{"result":[{"meta":{"currency":"MYR","symbol":"1155.KL",
"regularMarketPrice":10.36,"chartPreviousClose":10.42,
"shortName":"MAYBANG"}}],"error":null}}
''';

const _googleHtml = '''
<html><body><div data-last-price="10.36" data-currency-code="MYR">
Previous close</td><td>10.42</td></div></body></html>
''';

/// A client that answers per-URL-prefix, failing anything unlisted.
MockClient routingClient(Map<String, String Function()> routes) =>
    MockClient((req) async {
      for (final entry in routes.entries) {
        if (req.url.toString().startsWith(entry.key)) {
          final r = entry.value();
          if (r.isEmpty) return http.Response('not found', 404);
          return http.Response(r, 200);
        }
      }
      return http.Response('not found', 404);
    });

QuoteService serviceFor(Map<String, String Function()> routes) =>
    QuoteService(SymbolLookup.parse(_dict),
        httpClient: routingClient(routes));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    QuoteService.networkEnabled = true;
    QuoteService.debugSetShared(null);
  });
  tearDown(() => QuoteService.debugSetShared(null));

  group('yahoo chart', () {
    test('parses price, previous close and currency', () async {
      final q = await serviceFor({
        'https://query1.finance.yahoo.com/v8/finance/chart/1155.KL':
            () => _yahooChart,
      }).fetch('Malaysia', '1155');
      expect(q, isNotNull);
      expect(q!.price, 10.36);
      expect(q.previousClose, 10.42);
      expect(q.currency, 'MYR');
      expect(q.symbol, '1155.KL');
      expect(q.provider, 'yahoo');
      expect(q.change, closeTo(-0.06, 1e-9));
      expect(q.changePercent, closeTo(-0.06 / 10.42 * 100, 1e-9));
    });

    test('offline / throttled / garbage all yield null', () async {
      final offline =
          MockClient((req) async => throw http.ClientException('x'));
      final throttled = MockClient((req) async => http.Response('no', 429));
      final garbage = MockClient((req) async => http.Response('<html>', 200));
      final lookup = SymbolLookup.parse(_dict);
      for (final c in [offline, throttled, garbage]) {
        expect(
            await QuoteService(lookup, httpClient: c).fetch('Malaysia', '1155'),
            isNull);
      }
    });

    test('network switch off never calls the client', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response(_yahooChart, 200);
      });
      QuoteService.networkEnabled = false;
      final q = await QuoteService(SymbolLookup.parse(_dict),
              httpClient: client)
          .fetch('Malaysia', '1155');
      expect(q, isNull);
      expect(called, isFalse);
    });
  });

  group('yahoo symbol construction', () {
    final svc = QuoteService(SymbolLookup.parse('''
{"version":1,"markets":{
 "Malaysia":{"currency":"MYR","suffix":".KL"},
 "Hong Kong":{"currency":"HKD","suffix":".HK"},
 "United States (US)":{"currency":"USD","suffix":""},
 "United Kingdom (UK)":{"currency":"GBP","suffix":".L"}},
 "symbols":[]}'''));

    test('appends the exchange suffix', () {
      expect(svc.yahooSymbol('Malaysia', '1155'), '1155.KL');
    });

    test('pads Hong Kong codes to Yahoo 4-digit form', () {
      expect(svc.yahooSymbol('Hong Kong', '700'), '0700.HK');
    });

    test('US share classes use a hyphen and no suffix', () {
      expect(svc.yahooSymbol('United States (US)', 'BRK.B'), 'BRK-B');
    });

    test('UK trailing dot is stripped before the suffix', () {
      expect(svc.yahooSymbol('United Kingdom (UK)', 'RR.'), 'RR.L');
    });
  });

  group('fallback chain', () {
    test('falls back to Yahoo search then the resolved symbol', () async {
      final calls = <String>[];
      final q = await serviceFor({
        'https://query1.finance.yahoo.com/v8/finance/chart/XYZ.KL': () {
          calls.add('direct');
          return ''; // 404 - Yahoo does not know the code directly
        },
        'https://query1.finance.yahoo.com/v1/finance/search': () => jsonEncode({
              'quotes': [
                {'symbol': '1155.KL', 'shortname': 'MAYBANK'}
              ]
            }),
        'https://query1.finance.yahoo.com/v8/finance/chart/1155.KL': () {
          calls.add('resolved');
          return _yahooChart.replaceAll('10.36', '7.77');
        },
      }).fetch('Malaysia', 'XYZ');
      expect(calls, ['direct', 'resolved'],
          reason: 'direct chart fails, search resolves, resolved chart wins');
      expect(q!.symbol, '1155.KL');
      expect(q.price, 7.77);
    });

    test('falls back to Google Finance with the Yahoo short name', () async {
      final q = await serviceFor({
        'https://query1.finance.yahoo.com/v8/finance/chart/1155.KL':
            () => '', // Yahoo chart misses
        'https://query1.finance.yahoo.com/v1/finance/search': () =>
            jsonEncode({'quotes': []}), // search misses too
        'https://www.google.com/finance/quote/1155:KLSE':
            () => '', // code ticker misses
        'https://www.google.com/finance/quote/MAYBANK:KLSE': () => _googleHtml,
      }).fetch('Malaysia', '1155', name: 'MALAYAN BANKING BERHAD');
      expect(q, isNotNull);
      expect(q!.provider, 'google');
      expect(q.price, 10.36);
      expect(q.currency, 'MYR');
      expect(q.symbol, 'MAYBANK:KLSE');
    });

    test('null when every provider fails', () async {
      final q = await serviceFor({}).fetch('Malaysia', '1155');
      expect(q, isNull);
    });
  });

  group('session cache', () {
    test('a fresh quote is served from cache without a second request',
        () async {
      var calls = 0;
      final svc = QuoteService(SymbolLookup.parse(_dict),
          httpClient: MockClient((req) async {
        calls++;
        return http.Response(_yahooChart, 200);
      }));
      final a = await svc.fetch('Malaysia', '1155');
      final b = await svc.fetch('Malaysia', '1155');
      expect(identical(a, b), isTrue);
      expect(calls, 1);
      svc.clearCache();
      await svc.fetch('Malaysia', '1155');
      expect(calls, 2);
    });
  });
}
