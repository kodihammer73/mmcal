import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/engine.dart';
import '../main.dart';
import '../markets/malaysia.dart';
import '../services/form_state.dart';
import '../ui/branding.dart';

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

  // Scroll-to-results support.
  final _scrollController = ScrollController();
  final _resultsKey = GlobalKey();

  // Debounced persistence so we don't hammer SharedPreferences on every key.
  Timer? _persistTimer;

  // Incremented on every calculate to re-key the results animation.
  int _formSeq = 0;

  bool _isOnline = true; // Default to online
  int _flagMinRm = 0; // Malaysia min-brokerage tier: 0=off, 12=Min RM12, 8=Min RM8
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
    if (_flagMinRm > 0) f |= 1;
    if (_flagSpecial) f |= 2;
    if (_flagNoSduty) f |= 4;
    if (_settleLocal) f |= 8;
    if (!_applyGst) f |= 16; // bit4: GST/SST NOT applied (matches desktop)
    return f;
  }

  bool get _hasResults => _buy != null || _sell != null;

  /// Live validation error for the current input, or null when the form is
  /// valid and ready to calculate.
  String? get _error {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return 'Enter a quantity greater than 0.';
    final buy = double.tryParse(_buyCtrl.text) ?? 0;
    final sell = double.tryParse(_sellCtrl.text) ?? 0;
    if (buy <= 0 && sell <= 0) return 'Enter a Buy and/or Sell price.';
    if (widget.market is! MalaysiaMarket) {
      final buyRate = double.tryParse(_buyRateCtrl.text) ?? 0;
      final sellRate = double.tryParse(_sellRateCtrl.text) ?? 0;
      if (buyRate <= 0 && sellRate <= 0) {
        return 'Enter a Buy and/or Sell exchange rate.';
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    final saved = await FormStateStore.load(widget.market.name);
    if (!mounted) return;
    setState(() {
      _qtyCtrl.text = saved['qty'] as String? ?? '';
      _buyCtrl.text = saved['buy'] as String? ?? '';
      _sellCtrl.text = saved['sell'] as String? ?? '';
      _buyRateCtrl.text = saved['buyRate'] as String? ?? '1.0';
      _sellRateCtrl.text = saved['sellRate'] as String? ?? '1.0';
      _brkrateCtrl.text = saved['brkrate'] as String? ?? '0';
      _dfDaysCtrl.text = saved['dfDays'] as String? ?? '5';
      _flagMinRm = (saved['flagMinRm'] as num?)?.toInt() ?? 0;
      final onlineFlag = (saved['isOnline'] as num?)?.toInt();
      if (onlineFlag != null) _isOnline = onlineFlag == 1;
      _flagNoSduty = (saved['flagNoSduty'] as num?)?.toInt() == 1;
      _flagSpecial = (saved['flagSpecial'] as num?)?.toInt() == 1;
      _applyGst = (saved['applyGst'] as num?)?.toInt() == 1;
      _settleLocal = (saved['settleLocal'] as num?)?.toInt() == 1;
      _dfAc = (saved['dfAc'] as num?)?.toInt() == 1;
      _dfDays = int.tryParse(_dfDaysCtrl.text) ?? 5;
    });
  }

  /// Collects the current form into a storable map. Text fields are stored as
  /// raw strings so the exact input round-trips; toggles are 1/0 ints.
  Map<String, Object> _collectState() => {
        'qty': _qtyCtrl.text,
        'buy': _buyCtrl.text,
        'sell': _sellCtrl.text,
        'buyRate': _buyRateCtrl.text,
        'sellRate': _sellRateCtrl.text,
        'brkrate': _brkrateCtrl.text,
        'dfDays': _dfDaysCtrl.text,
        'isOnline': _isOnline ? 1 : 0,
        'flagMinRm': _flagMinRm,
        'flagNoSduty': _flagNoSduty ? 1 : 0,
        'flagSpecial': _flagSpecial ? 1 : 0,
        'applyGst': _applyGst ? 1 : 0,
        'settleLocal': _settleLocal ? 1 : 0,
        'dfAc': _dfAc ? 1 : 0,
      };

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), _persistNow);
  }

  Future<void> _persistNow() async {
    await FormStateStore.save(widget.market.name, _collectState());
  }

  /// Scrolls the results card into view (post-frame so it exists after the
  /// rebuild triggered by [setState]).
  void _scrollToResults() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.05);
      }
    });
  }

  void _calculate() {
    // Dismiss the keyboard when Calculate or any quick button is pressed.
    FocusManager.instance.primaryFocus?.unfocus();
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

    // Inline validation: stop silently when the form is incomplete.
    if (_error != null) return;

    // Fill missing rates
    if (buyRate <= 0 && sellRate > 0) buyRate = sellRate;
    if (sellRate <= 0 && buyRate > 0) sellRate = buyRate;

    final flag = _flag;
    final m = widget.market;

    // Malaysia min-brokerage tier override (RM12 default or RM8 when selected)
    double? minBrkOverride;
    if (isMalaysia && _flagMinRm > 0) {
      minBrkOverride = m.s.get(_flagMinRm == 8 ? 'malminbrk8' : 'malminbrk');
    }

    final mode = _isOnline ? 6 : 5;

    setState(() {
      _buy = buy > 0 ? m.calculate(mode: mode, buysel: 1, flag: flag, qty: qty, price: buy, rate: buyRate, brkrate: brkrate, minBrkOverride: minBrkOverride) : null;
      _sell = sell > 0 ? m.calculate(mode: mode, buysel: 2, flag: flag, qty: qty, price: sell, rate: sellRate, brkrate: brkrate, minBrkOverride: minBrkOverride) : null;

      // DF A/C (Malaysia only)
      _dfBuy = null;
      if (isMalaysia && _dfAc && buy > 0) {
        final mm = m as MalaysiaMarket;
        _dfBuy = mm.dfAcCalculate(mode: mode, buysel: 1, flag: flag, qty: qty, price: buy, rate: buyRate, brkrate: brkrate, noday: _dfDays, minBrkOverride: minBrkOverride);
      }
      _formSeq++;
    });
    _schedulePersist();
    _scrollToResults();
  }

  void _autoCalculate() {
    // Only auto-calculate if quantity is filled (avoid errors on empty form)
    if (_qtyCtrl.text.trim().isEmpty) return;
    if (double.tryParse(_qtyCtrl.text) == null) return;
    _calculate();
  }

  void _clear() {
    // Dismiss the keyboard when Clear is pressed.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {

      _qtyCtrl.clear();
      _buyCtrl.clear();
      _sellCtrl.clear();
      _buyRateCtrl.text = '1.0';
      _sellRateCtrl.text = '1.0';
      _brkrateCtrl.text = '0';
      _dfDaysCtrl.text = '5';
      _isOnline = true;
      _flagMinRm = 0;
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
    _persistTimer?.cancel();
    FormStateStore.clear(widget.market.name);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _scrollController.dispose();
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

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header: Trade Details ───────────────────
          _sectionHeader(Icons.tune, 'Trade Details'),
          const SizedBox(height: 8),
          _card(
            child: Column(
              children: [
                // Row 1: Quantity + Special Brk Rate (same row)
                Row(children: [
                  Expanded(child: _inputField(_qtyCtrl, 'Quantity', TextInputType.number, prefix: const Icon(Icons.tag, size: 18),
                      onChanged: (_) => setState(() {}), errorText: (double.tryParse(_qtyCtrl.text) ?? 0) <= 0 ? 'Quantity must be > 0' : null)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _brkrateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Special Brk Rate (%)',
                        prefixIcon: Icon(Icons.percent, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) {
                        final rate = double.tryParse(val) ?? 0;
                        setState(() {
                          _flagSpecial = rate > 0;
                        });
                        _autoCalculate();
                        _schedulePersist();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // Quick quantity fill
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [100, 500, 1000, 5000].map((v) {
                    return ActionChip(
                      label: Text(v.toString(), style: Theme.of(context).textTheme.bodySmall),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () {
                        setState(() => _qtyCtrl.text = v.toString());
                        _autoCalculate();
                        _schedulePersist();
                      },
                    );
                  }).toList(),
                ),
                // Row 2: Buy / Sell price
                Row(children: [
                  Expanded(child: _inputField(_buyCtrl, 'Buy Price (${m.currency})', const TextInputType.numberWithOptions(decimal: true), prefix: const Icon(Icons.shopping_cart, size: 18), onChanged: (_) { setState(() {}); _schedulePersist(); })),
                  const SizedBox(width: 8),
                  Expanded(child: _inputField(_sellCtrl, 'Sell Price (${m.currency})', const TextInputType.numberWithOptions(decimal: true), prefix: const Icon(Icons.sell, size: 18), onChanged: (_) { setState(() {}); _schedulePersist(); })),
                ]),
                const SizedBox(height: 8),
                // Row 3: Buy / Sell rate (foreign only)
                if (isForeign) ...[
                  Row(children: [
                    Expanded(child: _inputField(_buyRateCtrl, 'Buy Rate (MYR/${m.currency})', const TextInputType.numberWithOptions(decimal: true), prefix: const Icon(Icons.currency_exchange, size: 18), onChanged: (_) { setState(() {}); _schedulePersist(); })),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField(_sellRateCtrl, 'Sell Rate (MYR/${m.currency})', const TextInputType.numberWithOptions(decimal: true), prefix: const Icon(Icons.currency_exchange, size: 18), onChanged: (_) { setState(() {}); _schedulePersist(); })),
                  ]),
                  const SizedBox(height: 8),
                ],

                const Divider(height: 16),
                Row(
                  children: [
                    Icon(Icons.checklist, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Options', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),                // Row 4: Offline / Online / Buy / Sell (highlight only, no tick)
                Row(children: [
                  if (m.supportsOnline) ...[
                    Expanded(child: _fixedChip('Offline', !_isOnline, (_) => setState(() { _isOnline = false; _autoCalculate(); }))),
                    const SizedBox(width: 6),
                    Expanded(child: _fixedChip('Online', _isOnline, (_) => setState(() { _isOnline = true; _autoCalculate(); }))),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: _fixedChip('Buy', _buyCtrl.text.isNotEmpty, (_) {})),
                  const SizedBox(width: 6),
                  Expanded(child: _fixedChip('Sell', _sellCtrl.text.isNotEmpty, (_) {})),
                ]),
                const SizedBox(height: 8),
                // Row 5: Options chips (Wrap so they flow into fewer lines)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (m.flagMinRm12) ...[
                      _fixedChip('MIN RM12', _flagMinRm == 12, (v) => setState(() { _flagMinRm = v! ? 12 : 0; _autoCalculate(); })),
                      _fixedChip('MIN RM8', _flagMinRm == 8, (v) => setState(() { _flagMinRm = v! ? 8 : 0; _autoCalculate(); })),
                    ],
                    if (m.flagNoSduty)
                      _fixedChip('NO S/D', _flagNoSduty, (v) => setState(() { _flagNoSduty = v!; _autoCalculate(); })),
                    if (isMalaysia)
                      _fixedChip('DF A/C', _dfAc, (v) => setState(() { _dfAc = v!; _autoCalculate(); })),
                    _fixedChip('Special Rate', _flagSpecial, (v) => setState(() { _flagSpecial = v!; _autoCalculate(); })),
                    _fixedChip('Apply GST/SST', _applyGst, (v) => setState(() { _applyGst = v!; _autoCalculate(); })),
                    if (isForeign)
                      _fixedChip('Sett in ${m.currency}', _settleLocal, (v) => setState(() { _settleLocal = v!; _autoCalculate(); })),
                  ],
                ),
                // DF Days field (Malaysia only, shown when DF A/C ticked)
                if (isMalaysia && _dfAc) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _dfDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'DF Days',
                        prefixIcon: Icon(Icons.calendar_today, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      // Disabled (greyed out) while the form is incomplete,
                      // instead of silently doing nothing on tap.
                      onPressed: _error == null ? _calculate : null,
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calculate'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Clear'),
                  ),
                ]),
              ],
            ),
          ),

          // ── Inline validation message (instead of silent no-op) ──
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error == null && !_hasResults) ...[
            const SizedBox(height: 12),
            _buildEmptyState(),
          ],          // ── Results ─────────────────────────────────────────
          if (_hasResults) ...[
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _resultsKey,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('results-$_formSeq'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResults(isMalaysia, isForeign),
                    const SizedBox(height: 8),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers matching desktop GUI ──────────────────────────

  Widget _sectionHeader(IconData icon, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

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

  Widget _buildResults(bool isMalaysia, bool isForeign) {
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

    // SST/GST rows are only shown when the "Apply GST/SST" toggle is ON.
    if (_applyGst) {
      // SST/GST - Brokerage
      final gstLabel = isMalaysia ? 'SST - Brokerage' : 'GST - Brokerage';
      rows.add(_Row(gstLabel, _curr('MYR'),
        buy: _disp(_buy, 'gstbrkamt', 'gstbrkamtcv', buyRate),
        sell: _disp(_sell, 'gstbrkamt', 'gstbrkamtcv', sellRate),
      ));

      // SST/GST - Clearing Fee
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
    }


    // DF A/C rows (Malaysia only)
    if (_dfBuy != null) {
      rows.add(_Row('DF Interest', 'MYR',
        buy: _dfBuy?['dfint'],
      ));
      rows.add(_Row('DF Fees', 'MYR',
        buy: _dfBuy?['dffee'],
      ));
      if (_applyGst) {
        rows.add(_Row('GST - DF Fees', 'MYR',
          buy: _dfBuy?['dfgstfee'],
        ));
      }

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
          Row(
            children: [
              Icon(Icons.receipt_long, size: 18, color: marketAccent(m.name)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Results ($modeLabel)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy summary',
                onPressed: () => _copySummary(rows),
                icon: const Icon(Icons.copy),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Share summary',
                onPressed: () => _shareSummary(rows),
                icon: const Icon(Icons.share),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Header row
          _buildHeader(),
          const Divider(height: 1),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            leading: const Icon(Icons.unfold_more, size: 18),
            title: Text('All charges',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            initiallyExpanded: true,
            children: rows.takeWhile((r) => !r.isTotal).toList().asMap().entries
                .map((e) => _ResultRow(row: e.value, index: e.key))
                .toList(),
          ),
          ...rows.skipWhile((r) => !r.isTotal).toList().asMap().entries
              .map((e) => _ResultRow(row: e.value, index: e.key)),
        ],
      ),
    );
  }

  /// Renders the results as a compact, aligned plain-text summary for
  /// copy/share. Header line mirrors the on-screen table columns.
  /// Renders the results as a compact, aligned plain-text summary for
  /// copy/share. Header line mirrors the on-screen table columns.
  /// Builds a shareable/copyable plain-text summary.
  ///
  /// Adaptive columns: only the columns the user actually entered are shown
  /// (BUY only, SELL only, or both), so every row stays on one line and fits
  /// within a phone chat width (~33 chars max) without wrapping.
  String _buildSummaryText(List<_Row> rows) {
    final market = widget.market;
    final hasBuy = rows.any((r) => r.buy != null);
    final hasSell = rows.any((r) => r.sell != null);
    final b = StringBuffer();
    b.writeln('${marketFlag(market.name)} ${market.name} - '
        '${_isOnline ? 'Online' : 'Offline'}');
    final qty = _qtyCtrl.text;
    final buyTxt = _buyCtrl.text.isNotEmpty ? _buyCtrl.text : '-';
    final sellTxt = _sellCtrl.text.isNotEmpty ? _sellCtrl.text : '-';
    if (hasBuy && hasSell) {
      b.writeln('Qty $qty - $buyTxt/$sellTxt ${market.currency}');
    } else if (hasBuy) {
      b.writeln('Qty $qty - $buyTxt ${market.currency}');
    } else {
      b.writeln('Qty $qty - $sellTxt ${market.currency}');
    }
    b.writeln();
    final head = 'Item'.padRight(15) +
        (hasBuy ? 'BUY'.padLeft(8) : '') +
        (hasSell ? 'SELL'.padLeft(8) : '');
    b.writeln(head);
    b.writeln('-' * head.length);
    for (final r in rows) {
      final label = r.label.length > 16 ? '..' : r.label;
      final line = label.padRight(15) +
          (hasBuy ? formatCell(r.buy).padLeft(8) : '') +
          (hasSell ? formatCell(r.sell).padLeft(8) : '');
      b.writeln(line);
    }
    b.writeln('-' * head.length);
    b.writeln('Estimates only - actual charges may vary.');
    return b.toString();
  }
  static String formatCell(double? v) =>
      v == null ? '' : _numFmt.format(v);
  Future<void> _copySummary(List<_Row> rows) async {
    await Clipboard.setData(ClipboardData(text: _buildSummaryText(rows)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _shareSummary(List<_Row> rows) async {
    try {
      await SharePlus.instance.share(ShareParams(text: _buildSummaryText(rows)));
    } catch (_) {
      // Some platforms (e.g. non-interactive test env) lack a share sheet.
      // Fall back to copying so the data is still available.
      await Clipboard.setData(ClipboardData(text: _buildSummaryText(rows)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary copied to clipboard'), duration: Duration(seconds: 2)),
      );
    }
  }

  bool _anyNonZero(String key) {
    for (final c in [_buy, _sell]) {
      if (c != null && c.get(key) != 0) return true;
    }
    return false;
  }


  /// Friendly hint shown before any calculation has been run.
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.calculate_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Enter a trade, then press Calculate', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('Buy/sell price and fees will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Footer + disclaimer. Only rendered once results are shown.
  Widget _buildFooter() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${DateTime.now().year} - Developed by Hemerjit',
                  style: TextStyle(
                      color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Calculations are estimates for informational purposes only. Actual charges may vary depending on the broker, exchange, transaction type and applicable fees.',
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buyColor = isDark ? AppColors.buyDark : AppColors.buyLight;
    final sellColor = isDark ? AppColors.sellDark : AppColors.sellLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(flex: 3, child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
          const Expanded(flex: 1, child: Text('Curr', style: TextStyle(fontWeight: FontWeight.bold))),
          const Expanded(flex: 2, child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('BUY', style: TextStyle(fontWeight: FontWeight.bold, color: buyColor), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('SELL', style: TextStyle(fontWeight: FontWeight.bold, color: sellColor), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );

  Widget _inputField(TextEditingController ctrl, String label, TextInputType type, {Widget? prefix, ValueChanged<String>? onChanged, String? errorText}) => TextField(
    controller: ctrl,
    keyboardType: type,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: prefix,
      errorText: errorText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );

  /// Flexible toggle chip. Uses FilterChip with no checkmark so the chip
  /// only highlights when selected (no size jump / no tick).
  Widget _fixedChip(String label, bool value, ValueChanged<bool?> onChanged) {
    return FilterChip(
      label: Text(label, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall),
      selected: value,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
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
  final int index;
  const _ResultRow({required this.row, required this.index});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buyColor = isDark ? AppColors.buyDark : AppColors.buyLight;
    final sellColor = isDark ? AppColors.sellDark : AppColors.sellLight;
    final totalColor = isDark ? AppColors.totalDark : AppColors.totalLight;

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

    // Alternating row striping for readability
    final stripe = !row.isTotal && index.isOdd
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
        : null;

    return Container(
      decoration: row.isTotal
          ? BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            )
          : stripe != null
              ? BoxDecoration(color: stripe, borderRadius: BorderRadius.circular(6))
              : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
