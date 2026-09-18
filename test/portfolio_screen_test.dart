import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_mmcal/main.dart';
import 'package:flutter_mmcal/screens/add_portfolio_sheet.dart';
import 'package:flutter_mmcal/screens/portfolio_screen.dart';
import 'package:flutter_mmcal/services/portfolio_store.dart';
import 'package:flutter_mmcal/services/quote_service.dart';
import 'package:flutter_mmcal/services/symbol_lookup.dart';

/// A tiny offline dictionary used by the suggestion tests.
SymbolLookup testDictionary() => SymbolLookup.parse('''
{
  "version": 1,
  "markets": {"Malaysia": {"currency": "MYR", "suffix": ".KL"}},
  "symbols": [
    {"m": "Malaysia", "c": "1155", "n": "MAYBANK"},
    {"m": "Malaysia", "c": "1023", "n": "CIMB"},
    {"m": "Malaysia", "c": "1295", "n": "PBBANK"}
  ]
}
''');

PortfolioTxn txn({
  required String id,
  required String market,
  required String currency,
  required String code,
  required String name,
  required String date,
  String side = 'buy',
  required double qty,
  required double total,
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

/// Pumps a screen with a button that opens the add/edit sheet.
Future<void> pumpWithSheetOpener(
  WidgetTester tester, {
  required String side,
  List<PortfolioTxn> allTxns = const [],
  SymbolLookup? lookup,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showPortfolioEntrySheet(
              ctx,
              market: 'Malaysia',
              currency: 'MYR',
              side: side,
              qty: 100,
              price: 9,
              total: 900,
              allTxns: allTxns,
              lookup: lookup,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Pumps a screen whose button opens the add sheet and hands the popped
/// outcome to [onOutcome], so a test can assert on what was saved.
Future<void> pumpSheetCapturing(
  WidgetTester tester, {
  required void Function(PortfolioEntryOutcome?) onOutcome,
  String side = 'buy',
  List<PortfolioTxn> allTxns = const [],
  SymbolLookup? lookup,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              onOutcome(await showPortfolioEntrySheet(
                ctx,
                market: 'Malaysia',
                currency: 'MYR',
                side: side,
                qty: 100,
                price: 9,
                total: 900,
                allTxns: allTxns,
                lookup: lookup,
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Keep every test offline: no hosted refresh, no asset-bundle dependency,
    // and no quote network calls unless a test installs a mock service.
    SymbolLookup.debugSetShared(SymbolLookup.empty);
    QuoteService.networkEnabled = false;
    QuoteService.debugSetShared(null);
  });

  testWidgets('empty portfolio shows the empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PortfolioStore.clearAll();
    await tester.pumpWidget(const MaterialApp(home: PortfolioScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No holdings yet'), findsOneWidget);
  });

  testWidgets('groups holdings by market then settlement currency',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PortfolioStore.saveAll([
      txn(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', date: '2026-08-01', qty: 1000, total: 9200),
      txn(id: 'b', market: 'United States (US)', currency: 'USD', code: 'AAPL', name: 'Apple', date: '2026-08-02', qty: 150, total: 31275),
      txn(id: 'c', market: 'United States (US)', currency: 'MYR', code: 'AAPL', name: 'Apple', date: '2026-08-03', qty: 100, total: 88410.50),
    ]);
    await tester.pumpWidget(const MaterialApp(home: PortfolioScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Malaysia - MYR'), findsOneWidget);
    expect(find.text('United States (US) - USD'), findsOneWidget);
    expect(find.text('United States (US) - MYR'), findsOneWidget);
    expect(find.text('1155'), findsOneWidget);
    // Apple appears once per currency group - two separate lines. Names are
    // stored upper-cased, so the canonical spelling is APPLE.
    expect(find.text('APPLE'), findsNWidgets(2));
  });
  testWidgets('single currency shows one Total (MYR) headline row',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PortfolioStore.clearAll();
    await PortfolioStore.saveAll([
      txn(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', date: '2026-08-01', qty: 1000, total: 9200),
      txn(id: 'b', market: 'Singapore', currency: 'MYR', code: 'D05', name: 'Singtel', date: '2026-08-02', qty: 500, total: 3000),
    ]);
    await tester.pumpWidget(const MaterialApp(home: PortfolioScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Total (MYR)'), findsOneWidget);
    expect(find.text('12,200.00'), findsOneWidget);
    expect(find.text('2 lines · 2 markets'), findsOneWidget);
    expect(find.textContaining('never converted'), findsNothing);
  });

  testWidgets('mixed currencies show one total row per currency, unconverted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PortfolioStore.clearAll();
    await PortfolioStore.saveAll([
      txn(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', date: '2026-08-01', qty: 1000, total: 9200),
      txn(id: 'b', market: 'United States (US)', currency: 'USD', code: 'AAPL', name: 'Apple', date: '2026-08-02', qty: 150, total: 31275),
      txn(id: 'c', market: 'United States (US)', currency: 'MYR', code: 'AAPL', name: 'Apple', date: '2026-08-03', qty: 100, total: 88410.50),
    ]);
    await tester.pumpWidget(const MaterialApp(home: PortfolioScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Total (MYR)'), findsOneWidget);
    expect(find.text('Total (USD)'), findsOneWidget);
    expect(find.text('97,610.50'), findsOneWidget, reason: 'MYR total');
    // 31,275.00 shows twice: the USD group subtotal and the Total (USD) row.
    expect(find.text('31,275.00'), findsNWidgets(2), reason: 'USD total');
    expect(find.text('Per-currency totals are never converted.'),
        findsOneWidget);
  });

  testWidgets('expanding a line shows the last price, value and P/L',
      (tester) async {
    QuoteService.debugSetShared(QuoteService(
        SymbolLookup.parse(
            '{"version":1,"markets":{"Malaysia":{"currency":"MYR","suffix":".KL"}},"symbols":[]}'),
        httpClient: MockClient((req) async => http.Response(
            jsonEncode({
              'chart': {
                'result': [
                  {
                    'meta': {
                      'currency': 'MYR',
                      'symbol': '1155.KL',
                      'regularMarketPrice': 10.36,
                      'chartPreviousClose': 10.42
                    }
                  }
                ],
                'error': null
              }
            }),
            200))));
    QuoteService.networkEnabled = true;
    SharedPreferences.setMockInitialValues({});
    await PortfolioStore.clearAll();
    await PortfolioStore.saveAll([
      txn(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', date: '2026-08-01', qty: 1000, total: 9200),
    ]);
    await tester.pumpWidget(const MaterialApp(home: PortfolioScreen()));
    await tester.pumpAndSettle();

    // Nothing quote-related before the automatic price pass resolves.
    await tester.pumpAndSettle();

    // The on-load pass fetched every line without any expansion, so the
    // totals card shows Value/P/L straight away.
    expect(find.textContaining('Value (MYR)'), findsOneWidget);
    expect(find.textContaining('P/L (MYR)'), findsOneWidget);

    // Expanding a line also shows its own quote details.
    await tester.tap(find.text('1155'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Last 10.36 MYR'), findsOneWidget);
    // Value = 1000 x 10.36; P/L = (10.36 - 9.20) x 1000.
    expect(find.textContaining('Value 10,360.00 MYR'), findsOneWidget);
    expect(find.textContaining('P/L +1,160.00 MYR'), findsOneWidget);
    expect(find.text('Value (MYR)'), findsOneWidget);
    expect(find.text('P/L (MYR)'), findsOneWidget);
  });

  testWidgets('buy sheet saves and enables Save', (tester) async {
    await pumpWithSheetOpener(tester, side: 'buy');
    await tester.enterText(find.byType(TextField).at(0), '1155');
    await tester.pumpAndSettle();
    final save =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('sell with no purchase record blocks Save', (tester) async {
    await pumpWithSheetOpener(tester, side: 'sell');
    await tester.enterText(find.byType(TextField).at(0), 'TSLA');
    await tester.pumpAndSettle();

    expect(find.textContaining('No purchase record'), findsOneWidget);
    final save =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save.onPressed, isNull);
  });

  testWidgets('sell matching an existing holding enables Save', (tester) async {
    await pumpWithSheetOpener(
      tester,
      side: 'sell',
      allTxns: [
        txn(id: 'a', market: 'Malaysia', currency: 'MYR', code: '1155', name: 'Maybank', date: '2026-08-01', qty: 1000, total: 9200),
      ],
    );
    await tester.enterText(find.byType(TextField).at(0), '1155');
    await tester.pumpAndSettle();

    expect(find.textContaining('No purchase record'), findsNothing);
    final save =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('there is a single stock box and it is upper-cased',
      (tester) async {
    await pumpWithSheetOpener(tester, side: 'buy');

    // One box replaces the old Stock Code + Stock Name pair.
    expect(find.byKey(const ValueKey('stock-identifier')), findsOneWidget);
    expect(find.text('Stock Name'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('stock-identifier')), 'maybank');
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('stock-identifier')));
    expect(field.controller!.text, 'MAYBANK');
  });

  testWidgets('picking a suggestion stores the dictionary code and name',
      (tester) async {
    await pumpWithSheetOpener(tester, side: 'buy', lookup: testDictionary());

    await tester.enterText(find.byType(TextField).at(0), '115');
    // The search is debounced by 400ms.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('MAYBANK'), findsOneWidget);

    await tester.tap(find.text('MAYBANK'));
    await tester.pumpAndSettle();

    // The chip confirms what will be saved; the typed text is left alone.
    expect(find.text('1155 · MAYBANK'), findsOneWidget);
    // The list closes once a suggestion is taken.
    expect(find.text('PBBANK'), findsNothing);
  });

  testWidgets('suggestions do not reappear after a pick', (tester) async {
    await pumpWithSheetOpener(tester, side: 'buy', lookup: testDictionary());

    await tester.enterText(find.byType(TextField).at(0), 'may');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('MAYBANK'), findsOneWidget);
    await tester.tap(find.text('MAYBANK'));
    await tester.pumpAndSettle();

    // Picking must not re-open the list via its own text change.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('MAYBANK'), findsNothing); // the list stays closed
    expect(find.text('1155 · MAYBANK'), findsOneWidget); // the picked chip
  });

  testWidgets('an exact dictionary match saves the official code and name',
      (tester) async {
    PortfolioEntryOutcome? outcome;
    await pumpSheetCapturing(tester, lookup: testDictionary(),
        onOutcome: (o) => outcome = o);

    await tester.enterText(find.byType(TextField).at(0), '1155');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(outcome?.saved?.code, '1155');
    expect(outcome?.saved?.name, 'MAYBANK');
  });

  testWidgets('an unmatched stock saves exactly what the user typed',
      (tester) async {
    PortfolioEntryOutcome? outcome;
    await pumpSheetCapturing(tester, lookup: testDictionary(),
        onOutcome: (o) => outcome = o);

    await tester.enterText(find.byType(TextField).at(0), 'zzz unknown bhd');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(outcome?.saved?.code, 'ZZZ UNKNOWN BHD');
    expect(outcome?.saved?.name, 'ZZZ UNKNOWN BHD');
  });

  test('app bar theme is opaque so the white back arrow stays visible', () {
    // Regression guard: a transparent bar with a white foreground renders an
    // invisible back arrow on the near-white light scaffold (and iOS has no
    // system back button to fall back on).
    final light = buildAppBarTheme(Brightness.light);
    expect(light.backgroundColor, AppColors.primary);
    expect(light.foregroundColor, Colors.white);

    final dark = buildAppBarTheme(Brightness.dark);
    expect(dark.backgroundColor, AppColors.darkPrimary);
    expect(dark.foregroundColor, Colors.white);
  });

  testWidgets('portfolio screen shows a back button that pops', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PortfolioStore.clearAll();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => const PortfolioScreen()),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(PortfolioScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PortfolioScreen), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });
}
