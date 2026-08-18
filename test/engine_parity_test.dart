import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mmcal/config/settings.dart';
import 'package:flutter_mmcal/engine/engine.dart';
import 'package:flutter_mmcal/markets/market_registry.dart';

// Minimal settings manager for tests using defaults
class _TestSettings extends SettingsManager {
  _TestSettings() : super();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The engine only uses default settings in tests
  final markets = getAllMarkets(_TestSettings());

  Market market(String name) => markets.firstWhere((m) => m.name == name);

  void check(String label, double actual, double expected, {double tol = 0.01}) {
    expect(actual, closeTo(expected, tol), reason: '$label: expected $expected, got $actual');
  }

  group('Singapore Market', () {
    final sg = market('Singapore');

    test('Test 1: Small trade offline BUY (proceeds 825 RM <= 100K)', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      check('gross (SGD)', calc.get('gross'), 1500);
      check('rmgross (RM)', calc.get('rmgross'), 825);
      check('brkamtrate', calc.get('brkamtrate'), 0.55);
      check('malbrkamt (RM)', calc.get('malbrkamt'), 18.15);
      check('forbrkamt (SGD)', calc.get('forbrkamt'), 6);
    });

    test('Test 3: Small trade online BUY', () {
      final calc = sg.calculate(mode: 6, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      check('brkamtrate', calc.get('brkamtrate'), 0.35);
      check('malbrkamt (RM)', calc.get('malbrkamt'), 14.85);
      check('forbrkamt (SGD)', calc.get('forbrkamt'), 6);
    });

    test('Test 5: Large trade offline BUY (proceeds 165000 RM > 100K)', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 0, qty: 200000, price: 1.50, rate: 0.55);
      check('gross (SGD)', calc.get('gross'), 300000);
      check('rmgross (RM)', calc.get('rmgross'), 165000);
      check('brkamtrate', calc.get('brkamtrate'), 0.25);
      check('malbrkamt (RM)', calc.get('malbrkamt'), 412.5);
      check('forbrkamt (SGD)', calc.get('forbrkamt'), 150);
    });

    test('Test 6: Large trade online BUY', () {
      final calc = sg.calculate(mode: 6, buysel: 1, flag: 0, qty: 200000, price: 1.50, rate: 0.55);
      check('brkamtrate', calc.get('brkamtrate'), 0.20);
      check('malbrkamt (RM)', calc.get('malbrkamt'), 330);
      check('forbrkamt (SGD)', calc.get('forbrkamt'), 150);
    });

