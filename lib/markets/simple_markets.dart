import '../engine/engine.dart';
import '../config/settings.dart';

// ============================================================
// Simple foreign markets with local+foreign+combined minimums
// ============================================================

abstract class _SimpleMarket extends ForeignMarket {
  _SimpleMarket(super.s);

  double get localMin;
  double get foreignMin;
  double get combinedMin;

  @override String? get clearingRateKey => null;
  @override String? get tradingRateKey => null;
  @override String? get levyRateKey => null;
  @override String? get ccassRateKey => null;
  @override String? get ccassMinKey => null;
  @override String? get hkStampRateKey => null;
  @override String? get assfundKey => null;
  @override String? get exchfeeKey => null;
  @override String? get salestaxKey => null;
  @override String? get minOnBrkKey => null;
  @override String? get maxOnBrkKey => null;
  @override String get stampDutyRateKey => 'malstmpdutyrate';
  @override String get gstFormula => 'au_jp_ca_de';
  @override String get ibrmFormula => 'au_jp_ca_de';
  @override double get minIbFee => foreignMin;

  @override double get specialLocalMin => localMin;
  @override double get specialForeignMin => foreignMin;
  @override double get specialCombinedMin => combinedMin;

  @override
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate) {
    double gross = qty * price;
    double proceedsRm = gross * rate;
    double localRate = proceedsRm <= s.get('rmbrkamt') ? s.get(minOffBrkKey) : s.get(maxOffBrkKey);
    double localBrk = gross * localRate / 100;
    if (localBrk < localMin) localBrk = localMin;
    double foreignBrk = gross * s.get(foreignChargeKey!) / 100;
    if (foreignBrk < foreignMin) foreignBrk = foreignMin;
    double total = localBrk + foreignBrk;
    if (total < combinedMin) total = combinedMin;
    return (localRate, total);
  }
}

// ============================================================
// Thailand
// ============================================================

class ThailandMarket extends _SimpleMarket {
  @override String get name => 'Thailand';
  @override String get currency => 'THB';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 0;
  @override double get foreignMin => 0;
  @override double get combinedMin => 840;
  @override String? get foreignChargeKey => 'thaforchrgrate';
  @override String get minOffBrkKey => 'thaoffminrmbrkrate';
  @override String get maxOffBrkKey => 'thaoffmaxrmbrkrate';
  @override double get minIbFee => 0;

  ThailandMarket(SettingsManager s) : super(s);
}

// ============================================================
// Indonesia
// ============================================================

class IndonesiaMarket extends _SimpleMarket {
  @override String get name => 'Indonesia';
  @override String get currency => 'IDR';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 0;
  @override double get foreignMin => 0;
  @override double get combinedMin => 265000;
  @override String? get foreignChargeKey => 'indforchrgrate';
  @override String get minOffBrkKey => 'indoffminrmbrkrate';
  @override String get maxOffBrkKey => 'indoffmaxrmbrkrate';
  @override double get minIbFee => 0;

  IndonesiaMarket(SettingsManager s) : super(s);
}

// ============================================================
// United Kingdom
// ============================================================

class UnitedKingdomMarket extends _SimpleMarket {
  @override String get name => 'United Kingdom (UK)';
  @override String get currency => 'GBP';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 18;
  @override double get foreignMin => 20;
  @override double get combinedMin => 38;
  @override String? get foreignChargeKey => 'ukdforchrgrate';
  @override String get minOffBrkKey => 'ukdoffminrmbrkrate';
  @override String get maxOffBrkKey => 'ukdoffmaxrmbrkrate';
  @override double get minIbFee => 20;

  UnitedKingdomMarket(SettingsManager s) : super(s);
}

// ============================================================
// Australia
// ============================================================

class AustraliaMarket extends _SimpleMarket {
  @override String get name => 'Australia';
  @override String get currency => 'AUD';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 35;
  @override double get foreignMin => 20;
  @override double get combinedMin => 55;
  @override String? get foreignChargeKey => 'ausforchrgrate';
  @override String get minOffBrkKey => 'ausoffminrmbrkrate';
  @override String get maxOffBrkKey => 'ausoffmaxrmbrkrate';
  @override double get minIbFee => 20;

  AustraliaMarket(SettingsManager s) : super(s);
}

// ============================================================
// Japan
// ============================================================

class JapanMarket extends _SimpleMarket {
  @override String get name => 'Japan';
  @override String get currency => 'JPY';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 1300;
  @override double get foreignMin => 3000;
  @override double get combinedMin => 4300;
  @override String? get foreignChargeKey => 'japforchrgrate';
  @override String get minOffBrkKey => 'japoffminrmbrkrate';
  @override String get maxOffBrkKey => 'japoffmaxrmbrkrate';
  @override double get minIbFee => 3000;

  JapanMarket(SettingsManager s) : super(s);
}

// ============================================================
// Canada
// ============================================================

class CanadaMarket extends _SimpleMarket {
  @override String get name => 'Canada';
  @override String get currency => 'CAD';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 0;
  @override double get foreignMin => 80;
  @override double get combinedMin => 95;
  @override String? get foreignChargeKey => 'canforchrgrate';
  @override String get minOffBrkKey => 'canoffminrmbrkrate';
  @override String get maxOffBrkKey => 'canoffmaxrmbrkrate';
  @override double get minIbFee => 80;

  // Canada uses the base ForeignMarket._determine_rates pattern:
  // malbrok = max(gross * local_rate / 100, 95) — local only, no foreign added.
  // The foreign minimum (80) is applied separately via minIbFee.
  @override
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate) {
    double gross = qty * price;
    double proceedsRm = gross * rate;
    double localRate = proceedsRm <= s.get('rmbrkamt') ? s.get(minOffBrkKey) : s.get(maxOffBrkKey);
    double malbrok = gross * localRate / 100;
    if (malbrok < combinedMin) malbrok = combinedMin;
    return (localRate, malbrok);
  }

  // Special rate: Python falls back to combined_min = min_brk_offline (95),
  // with no local/foreign minimums defined.
  @override double get specialLocalMin => 0;
  @override double get specialForeignMin => 0;
  @override double get specialCombinedMin => 95;

  CanadaMarket(SettingsManager s) : super(s);
}

// ============================================================
// Germany
// ============================================================

class GermanyMarket extends _SimpleMarket {
  @override String get name => 'Germany';
  @override String get currency => 'EUR';
  @override bool get supportsOnline => false;
  @override bool get supportsHkd => false;
  @override bool get flagMinRm12 => false;
  @override bool get flagNoSduty => false;
  @override double get localMin => 40;
  @override double get foreignMin => 20;
  @override double get combinedMin => 60;
  @override String? get foreignChargeKey => 'gerforchrgrate';
  @override String get minOffBrkKey => 'geroffminrmbrkrate';
  @override String get maxOffBrkKey => 'geroffmaxrmbrkrate';
  @override double get minIbFee => 20;

  GermanyMarket(SettingsManager s) : super(s);
}