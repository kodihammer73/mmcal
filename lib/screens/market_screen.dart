import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../engine/engine.dart';
import '../markets/malaysia.dart';

final _numFmt = NumberFormat('#,##0.00');

class MarketScreen extends StatefulWidget {
  final Market market;
  const MarketScreen({super.key, required this.market});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _qtyCtrl = TextEditingController();
  final _buyCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();
  final _buyRateCtrl = TextEditingController(text: '1.0');
  final _sellRateCtrl = TextEditingController(text: '1.0');
  final _brkrateCtrl = TextEditingController(text: '0');
  final _dfDaysCtrl = TextEditingController(text: '5');

  bool _isOnline = true; // Default to online
  bool _flagMinRm12 = false;
  bool _flagNoSduty = false;
  bool _flagSpecial = false;
  bool _applyGst = false; // Desktop: "Apply GST/SST" checkbox (default unchecked)
  bool _settleLocal = false; // "Sett in [currency]" for all foreign markets
  bool _dfAc = false; // Malaysia only
  int _dfDays = 5;

  // Results for the selected mode (offline or online)
  CalcResult? _buy;
  CalcResult? _sell;
  Map<String, double>? _dfBuy;

  int get _flag {
    int f = 0;
    if (_flagMinRm12) f |= 1;
    if (_flagSpecial) f |= 2;
    if (_flagNoSduty) f |= 4;
    if (_settleLocal) f |= 8;
    if (!_applyGst) f |= 16; // bit4: GST/SST NOT applied (matches desktop)
    return f;
  }

  bool get _hasResults => _buy != null || _sell != null;

  void _calculate() {
    double qty = double.tryParse(_qtyCtrl.text) ?? 0;
    double buy = double.tryParse(_buyCtrl.text) ?? 0;
    double sell = double.tryParse(_sellCtrl.text) ?? 0;
    double buyRate = double.tryParse(_buyRateCtrl.text) ?? 0;
    double sellRate = double.tryParse(_sellRateCtrl.text) ?? 0;
    double brkrate = double.tryParse(_brkrateCtrl.text) ?? 0;

    final isMalaysia = widget.market is MalaysiaMarket;
    if (isMalaysia) {
      buyRate = 1.0;
      sellRate = 1.0;
    }

    if (qty <= 0) return;
    if (buy <= 0 && sell <= 0) return;
    if (!isMalaysia && buyRate <= 0 && sellRate <= 0) return;

    // Fill missing rates
    if (buyRate <= 0 && sellRate > 0) buyRate = sellRate;
    if (sellRate <= 0 && buyRate > 0) sellRate = buyRate;

    final flag = _flag;
    final m = widget.market;

    final mode = _isOnline ? 6 : 5;

    setState(() {
      _buy = buy > 0 ? m.calculate(mode: mode, buysel: 1, flag: flag, qty: qty, price: buy, rate: buyRate, brkrate: brkrate) : null;
      _sell = sell > 0 ? m.calculate(mode: mode, buysel: 2, flag: flag, qty: qty, price: sell, rate: sellRate, brkrate: brkrate) : null;

      // DF A/C (Malaysia only)
      _dfBuy = null;
      if (isMalaysia && _dfAc && buy > 0) {
        final mm = m as MalaysiaMarket;
        _dfBuy = mm.dfAcCalculate(mode: mode, buysel: 1, flag: flag, qty: qty, price: buy, rate: buyRate, brkrate: brkrate, noday: _dfDays);
      }
    });
  }

  void _autoCalculate() {
    // Only auto-calculate if quantity is filled (avoid errors on empty form)
    if (_qtyCtrl.text.trim().isEmpty) return;
    if (double.tryParse(_qtyCtrl.text) == null) return;
    _calculate();
  }