    test('Test 9: Special brokerage rate 0.10% offline BUY', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 2, qty: 1000, price: 1.50, rate: 0.55, brkrate: 0.10);
      check('brkamtrate', calc.get('brkamtrate'), 0.10);
      check('malbrkamt (RM)', calc.get('malbrkamt'), 18.15);
      check('forbrkamt (SGD)', calc.get('forbrkamt'), 6);
    });

    test('Test 10: SG-specific fees', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      check('clrfee (SGD)', calc.get('clrfee'), 0.49);
      check('trdfee (SGD)', calc.get('trdfee'), 0.11);
    });

    test('Test 11: GST applied (flag=0 means GST ON)', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      check('gstbrkamt (RM)', calc.get('gstbrkamt'), 1.45);
      check('gstforfee (RM)', calc.get('gstforfee'), 0.29);
      check('gstclrfee (RM)', calc.get('gstclrfee'), 0);
    });

    test('Test 12: GST NOT applied (flag=16)', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 16, qty: 1000, price: 1.50, rate: 0.55);
      check('gstbrkamt (RM)', calc.get('gstbrkamt'), 0);
      check('gstforfee (RM)', calc.get('gstforfee'), 0);
      check('gstclrfee (RM)', calc.get('gstclrfee'), 0);
    });

    test('Test 13: Total values small offline BUY (GST ON)', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      check('stampduty (RM)', calc.get('stampduty'), 1);
      check('ibrmcharges (RM)', calc.get('ibrmcharges'), 3.63);
      check('val1 (MYR)', calc.get('val1'), 847.78);
      check('gstbrkamtcv (SGD)', calc.get('gstbrkamtcv'), 2.64);
      check('gstforfeecv (SGD)', calc.get('gstforfeecv'), 0.53);
      check('ibcharges (SGD)', calc.get('ibcharges'), 34.82);
      check('val2 (SGD)', calc.get('val2'), 1544.59);
    });

    test('Test 14: User example online SELL (percentage-based local brk)', () {
      final calc = sg.calculate(mode: 6, buysel: 2, flag: 0, qty: 1800, price: 27.82, rate: 0.51);
      check('gross (SGD)', calc.get('gross'), 50076);
      check('rmgross (RM)', calc.get('rmgross'), 25538.76);
      check('brkamtrate', calc.get('brkamtrate'), 0.35);
      check('malbrkamt (RM)', calc.get('malbrkamt'), 89.38);
      check('forbrkamt (SGD)', calc.get('forbrkamt'), 25.04);
    });

    test('Test 15: SG stamp duty rate (0.10%)', () {
      final calc = sg.calculate(mode: 5, buysel: 1, flag: 0, qty: 200000, price: 1.50, rate: 0.55);
      check('stampdutyrate', calc.get('stampdutyrate'), 0.10);
      check('stampduty_raw (RM)', calc.get('stampduty_raw'), 165.00);
      check('stampduty (RM)', calc.get('stampduty'), 165);
    });
  });

  group('Hong Kong Market', () {
    final hk = market('Hong Kong');

    test('Small trade offline BUY (proceeds 825 RM <= 100K)', () {
      final calc = hk.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      check('gross (HKD)', calc.get('gross'), 1500);
      check('rmgross (RM)', calc.get('rmgross'), 825);
      check('brkamtrate', calc.get('brkamtrate'), 0.55);
      // local brk = 1500*0.55% = 8.25 -> floored to min HKD110
      // foreign brk = max(1500*0.05%, 40) = max(0.75, 40) = 40 HKD
      // malbrok = 110 + 40 = 150 HKD
      // malbrkamt = (150 - 40) * 0.55 = 60.5 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 60.5);
      check('forbrkamt (HKD)', calc.get('forbrkamt'), 40);
    });

    test('Large trade offline BUY (proceeds 165000 RM > 100K)', () {
      final calc = hk.calculate(mode: 5, buysel: 1, flag: 0, qty: 200000, price: 1.50, rate: 0.55);
      check('brkamtrate', calc.get('brkamtrate'), 0.25);
      // local brk = 300000*0.25% = 750 HKD
      // foreign brk = 300000*0.05% = 150 HKD
      // malbrok = 900 HKD
      // malbrkamt = (900 - 150) * 0.55 = 412.5 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 412.5);
      check('forbrkamt (HKD)', calc.get('forbrkamt'), 150);
    });

    test('HK-specific fees', () {
      final calc = hk.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 0.55);
      // trading fee = 1500*0.0056% = 0.084 -> 0.08
      check('trdfee (HKD)', calc.get('trdfee'), 0.08);
      // CCASS fee = max(1500*0.0042%, 2) = max(0.063, 2) = 2.00
      check('ccassfee (HKD)', calc.get('ccassfee'), 2.00);
      // levy fee = 1500*0.00285% = 0.04275 -> 0.04
      check('levyfee (HKD)', calc.get('levyfee'), 0.04);
      // foreign stamp duty = 1500*0.001 = 1.5 -> ceil = 2
      check('forstampduty (HKD)', calc.get('forstampduty'), 2);
    });

    test('Special brokerage rate', () {
      final calc = hk.calculate(mode: 5, buysel: 1, flag: 2, qty: 1000, price: 1.50, rate: 0.55, brkrate: 0.10);
      check('brkamtrate', calc.get('brkamtrate'), 0.10);
      // local brk = 1500*0.10% = 1.50 -> floored to min HKD110
      // foreign brk = max(0.75, 40) = 40 HKD
      // malbrok = 150 HKD
      // malbrkamt = (150 - 40) * 0.55 = 60.5 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 60.5);
      check('forbrkamt (HKD)', calc.get('forbrkamt'), 40);
    });
  });

  group('United States Market', () {
    final us = market('United States (US)');

    test('Small trade offline BUY (proceeds 5250 RM <= 100K)', () {
      final calc = us.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 3.5);
      check('gross (USD)', calc.get('gross'), 1500);
      check('rmgross (RM)', calc.get('rmgross'), 5250);
      check('brkamtrate', calc.get('brkamtrate'), 0.57);
      // <= RM100K: local = flat min USD24
      // foreign = max(1500*0.03%, 4) = max(0.45, 4) = 4 USD
      // malbrok = 24 + 4 = 28 USD
      // malbrkamt = (28 - 4) * 3.5 = 84 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 84);
      check('forbrkamt (USD)', calc.get('forbrkamt'), 4);
    });

    test('Large trade offline BUY (proceeds 525000 RM > 100K)', () {
      final calc = us.calculate(mode: 5, buysel: 1, flag: 0, qty: 100000, price: 1.50, rate: 3.5);
      check('brkamtrate', calc.get('brkamtrate'), 0.37);
      // local brk = 150000*0.37% = 555 USD
      // foreign brk = 150000*0.03% = 45 USD
      // malbrok = 600 USD
      // malbrkamt = (600 - 45) * 3.5 = 1942.5 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 1942.5);
      check('forbrkamt (USD)', calc.get('forbrkamt'), 45);
    });

    test('SEC fee on sell only', () {
      final buy = us.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 5.60, rate: 4.167);
      final sell = us.calculate(mode: 5, buysel: 2, flag: 0, qty: 1000, price: 5.60, rate: 4.167);
      check('buy clrfee (USD)', buy.get('clrfee'), 0);
      // sell: clrfee = 5600*0.00218% = 0.12208 -> round up = 0.13
      check('sell clrfee (USD)', sell.get('clrfee'), 0.13);
    });
  });

  group('Malaysia Market', () {
    final my = market('Malaysia');

    test('Small trade offline BUY', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50);
      check('gross (MYR)', calc.get('gross'), 1500);
      check('brkamtrate', calc.get('brkamtrate'), 0.60);
      // brk = 1500*0.60% = 9 -> floored to min RM40
      check('brkamt (RM)', calc.get('brkamt'), 40);
      // stampduty = 1500*0.10% = 1.5 -> min RM1, ceil = 2
      check('stampduty (RM)', calc.get('stampduty'), 2);
      // clrfee = 1500*0.03% = 0.45
      check('clrfee (RM)', calc.get('clrfee'), 0.45);
    });

    test('MIN RM12 flag', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 1, qty: 1000, price: 1.50);
      check('brkamt (RM)', calc.get('brkamt'), 12);
    });

    test('No Stamp Duty flag', () {
      // bit2 (value 4) = no stamp duty
      final calc = my.calculate(mode: 5, buysel: 1, flag: 4, qty: 1000, price: 1.50);
      check('stampduty (RM)', calc.get('stampduty'), 0);
    });

    test('Special rate flag', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 2, qty: 1000, price: 1.50, brkrate: 0.35);
      check('brkamtrate', calc.get('brkamtrate'), 0.35);
      // brk = 1500*0.35% = 5.25 -> floored to min RM40
      check('brkamt (RM)', calc.get('brkamt'), 40);
    });

    test('GST applied (flag=0)', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50);
      // gstbrkamt = 40 * 8% = 3.20
      check('gstbrkamt (RM)', calc.get('gstbrkamt'), 3.20);
      // gstclrfee = 0.45 * 8% = 0.036 -> 0.04
      check('gstclrfee (RM)', calc.get('gstclrfee'), 0.04);
    });

    test('GST NOT applied (flag=16)', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 16, qty: 1000, price: 1.50);
      check('gstbrkamt (RM)', calc.get('gstbrkamt'), 0);
      check('gstclrfee (RM)', calc.get('gstclrfee'), 0);
    });

    test('DF A/C calculation', () {
      final mm = my as dynamic;
      final df = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      // base net_value = 1500 + 40 + 2 + 0.45 + 3.20 + 0.04 = 1545.69
      // dfint = 1545.69 * 0.0925 / 365 * (5-4) = 0.39
      // dffee = max(1545.69*0.003, 10) = max(4.64, 10) = 10
      // dfgstfee = 10 * 0.06 = 0.60
      // total = 1545.69 + 0.39 + 10 + 0.60 = 1556.68
      check('dfint', df['dfint'], 0.39);
      check('dffee', df['dffee'], 10);
      check('dfgstfee', df['dfgstfee'], 0.60);
      check('total', df['total'], 1556.68);
    });
  });

  group('Simple Markets', () {
    test('Thailand combined min THB840', () {
      final th = market('Thailand');
      final calc = th.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 3.5);
      // gross = 1500 THB, local = 1500*0.65% = 9.75, foreign = 1500*0.05% = 0.75
      // total = max(9.75 + 0.75, 840) = 840 THB
      // malbrok = 840, forbrkamt = 0.75
      // malbrkamt = (840 - 0.75) * 3.5 = 2937.375 -> 2937.38
      check('malbrkamt (RM)', calc.get('malbrkamt'), 2937.38);
      check('forbrkamt (THB)', calc.get('forbrkamt'), 0.75);
    });

    test('UK combined min GBP38', () {
      final uk = market('United Kingdom (UK)');
      final calc = uk.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 5.5);
      // gross = 1500 GBP, local = 1500*0.65% = 9.75 -> min 18
      // foreign = 1500*0.10% = 1.5 -> min 20
      // total = max(18 + 20, 38) = 38 GBP
      // malbrok = 38, forbrkamt = max(1.5, 20) = 20
      // malbrkamt = (38 - 20) * 5.5 = 99 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 99);
      check('forbrkamt (GBP)', calc.get('forbrkamt'), 20);
    });

    test('Canada min_brk_offline=95, min_ib_fee=80', () {
      final ca = market('Canada');
      final calc = ca.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 3.5);
      // gross = 1500 CAD, local = 1500*0.90% = 13.5 -> floored to min 95
      // foreign = 1500*0.35% = 5.25 -> floored to min 80
      // malbrok = 95 (local only, from determineRates)
      // forbrkamt = max(5.25, 80) = 80
      // malbrkamt = (95 - 80) * 3.5 = 52.5 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 52.5);
      check('forbrkamt (CAD)', calc.get('forbrkamt'), 80);
    });

    test('Germany combined min EUR60', () {
      final de = market('Germany');
      final calc = de.calculate(mode: 5, buysel: 1, flag: 0, qty: 1000, price: 1.50, rate: 4.5);
      // gross = 1500 EUR, local = 1500*1.05% = 15.75 -> min 40
      // foreign = 1500*0.15% = 2.25 -> min 20
      // total = max(40 + 20, 60) = 60 EUR
      // malbrok = 60, forbrkamt = max(2.25, 20) = 20
      // malbrkamt = (60 - 20) * 4.5 = 180 RM
      check('malbrkamt (RM)', calc.get('malbrkamt'), 180);
      check('forbrkamt (EUR)', calc.get('forbrkamt'), 20);
    });
  });
}