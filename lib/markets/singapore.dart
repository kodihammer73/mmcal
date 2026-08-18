import '../engine/engine.dart';


class SingaporeMarket extends ForeignMarket {
  @override String get name => 'Singapore';
  @override String get currency => 'SGD';
  @override bool get supportsOnline => true;
  @override bool get supportsHkd => true;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;

  static const double localMinOffline = 33;
  static const double localMinOnline = 27;
  static const double localMinOnlineSpecial = 14;
  static const double foreignMin = 6;

  @override String? get clearingRateKey => 'sinclrfeerate';
  @override String? get tradingRateKey => 'sintrdfeerate';
  @override String? get foreignChargeKey => 'sinforchrgrate';
  @override String? get levyRateKey => null;
  @override String? get ccassRateKey => null;
  @override String? get ccassMinKey => null;
  @override String? get hkStampRateKey => null;
  @override String? get assfundKey => null;
  @override String? get exchfeeKey => null;
  @override String? get salestaxKey => null;
  @override String get minOffBrkKey => 'sinoffminrmbrkrate';
  @override String get maxOffBrkKey => 'sinoffmaxrmbrkrate';
  @override String? get minOnBrkKey => 'sinonminrmbrkrate';
  @override String? get maxOnBrkKey => 'sinonmaxrmbrkrate';
  @override String get stampDutyRateKey => 'sinstmpdutyrate';
  @override String get gstFormula => 'sg';
  @override String get ibrmFormula => 'sg';
  @override double get minIbFee => 0;

  SingaporeMarket(super.s);


  @override
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate) {
    double proceedsRm = qty * price * rate;
    double brkamtrate;
    double malbrok;
    if (mode == 5) {
      brkamtrate = proceedsRm < s.get('rmbrkamt') ? s.get(minOffBrkKey) : s.get(maxOffBrkKey);
      malbrok = qty * price * brkamtrate / 100;
      if (malbrok < localMinOffline) malbrok = localMinOffline;
    } else {
      brkamtrate = proceedsRm < s.get('rmbrkamt') ? s.get(minOnBrkKey!) : s.get(maxOnBrkKey!);
      malbrok = qty * price * brkamtrate / 100;
      if (malbrok < localMinOnline) malbrok = localMinOnline;
    }
    return (brkamtrate, malbrok);
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
  }) {
    final flagSpecial = (flag & 2) != 0;
    final flagNoGst = (flag & 16) != 0;

    double effectiveRate = rate;
    var (brkamtrate, malbrok) = determineRates(mode, buysel, qty, price, effectiveRate);

    if (flagSpecial) {
      brkamtrate = brkrate;
      if (mode == 5) {
        malbrok = qty * price * brkamtrate / 100;
        if (malbrok < localMinOffline) malbrok = localMinOffline;
      } else {
        malbrok = qty * price * brkamtrate / 100;
        if (malbrok < localMinOnlineSpecial) malbrok = localMinOnlineSpecial;
      }
    }

    double clrfeerate = s.get(clearingRateKey!);
    double trdfeerate = s.get(tradingRateKey!);
    double forchrrate = s.get(foreignChargeKey!);

    double gross = qty * price;
    double rmgross = qty * price * effectiveRate;

    double stampduty = stampDutyRm(rmgross, stampDutyRateKey);
    double stampdutyRaw = stampDutyRmRaw(rmgross, stampDutyRateKey);

    double clrfee = gross * (clrfeerate / 100);
    double clrfee1 = roundUp2dp(clrfee);

    double forbrkamt = gross * (forchrrate / 100);
    if (forbrkamt < foreignMin) forbrkamt = foreignMin;
    forbrkamt = round2dp(forbrkamt);

    double malbrok2dp = truncate2dp(malbrok);
    double malbrkamt = malbrok2dp * effectiveRate;
    double malbrkamt1 = round2dp(malbrkamt);

    double trdfee = gross * (trdfeerate / 100);
    double trdfee1 = round2dp(trdfee);

    double gstbrkamt = round2dp(malbrkamt1 * (s.get('gstrate') / 100));
    double gstforfee = round2dp((forbrkamt + clrfee1 + trdfee) * effectiveRate * (s.get('gstrate') / 100));
    double gstclrfee = 0;

    if (flagNoGst) { gstbrkamt = 0; gstforfee = 0; gstclrfee = 0; }

    double ibrmcharges = round2dp((forbrkamt + clrfee1 + trdfee1) * effectiveRate);

    double gstbrkamtcv = effectiveRate != 0 ? round2dp(gstbrkamt / effectiveRate) : 0;
    double gstforfeecv = effectiveRate != 0 ? round2dp(gstforfee / effectiveRate) : 0;
    double ibcharges = effectiveRate != 0 ? round2dp((malbrkamt1 + stampduty) / effectiveRate) : 0;

    double clrfeeRm = round2dp(clrfee1 * effectiveRate);
    double forbrkamtRm = round2dp(forbrkamt * effectiveRate);
    double trdfeeRm = round2dp(trdfee1 * effectiveRate);

    double val1, val2;
    if (buysel == 1) {
      val1 = rmgross + malbrkamt1 + stampduty + clrfeeRm + forbrkamtRm + trdfeeRm;
      val2 = gross + forbrkamt + clrfee1 + trdfee1 + gstbrkamtcv + gstforfeecv + ibcharges;
    } else {
      val1 = rmgross - malbrkamt1 - stampduty - clrfeeRm - forbrkamtRm - trdfeeRm;
      val2 = gross - forbrkamt - clrfee1 - trdfee1 - gstbrkamtcv - gstforfeecv - ibcharges;
    }

    return CalcResult({
      'gross': gross, 'rmgross': rmgross, 'brkamtrate': brkamtrate,
      'malbrkamt': malbrkamt1, 'stampduty': stampduty, 'stampduty_raw': stampdutyRaw,
      'stampdutyrate': s.get(stampDutyRateKey),
      'clrfee': clrfee1, 'clrfee_rm': clrfeeRm, 'clrfeerate': clrfeerate,
      'trdfee': trdfee1, 'trdfee_rm': trdfeeRm,
      'gstbrkamt': gstbrkamt, 'gstclrfee': gstclrfee, 'gstforfee': gstforfee,
      'forbrkamt': forbrkamt, 'forbrkamt_rm': forbrkamtRm,
      'gstbrkamtcv': gstbrkamtcv, 'gstforfeecv': gstforfeecv,
      'ibrmcharges': ibrmcharges, 'ibcharges': ibcharges,
      'levyfee': 0, 'forstampduty': 0, 'ccassfee': 0, 'assfund': 0, 'exchfee': 0, 'salestax': 0,
      'val1': val1, 'val2': val2, 'net_value': val1,
    });
  }

  @override
  double netSellValue(CalcResult calc) {
    return calc.get('rmgross') - calc.get('malbrkamt') - calc.get('stampduty')
        - calc.get('clrfee_rm') - calc.get('forbrkamt_rm') - calc.get('trdfee_rm');
  }
}