  void _clear() {
    setState(() {
      _qtyCtrl.clear();
      _buyCtrl.clear();
      _sellCtrl.clear();
      _buyRateCtrl.text = '1.0';
      _sellRateCtrl.text = '1.0';
      _brkrateCtrl.text = '0';
      _dfDaysCtrl.text = '5';
      _isOnline = true;
      _flagMinRm12 = false;
      _flagNoSduty = false;
      _flagSpecial = false;
      _applyGst = false;
      _settleLocal = false;
      _dfAc = false;
      _dfDays = 5;
      _buy = null;
      _sell = null;
      _dfBuy = null;
    });
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _buyCtrl.dispose();
    _sellCtrl.dispose();
    _buyRateCtrl.dispose();
    _sellRateCtrl.dispose();
    _brkrateCtrl.dispose();
    _dfDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.market;
    final isMalaysia = m is MalaysiaMarket;
    final isForeign = m.currency != 'MYR';
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inputs ──────────────────────────────────────────
          _card(
            child: Column(
              children: [
                // Row 1: Quantity + Special Brk Rate (same row)
                Row(children: [
                  Expanded(child: _inputField(_qtyCtrl, 'Quantity', TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _brkrateCtrl,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Special Brk Rate (%)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      onChanged: (val) {
                        final rate = double.tryParse(val) ?? 0;
                        setState(() {
                          _flagSpecial = rate > 0;
                        });
                        _autoCalculate();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                // Row 2: Buy / Sell price
                Row(children: [
                  Expanded(child: _inputField(_buyCtrl, 'Buy Price (${m.currency})', TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 8),
                  Expanded(child: _inputField(_sellCtrl, 'Sell Price (${m.currency})', TextInputType.numberWithOptions(decimal: true))),
                ]),
                const SizedBox(height: 8),
                // Row 3: Buy / Sell rate (foreign only)
                if (isForeign) ...[
                  Row(children: [
                    Expanded(child: _inputField(_buyRateCtrl, 'Buy Rate (MYR/${m.currency})', TextInputType.numberWithOptions(decimal: true))),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField(_sellRateCtrl, 'Sell Rate (MYR/${m.currency})', TextInputType.numberWithOptions(decimal: true))),
                  ]),
                  const SizedBox(height: 8),
                ],
                // Row 4: Offline / Online / Buy / Sell (highlight only, no tick)
                Row(children: [
                  if (m.supportsOnline) ...[
                    Expanded(child: _fixedChip('Offline', !_isOnline, (_) => setState(() { _isOnline = false; _autoCalculate(); }))),
                    const SizedBox(width: 8),
                    Expanded(child: _fixedChip('Online', _isOnline, (_) => setState(() { _isOnline = true; _autoCalculate(); }))),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: _fixedChip('Buy', _buyCtrl.text.isNotEmpty, (_) {})),
                  const SizedBox(width: 8),
                  Expanded(child: _fixedChip('Sell', _sellCtrl.text.isNotEmpty, (_) {})),
                ]),
                const SizedBox(height: 8),
                // Row 5: MIN RM12 / No Stamp Duty / DF A/C
                Row(children: [
                  if (m.flagMinRm12) ...[
                    Expanded(child: _fixedChip('MIN RM12', _flagMinRm12, (v) => setState(() { _flagMinRm12 = v!; _autoCalculate(); }))),
                    const SizedBox(width: 8),
                  ],
                  if (m.flagNoSduty) ...[
                    Expanded(child: _fixedChip('No Stamp Duty', _flagNoSduty, (v) => setState(() { _flagNoSduty = v!; _autoCalculate(); }))),
                    const SizedBox(width: 8),
                  ],
                  if (isMalaysia) ...[
                    Expanded(child: _fixedChip('DF A/C', _dfAc, (v) => setState(() { _dfAc = v!; _autoCalculate(); }))),
                    if (_dfAc) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _dfDaysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'DF Days',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onChanged: (v) {
                            final d = int.tryParse(v);
                            if (d != null) {
                              setState(() { _dfDays = d; });
                              _autoCalculate();
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ]),
                const SizedBox(height: 8),
                // Row 6: Special Rate / Apply GST/SST / Sett in xxxx
                Row(children: [
                  Expanded(child: _fixedChip('Special Rate', _flagSpecial, (v) => setState(() { _flagSpecial = v!; _autoCalculate(); }))),
                  const SizedBox(width: 8),
                  Expanded(child: _fixedChip('Apply GST/SST', _applyGst, (v) => setState(() { _applyGst = v!; _autoCalculate(); }))),
                  if (isForeign) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _fixedChip('Sett in ${m.currency}', _settleLocal, (v) => setState(() { _settleLocal = v!; _autoCalculate(); }))),
                  ],
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _calculate,
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calculate'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _clear, child: const Text('Clear')),
                ]),
              ],
            ),
          ),

          // ── Results ─────────────────────────────────────────
          if (_hasResults) ...[
            const SizedBox(height: 12),
            _buildResults(isMalaysia, isForeign, theme),
          ],
        ],
      ),
    );
  }

  // ── Helpers matching desktop GUI ──────────────────────────

  double? _gv(CalcResult? calc, String myrKey, String forKey) {
    if (calc == null) return null;
    if (calc.has(myrKey)) return calc.get(myrKey);
    return calc.get(forKey);
  }

  double? _disp(CalcResult? calc, String myrKey, String? forKey, double rate) {
    if (calc == null) return null;
    if (_settleLocal) {
      if (forKey != null && calc.has(forKey)) return calc.get(forKey);
      return rate != 0 ? calc.get(myrKey) / rate : 0;
    }
    return calc.get(myrKey);
  }

  double? _dispSd(CalcResult? calc, double rate) {
    if (calc == null) return null;
    if (_settleLocal) {
      double wholeRm = calc.get('stampduty');
      double val = rate != 0 ? wholeRm / rate : 0;
      return (val * 100).ceilToDouble() / 100;
    }
    return calc.get('stampduty');
  }

  String _curr(String myrLabel) => _settleLocal ? widget.market.currency : myrLabel;

  String _rateStr(CalcResult? calc, [String key = 'brkamtrate']) {
    if (calc == null) return '';
    double r = calc.get(key);
    if (r == 0) return '';
    String s = r.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$s%';
  }

  Widget _buildResults(bool isMalaysia, bool isForeign, ThemeData theme) {
    final m = widget.market;
    final cur = m.currency;
    final buyRate = double.tryParse(_buyRateCtrl.text) ?? 1.0;
    final sellRate = double.tryParse(_sellRateCtrl.text) ?? 1.0;
    final hasBuy = _buyCtrl.text.trim().isNotEmpty;
    final hasSell = _sellCtrl.text.trim().isNotEmpty;
    final modeLabel = _isOnline ? 'Online' : 'Offline';

    List<_Row> rows = [];

    // Row 1: Proceeds - currency switches between MYR (unticked) and foreign (ticked)
    // Malaysia returns 'gross'; foreign markets return 'rmgross'
    final proceedsKey = isMalaysia ? 'gross' : 'rmgross';
    rows.add(_Row('Proceeds', _curr('MYR'),
      buy: _disp(_buy, proceedsKey, 'gross', buyRate),
      sell: _disp(_sell, proceedsKey, 'gross', sellRate),
    ));

    // Row 2: Brokerage (Local Brokerage for HK/SG)
    // Malaysia returns 'brkamt'; foreign markets return 'malbrkamt'
    final brkKey = isMalaysia ? 'brkamt' : 'malbrkamt';
    final brkLabel = (m.name == 'Hong Kong' || m.name == 'Singapore') ? 'Local Brokerage' : 'Brokerage';
    rows.add(_Row(brkLabel, _curr('MYR'),
      rate: _rateStr(_buy ?? _sell),
      buy: _disp(_buy, brkKey, null, buyRate),
      sell: _disp(_sell, brkKey, null, sellRate),
    ));

    // Row 3: Stamp Duty (Local Stamp Duty for HK)
    final sdLabel = m.name == 'Hong Kong' ? 'Local Stamp Duty' : 'Stamp Duty';
    rows.add(_Row(sdLabel, _curr('MYR'),
      rate: _rateStr(_buy ?? _sell, 'stampdutyrate'),
      buy: _dispSd(_buy, buyRate),
      sell: _dispSd(_sell, sellRate),
    ));

    // Row 4: Clearing Fee (Local Clearing Fee for HK)
    // Malaysia returns 'clrfee'; foreign markets return 'clrfee_rm'
    final clrKey = isMalaysia ? 'clrfee' : 'clrfee_rm';
    final clrLabel = m.name == 'Hong Kong' ? 'Local Clearing Fee' : 'Clearing Fee';
    rows.add(_Row(clrLabel, _curr('MYR'),
      rate: _rateStr(_buy ?? _sell, 'clrfeerate'),
      buy: _disp(_buy, clrKey, 'clrfee', buyRate),
      sell: _disp(_sell, clrKey, 'clrfee', sellRate),
    ));

    // Foreign Brokerage (US, HK, SG)
    if (m.name == 'United States (US)' || m.name == 'Hong Kong' || m.name == 'Singapore') {
      rows.add(_Row('Foreign Brokerage', _curr('MYR'),
        buy: _disp(_buy, 'forbrkamt_rm', 'forbrkamt', buyRate),
        sell: _disp(_sell, 'forbrkamt_rm', 'forbrkamt', sellRate),
      ));
    }

    // Foreign Stamp Duty (HK only)
    if (_anyNonZero('forstampduty')) {
      rows.add(_Row('Foreign Stamp Duty', cur,
        buy: _gv(_buy, 'forstampduty', 'forstampduty'),
        sell: _gv(_sell, 'forstampduty', 'forstampduty'),
      ));
    }

    // CCASS Fee (HK only)
    if (_anyNonZero('ccassfee')) {
      rows.add(_Row('CCASS Fee', cur,
        buy: _gv(_buy, 'ccassfee', 'ccassfee'),
        sell: _gv(_sell, 'ccassfee', 'ccassfee'),
      ));
    }

    // Trading Fee (HK & SG)
    if (_anyNonZero('trdfee')) {
      rows.add(_Row('Trading Fee', _curr('MYR'),
        buy: _disp(_buy, 'trdfee_rm', 'trdfee', buyRate),
        sell: _disp(_sell, 'trdfee_rm', 'trdfee', sellRate),
      ));
    }

    // Levy Fee (HK only)
    if (_anyNonZero('levyfee')) {
      rows.add(_Row('Levy Fee', cur,
        buy: _gv(_buy, 'levyfee', 'levyfee'),
        sell: _gv(_sell, 'levyfee', 'levyfee'),
      ));
    }

    // IB Charges (other foreign markets - not Malaysia, US, HK, SG)
    if (!isMalaysia && m.name != 'United States (US)' && m.name != 'Hong Kong' && m.name != 'Singapore') {
      rows.add(_Row('IB Charges', _curr('MYR'),
        buy: _disp(_buy, 'ibrmcharges', 'ibcharges', buyRate),
        sell: _disp(_sell, 'ibrmcharges', 'ibcharges', sellRate),
      ));
    }

    // SST/GST - Brokerage
    final gstLabel = isMalaysia ? 'SST - Brokerage' : 'GST - Brokerage';
    rows.add(_Row(gstLabel, _curr('MYR'),
      buy: _disp(_buy, 'gstbrkamt', 'gstbrkamtcv', buyRate),
      sell: _disp(_sell, 'gstbrkamt', 'gstbrkamtcv', sellRate),
    ));

    // SST/GST - Clearing Fee (always shown)
    final gstClrLabel = isMalaysia ? 'SST - Clearing Fee' : 'GST - Clearing Fee';
    rows.add(_Row(gstClrLabel, _curr('MYR'),
      buy: _disp(_buy, 'gstclrfee', null, buyRate),
      sell: _disp(_sell, 'gstclrfee', null, sellRate),
    ));

    // GST - Foreign Brokerage (US/HK/SG) / GST - IB Charges (other foreign)
    if (!isMalaysia) {
      final gstIbLabel = (m.name == 'United States (US)' || m.name == 'Hong Kong' || m.name == 'Singapore')
          ? 'GST - Foreign Brokerage' : 'GST - IB Charges';
      rows.add(_Row(gstIbLabel, _curr('MYR'),
        buy: _disp(_buy, 'gstforfee', 'gstforfeecv', buyRate),
        sell: _disp(_sell, 'gstforfee', 'gstforfeecv', sellRate),
      ));
    }

    // DF A/C rows (Malaysia only)
    if (_dfBuy != null) {
      rows.add(_Row('DF Interest', 'MYR',
        buy: _dfBuy?['dfint'],
      ));
      rows.add(_Row('DF Fees', 'MYR',
        buy: _dfBuy?['dffee'],
      ));
      rows.add(_Row('GST - DF Fees', 'MYR',
        buy: _dfBuy?['dfgstfee'],
      ));
    }

    // TOTAL row
    final totalCurr = _settleLocal ? cur : 'MYR';
    double? buyTotal, sellTotal;
    if (_settleLocal) {
      buyTotal = _gv(_buy, 'val2', 'val2');
      sellTotal = _gv(_sell, 'val2', 'val2');
    } else {
      buyTotal = _dfBuy?['total'] ?? _gv(_buy, 'val1', 'net_value');
      sellTotal = _gv(_sell, 'val1', 'net_value');
    }
    rows.add(_Row('TOTAL', totalCurr,
      buy: buyTotal, sell: sellTotal,
      isTotal: true,
    ));

    // Contra P&L row (only when both buy and sell present)
    if (hasBuy && hasSell) {
      double? contra;
      if (_settleLocal) {
        contra = (_gv(_sell, 'val2', 'val2') ?? 0) - (_gv(_buy, 'val2', 'val2') ?? 0);
      } else {
        contra = (_gv(_sell, 'val1', 'net_value') ?? 0) - (_dfBuy?['total'] ?? _gv(_buy, 'val1', 'net_value') ?? 0);
      }
      rows.add(_Row('Contra P&L', totalCurr,
        buy: contra,
        isContra: true,
      ));
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Results ($modeLabel)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Header row
          _buildHeader(theme),
          const Divider(height: 1),
          ...rows.map((row) => _ResultRow(row: row)),
        ],
      ),
    );
  }

  bool _anyNonZero(String key) {
    for (final c in [_buy, _sell]) {
      if (c != null && c.get(key) != 0) return true;
    }
    return false;
  }

  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final buyColor = isDark ? const Color(0xFF4ade80) : const Color(0xFF166534);
    final sellColor = isDark ? const Color(0xFFf87171) : const Color(0xFF991b1b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Expanded(flex: 3, child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
          const Expanded(flex: 1, child: Text('Curr', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('BUY', style: TextStyle(fontWeight: FontWeight.bold, color: buyColor), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('SELL', style: TextStyle(fontWeight: FontWeight.bold, color: sellColor), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Card(
    elevation: 2,
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );

  Widget _inputField(TextEditingController ctrl, String label, TextInputType type) => TextField(
    controller: ctrl,
    keyboardType: type,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
  );

  /// Flexible toggle chip. Uses FilterChip with no checkmark so the chip
  /// only highlights when selected (no size jump / no tick). Callers should
  /// wrap this in an [Expanded] so chips share the row width evenly and never
  /// overflow on narrow screens.
  Widget _fixedChip(String label, bool value, ValueChanged<bool?> onChanged) {
    return FilterChip(
      label: Text(label, textAlign: TextAlign.center),
      selected: value,
      showCheckmark: false,
      labelPadding: EdgeInsets.zero,
      onSelected: (v) => onChanged(v),
    );
  }
}

class _Row {
  final String label;
  final String curr;
  final double? buy;
  final double? sell;
  final String rate;
  final bool isTotal;
  final bool isContra;
  _Row(this.label, this.curr, {
    this.buy, this.sell,
    this.rate = '',
    this.isTotal = false, this.isContra = false,
  });
}

class _ResultRow extends StatelessWidget {
  final _Row row;
  const _ResultRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buyColor = isDark ? const Color(0xFF4ade80) : const Color(0xFF166534);
    final sellColor = isDark ? const Color(0xFFf87171) : const Color(0xFF991b1b);
    final totalColor = isDark ? const Color(0xFF93c5fd) : const Color(0xFF1a56db);

    String withCurr(double? v) => v == null ? '' : '${row.curr} ${_numFmt.format(v)}';

    Color? cellColor(double? v, bool isBuy) {
      if (v == null) return null;
      if (row.isContra) return v >= 0 ? buyColor : sellColor;
      if (row.isTotal) return totalColor;
      return isBuy ? buyColor : sellColor;
    }

    TextStyle? cellStyle(double? v, bool isBuy) {
      if (v == null) return theme.textTheme.bodySmall;
      if (row.isTotal || row.isContra) {
        return theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: cellColor(v, isBuy));
      }
      return theme.textTheme.bodySmall?.copyWith(color: cellColor(v, isBuy));
    }

    return Container(
      decoration: row.isTotal
          ? BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(row.label,
                style: row.isTotal || row.isContra
                    ? theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)
                    : theme.textTheme.bodySmall),
          ),
          Expanded(flex: 1, child: Text(row.curr, style: theme.textTheme.bodySmall)),
          Expanded(flex: 2, child: Text(row.rate, style: theme.textTheme.bodySmall, textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text(withCurr(row.buy), style: cellStyle(row.buy, true), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text(withCurr(row.sell), style: cellStyle(row.sell, false), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}