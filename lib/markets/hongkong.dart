import '../engine/engine.dart';
import '../config/settings.dart';

class HongKongMarket extends ForeignMarket {
  @override String get name => 'Hong Kong';
  @override String get currency => 'HKD';
  @override bool get supportsOnline => true;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;

  static const double localMinOffline = 110;
  static const double localMinOnlinePromo = 50;
  static const double foreignMin = 40;
  static const double totalMinOnline = 80;

  @override String? get clearingRateKey => null;
  @override String? get tradingRateKey => 'hkdtrdfeerate';
  @override String? get foreignChargeKey => 'hkdforchrgrate';
  @override String? get levyRateKey => 'hkdlevyfeerate';
  @override String? get ccassRateKey => 'hkdccassfeerate';
  @override String? get ccassMinKey => 'hkdminccassfee';
  @override String? get hkStampRateKey => 'hkdstampdutyrate';
  @override String? get assfundKey => null;
  @override String? get exchfeeKey => null;
  @override String? get salestaxKey => null;
  @override String get minOffBrkKey => 'hkdoffminrmbrkrate';
  @override String get maxOffBrkKey => 'hkdoffmaxrmbrkrate';
  @override String? get minOnBrkKey => 'hkdonminrmbrkrate';
  @override String? get maxOnBrkKey => 'hkdonmaxrmbrkrate';
  @override String get stampDutyRateKey => 'hkdlocalstampdutyrate';
  @override String get gstFormula => 'hk';
  @override String get ibrmFormula => 'hk';
  @override double get minIbFee => 0;

  HongKongMarket(SettingsManager s) : super(s);

  @override
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate) {
    double proceedsRm = qty * price * rate;
    double brkamtrate;
    double localBrk;
    double? totalMin;

    if (mode == 5) {
      brkamtrate = proceedsRm < s.get('rmbrkamt') ? s.get(minOffBrkKey) : s.get(maxOffBrkKey);
      localBrk = qty * price * brkamtrate / 100;
      if (localBrk < localMinOffline) localBrk = localMinOffline;
      totalMin = null;
    } else {
      brkamtrate = proceedsRm < s.get('rmbrkamt') ? s.get(minOnBrkKey!) : s.get(maxOnBrkKey!);
      localBrk = qty * price * brkamtrate / 100;
      if (localBrk < localMinOnlinePromo) localBrk = localMinOnlinePromo;
      totalMin = totalMinOnline;
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
  }) {
    final flagSpecial = (flag & 2) != 0;
    final flagNoGst = (flag & 16) != 0;

    double effectiveRate = rate;
    var (brkamtrate, malbrok) = determineRates(mode, buysel, qty, price, effectiveRate);

    if (flagSpecial) {
      brkamtrate = brkrate;
      double foreignRate = s.get(foreignChargeKey!);
      double localBrk = qty * price * brkamtrate / 100;
      double? totalMin;
      if (mode == 5) {
        if (localBrk < localMinOffline) localBrk = localMinOffline;
        totalMin = null;
      } else {
        if (localBrk < localMinOnlinePromo) localBrk = localMinOnlinePromo;
        totalMin = totalMinOnline;
      }
      double foreignBrk = qty * price * (foreignRate / 100);
      if (foreignBrk < foreignMin) foreignBrk = foreignMin;
      malbrok = localBrk + foreignBrk;
      if (totalMin != null && malbrok < totalMin) malbrok = totalMin;
    }

    double trdfeerate = s.get(tradingRateKey!);
    double forchrrate = s.get(foreignChargeKey!);
    double levyfeerate = s.get(levyRateKey!);
    double ccassfeerate = s.get(ccassRateKey!);
    double minccassfee = s.get(ccassMinKey!);
    double forstampdutyrate = s.get(hkStampRateKey!);

    double gross = qty * price;
    double rmgross = qty * price * effectiveRate;

    double stampduty = stampDutyRm(rmgross, stampDutyRateKey);
    double stampdutyRaw = stampDutyRmRaw(rmgross, stampDutyRateKey);

    double forbrkamt = gross * (forchrrate / 100);
    if (forbrkamt < foreignMin) forbrkamt = foreignMin;
    forbrkamt = round2dp(forbrkamt);

    double malbrkamt = (malbrok - forbrkamt) * effectiveRate;
    double malbrkamt1 = round2dp(malbrkamt);

    double trdfee = round2dp(gross * (trdfeerate / 100));

    double ccassfee = gross * (ccassfeerate / 100);
    if (ccassfee < minccassfee) ccassfee = minccassfee;
    double ccassfee1 = round2dp(ccassfee);

    double levyfee = round2dp(gross * (levyfeerate / 100));

    double forstampduty = gross * forstampdutyrate;
    int fsdB = forstampduty.truncate();
    if (fsdB < forstampduty - 1e-5) forstampduty = (fsdB + 1).toDouble();

    double gstbrkamt = round2dp(malbrkamt1 * (s.get('gstrate') / 100));
    double gstforfee = round2dp((forbrkamt + ccassfee + trdfee) * effectiveRate * (s.get('gstrate') / 100));
    double gstclrfee = 0;

    if (flagNoGst) { gstbrkamt = 0; gstforfee = 0; gstclrfee = 0; }

    double ibrmcharges = round2dp((forbrkamt + forstampduty + ccassfee1 + levyfee + trdfee) * effectiveRate);

    double gstbrkamtcv = effectiveRate != 0 ? round2dp(gstbrkamt / effectiveRate) : 0;
    double gstforfeecv = effectiveRate != 0 ? round2dp(gstforfee / effectiveRate) : 0;
    double ibcharges = effectiveRate != 0 ? round2dp((malbrkamt1 + stampdutyRaw) / effectiveRate) : 0;

    double val1, val2;
    if (buysel == 1) {
      val1 = rmgross + malbrkamt1 + stampduty + gstbrkamt + gstforfee + ibrmcharges;
      val2 = gross + forbrkamt + trdfee + forstampduty + ccassfee1 + levyfee + gstbrkamtcv + gstforfeecv + ibcharges;
    } else {
      val1 = rmgross - malbrkamt1 - stampduty - gstbrkamt - gstforfee - ibrmcharges;
      val2 = gross - forbrkamt - trdfee - forstampduty - ccassfee1 - levyfee - gstbrkamtcv - gstforfeecv - ibcharges;
    }

    return CalcResult({
      'gross': gross, 'rmgross': rmgross, 'brkamtrate': brkamtrate,
      'malbrkamt': malbrkamt1, 'stampduty': stampduty, 'stampduty_raw': stampdutyRaw,
      'stampdutyrate': s.get(stampDutyRateKey),
      'clrfee': 0, 'clrfeerate': 0,
      'trdfee': trdfee,
      'gstbrkamt': gstbrkamt, 'gstclrfee': gstclrfee, 'gstforfee': gstforfee,
      'forbrkamt': forbrkamt, 'forbrkamt_rm': round2dp(forbrkamt * effectiveRate),
      'gstbrkamtcv': gstbrkamtcv, 'gstforfeecv': gstforfeecv,
      'ibrmcharges': ibrmcharges, 'ibcharges': ibcharges,
      'levyfee': levyfee, 'forstampduty': forstampduty, 'ccassfee': ccassfee1,
      'assfund': 0, 'exchfee': 0, 'salestax': 0,
      'val1': val1, 'val2': val2, 'net_value': val1,
    });
  }
}