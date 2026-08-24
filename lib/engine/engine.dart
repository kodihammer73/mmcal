import '../config/settings.dart';

// ============================================================
// Rounding helpers
// ============================================================

double round2dp(double value) {
  return (value * 100).roundToDouble() / 100;
}

double truncate2dp(double value) {
  return (value * 100).truncateToDouble() / 100;
}

double roundUp2dp(double value) {
  return (value * 100).ceilToDouble() / 100;
}

// ============================================================
// Calculation result
// ============================================================

class CalcResult {
  final Map<String, double> data;
  CalcResult(this.data);
  double get(String key) => data[key] ?? 0.0;
  bool has(String key) => data.containsKey(key);
}

// ============================================================
// Base Market
// ============================================================

abstract class Market {
  String get name;
  String get currency;
  bool get supportsOnline;
  bool get supportsHkd;
  bool get flagMinRm12;
  bool get flagNoSduty;

  final SettingsManager s;
  Market(this.s);

  CalcResult calculate({
    required int mode, // 5=offline, 6=online
    required int buysel, // 1=buy, 2=sell
    required int flag, // bitfield
    required double qty,
    required double price,
    double rate = 1.0,
    double brkrate = 0,
    double? minBrkOverride, // Malaysia only: min-brokerage tier override (e.g. RM8)
  });

  /// Net sell value in RM (for breakeven/contra)
  double netSellValue(CalcResult calc) => calc.get('net_value');

  /// Calculate 5 breakeven price points
  List<Map<String, double>> breakeven({
    required double buyval,
    required double buyprice,
    required int flag,
    required double qty,
    required int mode,
    required double bexchrate,
    double sexchrate = 0,
    double brkrate = 0,
  }) {
    double rate = (sexchrate != 0) ? sexchrate : bexchrate;
    List<Map<String, double>> results = [];

    for (int i = 0; i < 5; i++) {
      while (true) {
        double ticker;
        if (buyprice < 1 - 1e-5) {
          ticker = 0.005;
        } else if (buyprice < 10 - 1e-5) {
          ticker = 0.01;
        } else if (buyprice < 100 - 1e-5) {
          ticker = 0.02;
        } else if (buyprice < 1000 - 1e-5) {
          ticker = 0.1;
        } else {
          ticker = 1;
        }
        buyprice += ticker;
        final calc = calculate(
          mode: mode, buysel: 2, flag: flag, qty: qty, price: buyprice, rate: rate, brkrate: brkrate,
        );
        final selval = netSellValue(calc);
        if (selval > buyval) break;
      }
      final calc = calculate(
        mode: mode, buysel: 2, flag: flag, qty: qty, price: buyprice, rate: rate, brkrate: brkrate,
      );
      results.add({'price': buyprice, 'selval': netSellValue(calc)});
    }
    return results;
  }

  // Stamp duty (RM, ceiling to whole RM)
  double stampDutyRm(double rmgross, String rateKey) {
    double rate = s.get(rateKey);
    double sd = rmgross * (rate / 100);
    if (sd < s.get('minstampduty')) sd = s.get('minstampduty');
    if (sd > s.get('maxstampduty')) sd = s.get('maxstampduty');
    int valueB = sd.truncate();
    if (valueB < sd - 1e-5) sd = (valueB + 1).toDouble();
    return sd;
  }

  // Stamp duty raw (2dp, no ceiling)
  double stampDutyRmRaw(double rmgross, String rateKey) {
    double rate = s.get(rateKey);
    double sd = rmgross * (rate / 100);
    if (sd < s.get('minstampduty')) sd = s.get('minstampduty');
    if (sd > s.get('maxstampduty')) sd = s.get('maxstampduty');
    return round2dp(sd);
  }
}

// ============================================================
// Foreign Market Base
// ============================================================

abstract class ForeignMarket extends Market {
  ForeignMarket(super.s);

  String? get clearingRateKey;
  String? get tradingRateKey;
  String? get foreignChargeKey;
  String? get levyRateKey;
  String? get ccassRateKey;
  String? get ccassMinKey;
  String? get hkStampRateKey;
  String? get assfundKey;
  String? get exchfeeKey;
  String? get salestaxKey;
  String get minOffBrkKey;
  String get maxOffBrkKey;
  String? get minOnBrkKey;
  String? get maxOnBrkKey;
  String get stampDutyRateKey;
  String get gstFormula; // 'sg','hk','us_th','id','au_jp_ca_de'
  String get ibrmFormula; // 'sg','hk','us_th_uk','id','au_jp_ca_de'
  double get minIbFee;

