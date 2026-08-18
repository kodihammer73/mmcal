import '../engine/engine.dart';


class MalaysiaMarket extends Market {
  @override String get name => 'Malaysia';
  @override String get currency => 'MYR';
  @override bool get supportsOnline => true;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => true;
  @override bool get flagNoSduty => true;

  MalaysiaMarket(super.s);


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
    final flagMinRm12 = (flag & 1) != 0;
    final flagSpecial = (flag & 2) != 0;
    final flagNoSduty = (flag & 4) != 0;
    final flagNoGst = (flag & 16) != 0;

    // Map to Liberty BASIC lb_flag
    int lbFlag = 0;
    if (flagSpecial && flagMinRm12 && flagNoSduty) {
      lbFlag = 9;
    } else if (flagSpecial && flagMinRm12) {
      lbFlag = 3;
    } else if (flagSpecial && flagNoSduty) {
      lbFlag = 7;
    } else if (flagSpecial) {
      lbFlag = 2;
    } else if (flagMinRm12 && flagNoSduty) {
      lbFlag = 10;
    } else if (flagMinRm12) {
      lbFlag = 1;
    } else if (flagNoSduty) {
      lbFlag = 8;
    }


    double brkamtrate;
    double brokerage;
    if (mode == 5) {
      brkamtrate = (qty * price) < s.get('rmbrkamt')
          ? s.get('maloffbrkrate1')
          : s.get('maloffbrkrate2');
      brokerage = s.get('offlinebrk');
    } else {
      brkamtrate = (qty * price) < s.get('rmbrkamt')
          ? s.get('malonbrkrate1')
          : s.get('malonbrkrate2');
      brokerage = s.get('onlinebrk');
    }

    double clrfeerate = s.get('malclrfeerate');

    if (lbFlag == 1 || lbFlag == 3 || lbFlag == 9 || lbFlag == 10) {
      brokerage = s.get('malminbrk');
    }
    if (lbFlag == 2 || lbFlag == 3 || lbFlag == 7 || lbFlag == 9) {
      brkamtrate = brkrate;
    }

    double gross = qty * price;

    // Stamp duty
    double stampduty = gross * (s.get('malstmpdutyrate') / 100);
    if (stampduty < s.get('minstampduty')) stampduty = s.get('minstampduty');
    if (stampduty > s.get('maxstampduty')) stampduty = s.get('maxstampduty');
    int valueB = stampduty.truncate();
    if (valueB < stampduty - 1e-5) stampduty = (valueB + 1).toDouble();

    if ([7, 8, 9, 10].contains(lbFlag)) stampduty = 0;

    double clrfee = gross * (clrfeerate / 100);

    double brkamt = gross * (brkamtrate / 100);
    if (brkamt < brokerage) brkamt = brokerage;

    double gstbrkamt = 0;
    double gstclrfee = 0;
    if (!flagNoGst) {
      gstbrkamt = brkamt * (s.get('gstrate') / 100);
      gstclrfee = clrfee * (s.get('gstrate') / 100);
    }

    double brkamt1 = round2dp(brkamt);
    double clrfee1 = roundUp2dp(clrfee);
    double gstbrkamt1 = round2dp(gstbrkamt);
    double gstclrfee1 = round2dp(gstclrfee);

    double netValue;
    if (buysel == 1) {
      netValue = gross + brkamt1 + stampduty + clrfee1 + gstbrkamt1 + gstclrfee1;
    } else {
      netValue = gross - brkamt1 - stampduty - clrfee1 - gstbrkamt1 - gstclrfee1;
    }

    return CalcResult({
      'gross': gross,
      'brkamtrate': brkamtrate,
      'brkamt': brkamt1,
      'stampduty': stampduty,
      'stampdutyrate': s.get('malstmpdutyrate'),
      'clrfee': clrfee1,
      'clrfeerate': clrfeerate,
      'gstbrkamt': gstbrkamt1,
      'gstclrfee': gstclrfee1,
      'net_value': netValue,
    });
  }

  @override
  double netSellValue(CalcResult calc) {
    return calc.get('gross') - calc.get('brkamt') - calc.get('stampduty')
        - calc.get('clrfee') - calc.get('gstbrkamt') - calc.get('gstclrfee');
  }

  /// DF A/C calculation
  Map<String, double> dfAcCalculate({
    required int mode,
    required int buysel,
    required int flag,
    required double qty,
    required double price,
    double rate = 1.0,
    double brkrate = 0,
    int noday = 5,
  }) {
    final base = calculate(mode: mode, buysel: buysel, flag: flag, qty: qty, price: price, rate: rate, brkrate: brkrate);
    double buyval = base.get('net_value');

    if (noday <= 4) {
      return {'dfint': 0, 'dffee': 0, 'dfgstfee': 0, 'total': buyval};
    }
    if (noday > 8) noday = 8;

    double dfint = buyval * 0.0925 / 365 * (noday - 4);
    double dffee;
    if (buyval < 100000) {
      dffee = buyval * 0.003;
      if (dffee < 10) dffee = 10;
    } else {
      dffee = buyval * 0.002;
    }
    double dfgstfee = dffee * 0.06;
    double total = buyval + dfint + dffee + dfgstfee;
    return {'dfint': dfint, 'dffee': dffee, 'dfgstfee': dfgstfee, 'total': total};
  }
}