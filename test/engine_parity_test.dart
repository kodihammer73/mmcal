import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mmcal/config/settings.dart';
import 'package:flutter_mmcal/engine/engine.dart';
import 'package:flutter_mmcal/markets/malaysia.dart';
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

  /// Markets built from a settings manager with the given overrides applied,
  /// so tests can prove a value is read from Settings rather than hardcoded.
  List<Market> marketsWith(Map<String, double> overrides) {
    final s = SettingsManager();
    overrides.forEach(s.set);
    return getAllMarkets(s);
  }

  MalaysiaMarket malaysiaWith(Map<String, double> overrides) =>
      marketsWith(overrides).firstWhere((m) => m.name == 'Malaysia')
          as MalaysiaMarket;

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

    test('Test 16: SG un-capped stamp duty (no RM200 max)', () {
      final calc = sg.calculate(mode: 5, buysel: 2, flag: 0, qty: 20000, price: 4.29, rate: 3.124);
      check('stampduty_raw (RM)', calc.get('stampduty_raw'), 268.04);
      check('stampduty (RM)', calc.get('stampduty'), 269);
      final sgdSd = (calc.get('stampduty') / 3.124 * 100).ceilToDouble() / 100;
      check('stampduty (SGD, ceil whole_rm/rate)', sgdSd, 86.11);
      check('ibcharges (SGD)', calc.get('ibcharges'), 300.61);
      check('val1 (MYR)', calc.get('val1'), 266858.80);
      check('val2 (SGD)', calc.get('val2'), 85398.81);
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

    test('MIN RM8 override floors small trade brokerage at RM8', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 1, qty: 1000, price: 0.80, minBrkOverride: 8.00);
      // brk = 800*0.60% = 4.80 -> floored to min RM8 (override), not RM12 or RM40
      check('brkamt (RM)', calc.get('brkamt'), 8);
    });

    test('MIN RM8 override - percentage above floor wins', () {
      final calc = my.calculate(mode: 5, buysel: 1, flag: 1, qty: 10000, price: 1.50, minBrkOverride: 8.00);
      // brk = 15000*0.60% = 90 -> percentage beats the floor
      check('brkamt (RM)', calc.get('brkamt'), 90);
    });

    test('MIN RM8 combined with Special Rate and NO S/D (flag=7)', () {
      final calc = my.calculate(mode: 6, buysel: 1, flag: 7, qty: 1000, price: 1.50, brkrate: 0.10, minBrkOverride: 8.00);
      check('brkamtrate', calc.get('brkamtrate'), 0.10);
      // brk = 1500*0.10% = 1.50 -> floored to RM8
      check('brkamt (RM)', calc.get('brkamt'), 8);
      check('stampduty (RM)', calc.get('stampduty'), 0);
    });

    test('No override keeps default RM12 minimum', () {
      final calc = my.calculate(mode: 6, buysel: 1, flag: 1, qty: 1000, price: 1.50);
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
      final mm = market('Malaysia') as MalaysiaMarket;
      final df = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      // base net_value = 1500 + 40 + 2 + 0.45 + 3.20 + 0.04 = 1545.69
      // dfint = 1545.69 * 9.25% / 365 * (5-4) = 0.39
      // dffee = max(1545.69*0.30%, 10) = max(4.64, 10) = 10
      // dfgstfee = 10 * 8% (gstrate) = 0.80
      // total = 1545.69 + 0.39 + 10 + 0.80 = 1556.88
      check('dfint', df['dfint']!, 0.39);
      check('dffee', df['dffee']!, 10);
      check('dfgstfee', df['dfgstfee']!, 0.80);
      check('total', df['total']!, 1556.88);
    });

    test('DF A/C GST NOT applied (flag=16)', () {
      final mm = market('Malaysia') as MalaysiaMarket;
      final df = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 16, qty: 1000.0, price: 1.50, noday: 5);
      // GST off -> base net_value = 1500 + 40 + 2 + 0.45 = 1542.45
      // dfint = 1542.45 * 9.25% / 365 * 1 = 0.39
      // dffee = max(1542.45*0.30%, 10) = 10, dfgstfee = 0 (toggle off)
      check('dfint', df['dfint']!, 0.39);
      check('dffee', df['dffee']!, 10);
      check('dfgstfee', df['dfgstfee']!, 0);
      check('total', df['total']!, 1552.84);
    });

    test('DF A/C GST uses the gstrate setting (6%)', () {
      final mm = malaysiaWith({'gstrate': 6.0});
      final df = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      // 6%: base net_value = 1500 + 40 + 2 + 0.45 + 2.40 + 0.03 = 1544.88
      // dfgstfee = 10 * 6% = 0.60, total = 1544.88 + 0.39 + 10 + 0.60 = 1555.87
      check('dfgstfee', df['dfgstfee']!, 0.60);
      check('total', df['total']!, 1555.87);
    });

    test('DF A/C days use dfmindays / dfmaxdays', () {
      final mm = malaysiaWith({'dfmindays': 6.0, 'dfmaxdays': 8.0});
      // 5 days <= dfmindays (6) -> no DF at all
      final none = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      check('dfint', none['dfint']!, 0);
      check('dffee', none['dffee']!, 0);
      check('total', none['total']!, 1545.69);

      // 9 days capped at dfmaxdays (6) -> interest on (6-4) days
      final capped = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 9);
      // dfint = 1545.69 * 9.25% / 365 * (6-4) = 0.78
      check('dfint', capped['dfint']!, 0.78);
      check('total', capped['total']!, 1557.27);
    });

    test('DF A/C fee tiers and min fee use settings', () {
      // Tier 2 applies above dffeeamt; dfminfee floors tier 1 only.
      final tiered = malaysiaWith({'dffeeamt': 1000.0, 'dffeerate2': 0.20});
      final df = tiered.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      // dffee = 1545.69 * 0.20% = 3.09
      check('dffee', df['dffee']!, 3.09);
      check('dfgstfee', df['dfgstfee']!, 0.25);

      final floored = malaysiaWith({'dfminfee': 20.0});
      final df2 = floored.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      // dffee = max(4.64, dfminfee 20) = 20, dfgstfee = 20 * 8% = 1.60
      check('dffee', df2['dffee']!, 20);
      check('dfgstfee', df2['dfgstfee']!, 1.60);
      check('total', df2['total']!, 1567.68);
    });

    test('DF A/C interest uses dfintrate / dfintbasis', () {
      final mm = malaysiaWith({'dfintrate': 5.0, 'dfintbasis': 360.0});
      final df = mm.dfAcCalculate(mode: 5, buysel: 1, flag: 0, qty: 1000.0, price: 1.50, noday: 5);
      // dfint = 1545.69 * 5% / 360 * 1 = 0.21
      check('dfint', df['dfint']!, 0.21);
      check('total', df['total']!, 1556.70);
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

  // ==========================================================
  // Per-market brokerage minimums (settings-driven), mirroring
  // test_minimums.py: defaults must reproduce historical hardcoded values,
  // and overriding a setting must move the calculated brokerage.
  // ==========================================================
  group('Settings-driven minimums', () {
    test('Defaults reproduce historical hardcoded values', () {
      final s = SettingsManager();
      final expected = <String, double>{
        'sinminbroff': 33, 'sinminbron': 27, 'sinminbronpromo': 14, 'sinminforbrk': 6,
        'hkdminbroff': 110, 'hkdminbronpromo': 50, 'hkdminforbrk': 40, 'hkdminbrton': 80,
        'usaminbroff': 24, 'usaminbron': 14, 'usaminforbrk': 4, 'usaminbrtoff': 28,
        'ukdminbroff': 18, 'ukdminforbrk': 20, 'ukdminbrtcomb': 38, 'ukdminibfee': 20,
        'ausminbroff': 35, 'ausminforbrk': 20, 'ausminbrtcomb': 55, 'ausminibfee': 20,
        'japminbroff': 1300, 'japminforbrk': 3000, 'japminbrtcomb': 4300, 'japminibfee': 3000,
        'germinbroff': 40, 'germinforbrk': 20, 'germinbrtcomb': 60, 'germinibfee': 20,
        'canminbroff': 95, 'canminbrton': 95, 'canminibfee': 80,
        'thaminbrtcomb': 840, 'indminbrtcomb': 265000,
      };
      expected.forEach((key, value) {
        check(key, s.get(key), value, tol: 0.0001);
      });
    });

    test('Singapore: sinminbroff / sinminbron / sinminbronpromo / sinminforbrk', () {
      final base = market('Singapore').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (default)', base.get('malbrkamt'), 16.50);

      final r1 = marketsWith({'sinminbroff': 55.0})
          .firstWhere((m) => m.name == 'Singapore')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (sinminbroff=55)', r1.get('malbrkamt'), 27.50);

      final r2 = marketsWith({'sinminbron': 66.0})
          .firstWhere((m) => m.name == 'Singapore')
          .calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('online malbrkamt (sinminbron=66)', r2.get('malbrkamt'), 33.00);

      final r3 = marketsWith({'sinminbronpromo': 40.0})
          .firstWhere((m) => m.name == 'Singapore')
          .calculate(mode: 6, buysel: 1, flag: 2, qty: 100, price: 1.00, rate: 0.50, brkrate: 0.10);
      check('online special-rate malbrkamt (sinminbronpromo=40)', r3.get('malbrkamt'), 20.00);

      final r4 = marketsWith({'sinminforbrk': 20.0})
          .firstWhere((m) => m.name == 'Singapore')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline forbrkamt (sinminforbrk=20)', r4.get('forbrkamt'), 20.00);
    });

    test('Hong Kong: hkdminbroff / hkdminbronpromo / hkdminforbrk / hkdminbrton', () {
      final base = market('Hong Kong').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (default)', base.get('malbrkamt'), 55.00);
      check('offline forbrkamt (default)', base.get('forbrkamt'), 40.00);

      final r1 = marketsWith({'hkdminbroff': 210.0})
          .firstWhere((m) => m.name == 'Hong Kong')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (hkdminbroff=210)', r1.get('malbrkamt'), 105.00);

      final r2 = marketsWith({'hkdminforbrk': 120.0})
          .firstWhere((m) => m.name == 'Hong Kong')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline forbrkamt (hkdminforbrk=120)', r2.get('forbrkamt'), 120.00);

      final r3 = marketsWith({'hkdminbronpromo': 52.0})
          .firstWhere((m) => m.name == 'Hong Kong')
          .calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('online malbrkamt (hkdminbronpromo=52)', r3.get('malbrkamt'), 26.00);

      final r4 = marketsWith({'hkdminbronpromo': 20.0, 'hkdminforbrk': 10.0, 'hkdminbrton': 80.0})
          .firstWhere((m) => m.name == 'Hong Kong')
          .calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('online malbrkamt (local 20 + foreign 10, hkdminbrton=80)', r4.get('malbrkamt'), 35.00);
    });

    test('United States: usaminbroff / usaminbron / usaminforbrk / usaminbrtoff', () {
      final base = market('United States (US)').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (default)', base.get('malbrkamt'), 12.00);

      final r1 = marketsWith({'usaminbroff': 44.0})
          .firstWhere((m) => m.name == 'United States (US)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (usaminbroff=44)', r1.get('malbrkamt'), 22.00);

      final r2 = marketsWith({'usaminforbrk': 14.0})
          .firstWhere((m) => m.name == 'United States (US)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline forbrkamt (usaminforbrk=14)', r2.get('forbrkamt'), 14.00);

      final r3 = marketsWith({'usaminbrtoff': 58.0})
          .firstWhere((m) => m.name == 'United States (US)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (usaminbrtoff=58)', r3.get('malbrkamt'), 27.00);

      final r4 = marketsWith({'usaminbron': 34.0})
          .firstWhere((m) => m.name == 'United States (US)')
          .calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('online malbrkamt (usaminbron=34)', r4.get('malbrkamt'), 17.00);
    });

    test('United Kingdom: ukdminbroff / ukdminforbrk / ukdminbrtcomb / ukdminibfee', () {
      final base = market('United Kingdom (UK)').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (default)', base.get('malbrkamt'), 9.00);

      final r1 = marketsWith({'ukdminbroff': 48.0})
          .firstWhere((m) => m.name == 'United Kingdom (UK)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ukdminbroff=48)', r1.get('malbrkamt'), 24.00);

      final r2 = marketsWith({'ukdminforbrk': 25.0})
          .firstWhere((m) => m.name == 'United Kingdom (UK)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ukdminforbrk=25 -> malbrok 43)', r2.get('malbrkamt'), 11.50);

      final r3 = marketsWith({'ukdminbrtcomb': 78.0})
          .firstWhere((m) => m.name == 'United Kingdom (UK)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ukdminbrtcomb=78)', r3.get('malbrkamt'), 29.00);

      final r4 = marketsWith({'ukdminibfee': 30.0})
          .firstWhere((m) => m.name == 'United Kingdom (UK)')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ukdminibfee=30)', r4.get('malbrkamt'), 4.00);
    });

    test('Australia: ausminbroff / ausminforbrk / ausminbrtcomb / ausminibfee', () {
      final base = market('Australia').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (default)', base.get('malbrkamt'), 17.50);

      final r1 = marketsWith({'ausminbroff': 55.0})
          .firstWhere((m) => m.name == 'Australia')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ausminbroff=55)', r1.get('malbrkamt'), 27.50);

      final r2 = marketsWith({'ausminforbrk': 25.0})
          .firstWhere((m) => m.name == 'Australia')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ausminforbrk=25 -> malbrok 60)', r2.get('malbrkamt'), 20.00);

      final r3 = marketsWith({'ausminbrtcomb': 85.0})
          .firstWhere((m) => m.name == 'Australia')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ausminbrtcomb=85)', r3.get('malbrkamt'), 32.50);

      final r4 = marketsWith({'ausminibfee': 40.0})
          .firstWhere((m) => m.name == 'Australia')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (ausminibfee=40)', r4.get('malbrkamt'), 7.50);
    });

    test('Japan: japminbroff / japminforbrk / japminbrtcomb / japminibfee', () {
      final base = market('Japan').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (default)', base.get('malbrkamt'), 650.00);

      final r1 = marketsWith({'japminbroff': 1800.0})
          .firstWhere((m) => m.name == 'Japan')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (japminbroff=1800)', r1.get('malbrkamt'), 900.00);

      final r2 = marketsWith({'japminforbrk': 3600.0})
          .firstWhere((m) => m.name == 'Japan')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (japminforbrk=3600 -> malbrok 4900)', r2.get('malbrkamt'), 950.00);

      final r3 = marketsWith({'japminbrtcomb': 5300.0})
          .firstWhere((m) => m.name == 'Japan')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (japminbrtcomb=5300)', r3.get('malbrkamt'), 1150.00);

      final r4 = marketsWith({'japminibfee': 4000.0})
          .firstWhere((m) => m.name == 'Japan')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (japminibfee=4000)', r4.get('malbrkamt'), 150.00);
    });

    test('Germany: germinbroff / germinforbrk / germinbrtcomb / germinibfee', () {
      final base = market('Germany').calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (default)', base.get('malbrkamt'), 20.00);

      final r1 = marketsWith({'germinbroff': 60.0})
          .firstWhere((m) => m.name == 'Germany')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (germinbroff=60)', r1.get('malbrkamt'), 30.00);

      final r2 = marketsWith({'germinforbrk': 25.0})
          .firstWhere((m) => m.name == 'Germany')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (germinforbrk=25 -> malbrok 65)', r2.get('malbrkamt'), 22.50);

      final r3 = marketsWith({'germinbrtcomb': 90.0})
          .firstWhere((m) => m.name == 'Germany')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (germinbrtcomb=90)', r3.get('malbrkamt'), 35.00);

      final r4 = marketsWith({'germinibfee': 30.0})
          .firstWhere((m) => m.name == 'Germany')
          .calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('malbrkamt (germinibfee=30)', r4.get('malbrkamt'), 15.00);
    });

    test('Canada: canminbroff / canminbrton / canminibfee (mode-aware)', () {
      final base = market('Canada');
      final baseOff = base.calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      final baseOn = base.calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50);
      check('offline malbrkamt (default)', baseOff.get('malbrkamt'), 7.50);
      check('online malbrkamt (default)', baseOn.get('malbrkamt'), 7.50);

      final ca1 = marketsWith({'canminbroff': 115.0}).firstWhere((m) => m.name == 'Canada');
      check('offline malbrkamt (canminbroff=115)',
          ca1.calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50).get('malbrkamt'), 17.50);
      check('online malbrkamt unaffected by canminbroff',
          ca1.calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50).get('malbrkamt'), 7.50);

      final ca2 = marketsWith({'canminbrton': 125.0}).firstWhere((m) => m.name == 'Canada');
      check('online malbrkamt (canminbrton=125)',
          ca2.calculate(mode: 6, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50).get('malbrkamt'), 22.50);
      check('offline malbrkamt unaffected by canminbrton',
          ca2.calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50).get('malbrkamt'), 7.50);

      final ca3 = marketsWith({'canminibfee': 60.0}).firstWhere((m) => m.name == 'Canada');
      check('offline malbrkamt (canminibfee=60)',
          ca3.calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00, rate: 0.50).get('malbrkamt'), 17.50);

      final ca4 = marketsWith({'canminbroff': 115.0}).firstWhere((m) => m.name == 'Canada');
      check('offline special-rate malbrkamt (canminbroff=115)',
          ca4.calculate(mode: 5, buysel: 1, flag: 2, qty: 100, price: 1.00, rate: 0.50, brkrate: 0.20).get('malbrkamt'),
          17.50);
      final ca5 = marketsWith({'canminbrton': 125.0}).firstWhere((m) => m.name == 'Canada');
      check('online special-rate malbrkamt (canminbrton=125)',
          ca5.calculate(mode: 6, buysel: 1, flag: 2, qty: 100, price: 1.00, rate: 0.50, brkrate: 0.20).get('malbrkamt'),
          22.50);
    });

  group('Malaysia Min Brokerage Settings (malminbrk / malminbrk8)', () {
    final base = market('Malaysia');
    final s = base.s;

    // Small trade: gross = 100 * 1.00 = 100, offline rate 0.10% => rate-based 0.10.
    // Without the MIN RM12/RM8 flag there is no tier override, so the brokerage
    // falls back to the global min offline brokerage (offlinebrk = RM40).
    test('no min-RM flag: falls back to offlinebrk minimum (RM40)', () {
      final c = base.calculate(mode: 5, buysel: 1, flag: 0, qty: 100, price: 1.00);
      check('brkamt', c.get('brkamt'), 40.00);
    });

    // RM12 tier (flag=1): brokerage floor = malminbrk=12. 0.10 < 12 => 12.
    test('RM12 tier uses malminbrk=12 (rate-based 0.10 < 12 => 12)', () {
      final c = base.calculate(
        mode: 5, buysel: 1, flag: 1, qty: 100, price: 1.00,
        minBrkOverride: s.get('malminbrk'));
      check('brkamt', c.get('brkamt'), 12.00);
    });

    // RM8 tier (flag=1): brokerage floor = malminbrk8=8. 0.10 < 8 => 8.
    test('RM8 tier uses malminbrk8=8 (rate-based 0.10 < 8 => 8)', () {
      final c = base.calculate(
        mode: 5, buysel: 1, flag: 1, qty: 100, price: 1.00,
        minBrkOverride: s.get('malminbrk8'));
      check('brkamt', c.get('brkamt'), 8.00);
    });

    // Custom malminbrk=14 via settings => RM12 tier floor becomes 14.
    test('custom malminbrk=14 => RM12 floor 14 (rate-based 0.10 < 14)', () {
      final m = malaysiaWith({'malminbrk': 14.0});
      final c = m.calculate(
        mode: 5, buysel: 1, flag: 1, qty: 100, price: 1.00,
        minBrkOverride: m.s.get('malminbrk'));
      check('brkamt', c.get('brkamt'), 14.00);
    });

    // Custom malminbrk8=6 via settings => RM8 tier floor becomes 6.
    test('custom malminbrk8=6 => RM8 floor 6 (rate-based 0.10 < 6)', () {
      final m = malaysiaWith({'malminbrk8': 6.0});
      final c = m.calculate(
        mode: 5, buysel: 1, flag: 1, qty: 100, price: 1.00,
        minBrkOverride: m.s.get('malminbrk8'));
      check('brkamt', c.get('brkamt'), 6.00);
    });

    // Large trade (>= RM100K): offline rate maloffbrkrate2=0.30% => rate-based
    // 15000 > floor 12, so the minimum is a floor not a forced amount.
    test('large trade RM12: rate-based 15000 > floor 12 => 15000 (floor, not forced)', () {
      final c = base.calculate(
        mode: 5, buysel: 1, flag: 1, qty: 500000, price: 10.0,
        minBrkOverride: s.get('malminbrk'));
      check('brkamt', c.get('brkamt'), 15000.00);
    });

    // Online mode: rate malonbrkrate1=0.10 for <100K, floor 12 => 12.
    test('online RM12 tier: rate-based 0.10 < 12 => 12', () {
      final c = base.calculate(
        mode: 6, buysel: 1, flag: 1, qty: 100, price: 1.00,
        minBrkOverride: s.get('malminbrk'));
      check('brkamt', c.get('brkamt'), 12.00);
    });

    // Special rate + RM12 (flag=3): brkamtrate=brkrate=0.05, floor=12.
    // gross=100 => rate-based 0.05 < 12 => 12.
    test('special+RM12: brkamt = max(0.05%*100=0.05, floor 12) = 12', () {
      final c = base.calculate(
        mode: 5, buysel: 1, flag: 3, qty: 100, price: 1.00,
        brkrate: 0.05, minBrkOverride: s.get('malminbrk'));
      check('brkamt', c.get('brkamt'), 12.00);
    });

    // Special rate + RM8 (flag=3): floor=8 => 8.
    test('special+RM8: brkamt = max(0.05%*100=0.05, floor 8) = 8', () {
      final c = base.calculate(
        mode: 5, buysel: 1, flag: 3, qty: 100, price: 1.00,
        brkrate: 0.05, minBrkOverride: s.get('malminbrk8'));
      check('brkamt', c.get('brkamt'), 8.00);
    });
  });
  });
}