  /// Local brokerage minimum (in market currency) - used for special rate
  double get specialLocalMin => 0;
  /// Foreign brokerage minimum (in market currency) - used for special rate
  double get specialForeignMin => 0;
  /// Combined brokerage minimum (in market currency) - used for special rate
  double get specialCombinedMin => 0;

  /// Returns (brkamtrate, malbrok)
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate);

  double getClearingRate(int mode, int buysel) {
    if (clearingRateKey != null) return s.get(clearingRateKey!);
    return 0;
  }

  @override
  CalcResult calculate({
    required int mode,
    required int buysel,
    required int flag,
    required double qty,
    required double price,
    double rate = 1.0,
    double brkrate = 0,
    double? minBrkOverride, // unused: min-brokerage tiers apply to Malaysia only
  }) {
    final flagSpecial = (flag & 2) != 0;
    final flagNoGst = (flag & 16) != 0;

    double effectiveRate = rate;
    var (brkamtrate, malbrok) = determineRates(mode, buysel, qty, price, effectiveRate);

    if (flagSpecial) {
      brkamtrate = brkrate;
      double gross0 = qty * price;
      double frate = foreignChargeKey != null ? s.get(foreignChargeKey!) : 0;
      double localBrk = gross0 * brkrate / 100;
      if (localBrk < specialLocalMin) localBrk = specialLocalMin;
      double foreignBrk = gross0 * frate / 100;
      if (foreignBrk < specialForeignMin) foreignBrk = specialForeignMin;
      malbrok = localBrk + foreignBrk;
      if (malbrok < specialCombinedMin) malbrok = specialCombinedMin;
    }

    double clrfeerate = getClearingRate(mode, buysel);
    double trdfeerate = tradingRateKey != null ? s.get(tradingRateKey!) : 0;
    double forchrrate = foreignChargeKey != null ? s.get(foreignChargeKey!) : 0;
    double levyfeerate = levyRateKey != null ? s.get(levyRateKey!) : 0;
    double ccassfeerate = ccassRateKey != null ? s.get(ccassRateKey!) : 0;
    double minccassfee = ccassMinKey != null ? s.get(ccassMinKey!) : 0;
    double forstampdutyrate = hkStampRateKey != null ? s.get(hkStampRateKey!) : 0;
    double forassfund = assfundKey != null ? s.get(assfundKey!) : 0;
    double forexchfee = exchfeeKey != null ? s.get(exchfeeKey!) : 0;
    double forsalestax = salestaxKey != null ? s.get(salestaxKey!) : 0;

    double gross = qty * price;
    double rmgross = qty * price * effectiveRate;

    double stampduty = stampDutyRm(rmgross, stampDutyRateKey);
    double stampdutyRaw = stampDutyRmRaw(rmgross, stampDutyRateKey);

    double clrfee = gross * (clrfeerate / 100);
    double clrfee1 = roundUp2dp(clrfee);

    double forbrkamt = gross * (forchrrate / 100);
    if (minIbFee > 0 && forbrkamt < minIbFee) forbrkamt = minIbFee;
    forbrkamt = round2dp(forbrkamt);

    double malbrkamt = (malbrok - forbrkamt) * effectiveRate;
    double malbrkamt1 = round2dp(malbrkamt);

    double trdfee = gross * (trdfeerate / 100);
    double trdfee1 = round2dp(trdfee);

    double assfund = round2dp(gross * (forassfund / 100));
    double exchfee = round2dp(gross * (forexchfee / 100));
    double salestax = round2dp(gross * (forsalestax / 100));

    double ccassfee = gross * (ccassfeerate / 100);
    if (ccassfee < minccassfee) ccassfee = minccassfee;
    double ccassfee1 = round2dp(ccassfee);

    double levyfee = round2dp(gross * (levyfeerate / 100));

    double forstampduty = gross * forstampdutyrate;
    int fsdB = forstampduty.truncate();
    if (fsdB < forstampduty - 1e-5) forstampduty = (fsdB + 1).toDouble();

    // GST on Malaysia brokerage - uses UNROUNDED malbrkamt (matches Python generic)
    double gstbrkamt = round2dp(malbrkamt * (s.get('gstrate') / 100));
    if (flagNoGst) gstbrkamt = 0;

    double gstBase = 0;
    switch (gstFormula) {
      case 'sg': gstBase = forbrkamt + clrfee1 + trdfee; break;
      case 'hk': gstBase = forbrkamt + ccassfee + trdfee; break;
      case 'us_th': gstBase = forbrkamt + clrfee1; break;
      case 'id': gstBase = forbrkamt + clrfee1 + assfund + exchfee + salestax; break;
      case 'au_jp_ca_de': gstBase = forbrkamt; break;
    }

    double gstforfee = round2dp(gstBase * effectiveRate * (s.get('gstrate') / 100));
    double gstclrfee = 0;
    if (['sg', 'us_th', 'id'].contains(gstFormula)) {
      gstclrfee = round2dp(clrfee1 * effectiveRate * (s.get('gstrate') / 100));
      gstforfee = round2dp(gstforfee - gstclrfee);
    }
    if (flagNoGst) { gstforfee = 0; gstclrfee = 0; }

    double ibrmcharges;
    switch (ibrmFormula) {
      case 'sg': ibrmcharges = round2dp((forbrkamt + clrfee1 + trdfee1) * effectiveRate); break;
      case 'hk': ibrmcharges = round2dp((forbrkamt + forstampduty + ccassfee1 + levyfee + trdfee1) * effectiveRate); break;
      case 'us_th_uk': ibrmcharges = round2dp((forbrkamt + clrfee1) * effectiveRate); break;
      case 'id': ibrmcharges = round2dp((forbrkamt + clrfee1 + assfund + exchfee + salestax) * effectiveRate); break;
      case 'au_jp_ca_de': ibrmcharges = round2dp(forbrkamt * effectiveRate); break;
      default: ibrmcharges = 0;
    }

    double gstbrkamtcv = effectiveRate != 0 ? round2dp(gstbrkamt / effectiveRate) : 0;
    double gstforfeecv = effectiveRate != 0 ? round2dp(gstforfee / effectiveRate) : 0;
    double ibcharges = effectiveRate != 0 ? round2dp((malbrkamt1 + stampduty) / effectiveRate) : 0;

    double val1, val2;
    if (buysel == 1) {
      val1 = rmgross + malbrkamt1 + stampduty + gstbrkamt + gstforfee + ibrmcharges;
      val2 = gross + forbrkamt + clrfee1 + trdfee1 + gstbrkamtcv + gstforfeecv + ibcharges;
    } else {
      val1 = rmgross - malbrkamt1 - stampduty - gstbrkamt - gstforfee - ibrmcharges;
      val2 = gross - forbrkamt - clrfee1 - trdfee1 - gstbrkamtcv - gstforfeecv - ibcharges;
    }

    return CalcResult({
      'gross': gross, 'rmgross': rmgross, 'brkamtrate': brkamtrate,
      'malbrkamt': malbrkamt1, 'stampduty': stampduty, 'stampduty_raw': stampdutyRaw,
      'stampdutyrate': s.get(stampDutyRateKey),
      'clrfee': clrfee1, 'clrfeerate': clrfeerate,
      'trdfee': trdfee1,
      'gstbrkamt': gstbrkamt, 'gstclrfee': gstclrfee, 'gstforfee': gstforfee,
      'forbrkamt': forbrkamt,
      'gstbrkamtcv': gstbrkamtcv, 'gstforfeecv': gstforfeecv,
      'ibrmcharges': ibrmcharges, 'ibcharges': ibcharges,
      'levyfee': levyfee, 'forstampduty': forstampduty, 'ccassfee': ccassfee1,
      'assfund': assfund, 'exchfee': exchfee, 'salestax': salestax,
      'val1': val1, 'val2': val2, 'net_value': val1,
    });
  }

  @override
  double netSellValue(CalcResult calc) {
    return calc.get('rmgross') - calc.get('malbrkamt') - calc.get('stampduty')
        - calc.get('gstbrkamt') - calc.get('gstforfee') - calc.get('ibrmcharges');
  }
}