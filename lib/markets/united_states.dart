import '../engine/engine.dart';


class UnitedStatesMarket extends ForeignMarket {
  @override String get name => 'United States (US)';
  @override String get currency => 'USD';
  @override bool get supportsOnline => true;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;

  // Local/foreign/total brokerage minimums (USD) - editable in Settings > US
  double get localMinOffline => s.get('usaminbroff');
  double get localMinOnline => s.get('usaminbron');
  double get foreignMin => s.get('usaminforbrk');
  double get totalMinOffline => s.get('usaminbrtoff');

  @override String? get clearingRateKey => 'usasecfeerate';
  @override String? get tradingRateKey => null;
  @override String? get foreignChargeKey => 'usaforchrgrate';
  @override String? get levyRateKey => null;
  @override String? get ccassRateKey => null;
  @override String? get ccassMinKey => null;
  @override String? get hkStampRateKey => null;
  @override String? get assfundKey => null;
  @override String? get exchfeeKey => null;
  @override String? get salestaxKey => null;
  @override String get minOffBrkKey => 'usaoffminrmbrkrate';
  @override String get maxOffBrkKey => 'usaoffmaxrmbrkrate';
  @override String? get minOnBrkKey => 'usaonminrmbrkrate';
  @override String? get maxOnBrkKey => 'usaonmaxrmbrkrate';
  @override String get stampDutyRateKey => 'usastmpdutyrate';
  @override String get gstFormula => 'us_th';
  @override String get ibrmFormula => 'us_th_uk';
  @override double get minIbFee => 0;

  UnitedStatesMarket(super.s);


  @override
  double getClearingRate(int mode, int buysel) {
    return buysel == 2 ? s.get('usasecfeerate') : 0;
  }

  @override
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate) {
    double proceedsRm = qty * price * rate;
    double brkamtrate;
    double localBrk;
    double? totalMin;

    if (mode == 5) {
      if (proceedsRm < s.get('rmbrkamt')) {
        brkamtrate = s.get(minOffBrkKey);
        localBrk = localMinOffline;
      } else {
        brkamtrate = s.get(maxOffBrkKey);
        localBrk = qty * price * brkamtrate / 100;
        if (localBrk < localMinOffline) localBrk = localMinOffline;
      }
      totalMin = totalMinOffline;
    } else {
      if (proceedsRm < s.get('rmbrkamt')) {
        brkamtrate = s.get(minOnBrkKey!);
        localBrk = localMinOnline;
      } else {
        brkamtrate = s.get(maxOnBrkKey!);
        localBrk = qty * price * brkamtrate / 100;
        if (localBrk < localMinOnline) localBrk = localMinOnline;
      }
      totalMin = null;
    }

    double foreignBrk = qty * price * (s.get(foreignChargeKey!) / 100);
    if (foreignBrk < foreignMin) foreignBrk = foreignMin;

    double malbrok = localBrk + foreignBrk;
    if (totalMin != null && malbrok < totalMin) malbrok = totalMin;

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
    double? minBrkOverride, // unused: min-brokerage tiers apply to Malaysia only
  }) {
    final flagSpecial = (flag & 2) != 0;
    final flagNoGst = (flag & 16) != 0;

    var (brkamtrate, malbrok) = determineRates(mode, buysel, qty, price, rate);

    if (flagSpecial) {
      brkamtrate = brkrate;
      double localBrk = qty * price * brkamtrate / 100;
      double? totalMin;
      if (mode == 5) {
        if (localBrk < localMinOffline) localBrk = localMinOffline;
        totalMin = totalMinOffline;
      } else {
        if (localBrk < localMinOnline) localBrk = localMinOnline;
        totalMin = null;
      }
      double foreignBrk = qty * price * (s.get(foreignChargeKey!) / 100);
      if (foreignBrk < foreignMin) foreignBrk = foreignMin;
      malbrok = localBrk + foreignBrk;
      if (totalMin != null && malbrok < totalMin) malbrok = totalMin;
    }

    double clrfeerate = getClearingRate(mode, buysel);
    double forchrrate = s.get(foreignChargeKey!);

    double gross = qty * price;
    double rmgross = qty * price * rate;

    double stampduty = stampDutyRm(rmgross, stampDutyRateKey);
    double stampdutyRaw = stampDutyRmRaw(rmgross, stampDutyRateKey);

    double clrfee = gross * (clrfeerate / 100);
    double clrfee1 = roundUp2dp(clrfee);

    double forbrkamt = gross * (forchrrate / 100);
    if (forbrkamt < foreignMin) forbrkamt = foreignMin;
    forbrkamt = round2dp(forbrkamt);

    double malbrkamt = (malbrok - forbrkamt) * rate;
    double malbrkamt1 = round2dp(malbrkamt);

    double gstbrkamt = round2dp(malbrkamt1 * (s.get('gstrate') / 100));
    double gstBase = forbrkamt + clrfee1;
    double gstforfee = round2dp(gstBase * rate * (s.get('gstrate') / 100));
    double gstclrfee = round2dp(clrfee1 * rate * (s.get('gstrate') / 100));
    gstforfee = round2dp(gstforfee - gstclrfee);

    if (flagNoGst) { gstbrkamt = 0; gstforfee = 0; gstclrfee = 0; }

    double ibrmcharges = round2dp((forbrkamt + clrfee1) * rate);

    double gstbrkamtcv = rate != 0 ? round2dp(gstbrkamt / rate) : 0;
    double gstforfeecv = rate != 0 ? round2dp(gstforfee / rate) : 0;
    double ibcharges = rate != 0 ? round2dp((malbrkamt1 + stampdutyRaw) / rate) : 0;

    double val1, val2;
    if (buysel == 1) {
      val1 = rmgross + malbrkamt1 + stampduty + gstbrkamt + gstforfee + ibrmcharges;
      val2 = gross + forbrkamt + clrfee1 + gstbrkamtcv + gstforfeecv + ibcharges;
    } else {
      val1 = rmgross - malbrkamt1 - stampduty - gstbrkamt - gstforfee - ibrmcharges;
      val2 = gross - forbrkamt - clrfee1 - gstbrkamtcv - gstforfeecv - ibcharges;
    }

    return CalcResult({
      'gross': gross, 'rmgross': rmgross, 'brkamtrate': brkamtrate,
      'malbrkamt': malbrkamt1, 'stampduty': stampduty, 'stampduty_raw': stampdutyRaw,
      'stampdutyrate': s.get(stampDutyRateKey),
      'clrfee': clrfee1, 'clrfee_rm': round2dp(clrfee1 * rate), 'clrfeerate': clrfeerate,
      'trdfee': 0,
      'gstbrkamt': gstbrkamt, 'gstclrfee': gstclrfee, 'gstforfee': gstforfee,
      'forbrkamt': forbrkamt, 'forbrkamt_rm': round2dp(forbrkamt * rate),
      'gstbrkamtcv': gstbrkamtcv, 'gstforfeecv': gstforfeecv,
      'ibrmcharges': ibrmcharges, 'ibcharges': ibcharges,
      'levyfee': 0, 'forstampduty': 0, 'ccassfee': 0, 'assfund': 0, 'exchfee': 0, 'salestax': 0,
      'val1': val1, 'val2': val2, 'net_value': val1,
    });
  }
}