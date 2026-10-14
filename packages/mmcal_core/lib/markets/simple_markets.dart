import '../engine/engine.dart';


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
  // Combined minimum (THB) - editable in Settings > Thailand
  @override double get combinedMin => s.get('thaminbrtcomb');
  @override String? get foreignChargeKey => 'thaforchrgrate';
  @override String get minOffBrkKey => 'thaoffminrmbrkrate';
  @override String get maxOffBrkKey => 'thaoffmaxrmbrkrate';
  @override double get minIbFee => 0;

  ThailandMarket(super.s);

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
  // Combined minimum (IDR) - editable in Settings > Indonesia
  @override double get combinedMin => s.get('indminbrtcomb');
  @override String? get foreignChargeKey => 'indforchrgrate';
  @override String get minOffBrkKey => 'indoffminrmbrkrate';
  @override String get maxOffBrkKey => 'indoffmaxrmbrkrate';
  @override double get minIbFee => 0;

  IndonesiaMarket(super.s);

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
  // Local/foreign/combined minimums (GBP) - editable in Settings > UK
  @override double get localMin => s.get('ukdminbroff');
  @override double get foreignMin => s.get('ukdminforbrk');
  @override double get combinedMin => s.get('ukdminbrtcomb');
  @override String? get foreignChargeKey => 'ukdforchrgrate';
  @override String get minOffBrkKey => 'ukdoffminrmbrkrate';
  @override String get maxOffBrkKey => 'ukdoffmaxrmbrkrate';
  @override double get minIbFee => s.get('ukdminibfee');

  UnitedKingdomMarket(super.s);

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
  // Local/foreign/combined minimums (AUD) - editable in Settings > Australia
  @override double get localMin => s.get('ausminbroff');
  @override double get foreignMin => s.get('ausminforbrk');
  @override double get combinedMin => s.get('ausminbrtcomb');
  @override String? get foreignChargeKey => 'ausforchrgrate';
  @override String get minOffBrkKey => 'ausoffminrmbrkrate';
  @override String get maxOffBrkKey => 'ausoffmaxrmbrkrate';
  @override double get minIbFee => s.get('ausminibfee');

  AustraliaMarket(super.s);

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
  // Local/foreign/combined minimums (JPY) - editable in Settings > Japan
  @override double get localMin => s.get('japminbroff');
  @override double get foreignMin => s.get('japminforbrk');
  @override double get combinedMin => s.get('japminbrtcomb');
  @override String? get foreignChargeKey => 'japforchrgrate';
  @override String get minOffBrkKey => 'japoffminrmbrkrate';
  @override String get maxOffBrkKey => 'japoffmaxrmbrkrate';
  @override double get minIbFee => s.get('japminibfee');

  JapanMarket(super.s);

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
  // Canada's brokerage floor comes from Python's min_brk_offline (mode 5) /
  // min_brk_online (mode 6) - editable in Settings > Canada.
  @override double get localMin => 0;
  @override double get foreignMin => s.get('canminibfee');
  @override double get combinedMin => s.get('canminbroff');
  @override String? get foreignChargeKey => 'canforchrgrate';
  @override String get minOffBrkKey => 'canoffminrmbrkrate';
  @override String get maxOffBrkKey => 'canoffmaxrmbrkrate';
  @override double get minIbFee => s.get('canminibfee');

  /// Canada's local brokerage floor for the given trade mode, mirroring
  /// Python's `min_brk_offline` (mode 5) / `min_brk_online` (mode 6).
  double _minBrk(int mode) => mode == 5 ? combinedMin : s.get('canminbrton');

  // Canada uses the base ForeignMarket._determine_rates pattern:
  // malbrok = max(gross * local_rate / 100, 95) — local only, no foreign added.
  // The foreign minimum (80) is applied separately via minIbFee.
  @override
  (double, double) determineRates(int mode, int buysel, double qty, double price, double rate) {
    double gross = qty * price;
    double proceedsRm = gross * rate;
    double localRate = proceedsRm <= s.get('rmbrkamt') ? s.get(minOffBrkKey) : s.get(maxOffBrkKey);
    double minBrk = _minBrk(mode);
    double malbrok = gross * localRate / 100;
    if (malbrok < minBrk) malbrok = minBrk;
    return (localRate, malbrok);
  }

  // Special rate: Python falls back to combined_min = min_brk_offline (mode 5) /
  // min_brk_online (mode 6), with no local/foreign minimums defined.
  @override double get specialLocalMin => 0;
  @override double get specialForeignMin => 0;
  @override double specialCombinedMinFor(int mode) => _minBrk(mode);

  CanadaMarket(super.s);

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
  // Local/foreign/combined minimums (EUR) - editable in Settings > Germany
  @override double get localMin => s.get('germinbroff');
  @override double get foreignMin => s.get('germinforbrk');
  @override double get combinedMin => s.get('germinbrtcomb');
  @override String? get foreignChargeKey => 'gerforchrgrate';
  @override String get minOffBrkKey => 'geroffminrmbrkrate';
  @override String get maxOffBrkKey => 'geroffmaxrmbrkrate';
  @override double get minIbFee => s.get('germinibfee');

  GermanyMarket(super.s);

}