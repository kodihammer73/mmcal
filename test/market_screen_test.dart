import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_mmcal/config/settings.dart';
import 'package:flutter_mmcal/markets/malaysia.dart';
import 'package:flutter_mmcal/screens/market_screen.dart';
import 'package:flutter_mmcal/services/form_state.dart';

Widget _wrap() {
  return MaterialApp(
    home: Scaffold(
      body: MarketScreen(market: MalaysiaMarket(SettingsManager())),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FormStateStore persistence', () {
    test('save then load round-trips fields', () async {
      await FormStateStore.save('Malaysia', {
        'qty': 100.0,
        'buy': 1.5,
        'isOnline': 1,
        'flagNoSduty': 1,
      });
      final saved = await FormStateStore.load('Malaysia');
      expect(saved['qty'], 100.0);
      expect(saved['buy'], 1.5);
      expect(saved['isOnline'], 1);
      expect(saved['flagNoSduty'], 1);
    });

    test('clear removes saved state', () async {
      await FormStateStore.save('Malaysia', {'qty': 100.0});
      await FormStateStore.clear('Malaysia');
      final saved = await FormStateStore.load('Malaysia');
      expect(saved, isEmpty);
    });

    test('nonexistent market loads empty', () async {
      final saved = await FormStateStore.load('Japan');
      expect(saved, isEmpty);
    });
  });

  group('MarketScreen validation', () {
    testWidgets('disables Calculate and shows error when quantity is 0', (
        tester) async {
      await tester.pumpWidget(_wrap());

      // Empty quantity field -> invalid.
      final btnEmpty = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Calculate'),
      );
      expect(btnEmpty.onPressed, isNull);
    });

    testWidgets('shows inline error then clears it once valid', (tester) async {
      await tester.pumpWidget(_wrap());

      await tester.enterText(
        find.widgetWithText(TextField, 'Quantity'),
        '100',
      );
      await tester.pump();
      expect(find.text('Enter a Buy and/or Sell price.'), findsOneWidget);
      final btnNoPrice = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Calculate'),
      );
      expect(btnNoPrice.onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Buy Price (MYR)'),
        '1.50',
      );
      await tester.pump();
      expect(find.text('Enter a Buy and/or Sell price.'), findsNothing);
      final btnValid = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Calculate'),
      );
      expect(btnValid.onPressed, isNotNull);
    });
  });

  group('MarketScreen persistence', () {
    testWidgets('restores saved input on load', (tester) async {
      SharedPreferences.setMockInitialValues({
        'formstate_Malaysia': jsonEncode({
          'qty': '100',
          'buy': '1.5',
          'sell': '',
          'buyRate': '1.0',
          'sellRate': '1.0',
          'brkrate': '0',
          'dfDays': '5',
          'isOnline': 1,
          'flagMinRm': 0,
          'flagNoSduty': 0,
          'flagSpecial': 0,
          'applyGst': 0,
          'settleLocal': 0,
          'dfAc': 0,
        }),
      });

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final qtyField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Quantity'),
      );
      final buyField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Buy Price (MYR)'),
      );
      expect(qtyField.controller!.text, '100');
      expect(buyField.controller!.text, '1.5');
    });
  });

  group('MarketScreen copy summary', () {
    testWidgets('calculate then copy writes a summary to the clipboard',
        (tester) async {
      // Capture clipboard writes via the platform channel mock.
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(_wrap());

      await tester.enterText(
        find.widgetWithText(TextField, 'Quantity'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Buy Price (MYR)'),
        '1.50',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Sell Price (MYR)'),
        '1.60',
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Calculate'));
      await tester.pumpAndSettle();

      // Results card + copy button appear.
      expect(find.textContaining('Results ('), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(copiedText, isNotNull);
      expect(copiedText, contains('Malaysia'));
      expect(copiedText, contains('TOTAL'));
    });
  });

  group('MarketScreen copy summary format', () {
    testWidgets('both buy and sell show both columns and no line wraps', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '10000');
      await tester.enterText(find.widgetWithText(TextField, 'Buy Price (MYR)'), '1.50');
      await tester.enterText(find.widgetWithText(TextField, 'Sell Price (MYR)'), '1.60');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Calculate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(copied, isNotNull);
      expect(copied, contains('BUY'));
      expect(copied, contains('SELL'));
      // Shortened labels per user spec.
      expect(copied, contains('Gross'));
      expect(copied, isNot(contains('Proceeds')));
      expect(copied, contains('TOTAL'));
      expect(copied, contains('CONTRA'));
      final lines = copied!.split('\n');
      for (final l in lines) {
        if (l.trim().isEmpty) continue;
        // No dangling empty cell / trailing whitespace.
        expect(l.endsWith(' '), isFalse, reason: 'trailing spaces: "$l"');
        // No column collision even with thousands separators.
        expect(RegExp(r'\d\.\d{2}[1-9]').hasMatch(l), isFalse,
            reason: 'cells collide: "$l"');
        expect(l.length, lessThanOrEqualTo(38), reason: 'line wraps: "$l"');
      }
    });

    testWidgets('buy only shows BUY column and no SELL', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '100');
      await tester.enterText(find.widgetWithText(TextField, 'Buy Price (MYR)'), '1.50');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Calculate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(copied, isNotNull);
      expect(copied, contains('BUY'));
      expect(copied, isNot(contains('SELL')));
    });

    testWidgets('sell only shows SELL column and no BUY', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '100');
      await tester.enterText(find.widgetWithText(TextField, 'Sell Price (MYR)'), '1.60');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Calculate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(copied, isNotNull);
      expect(copied, contains('SELL'));
      expect(copied, isNot(contains('BUY')));
    });
  });
}
