import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/portfolio_store.dart';
import '../services/symbol_lookup.dart';
import '../ui/branding.dart';
import '../ui/stock_identifier_field.dart';

/// What the user chose in the add/edit sheet.
class PortfolioEntryOutcome {
  /// The transaction to save (new or edited), when they tapped Save.
  final PortfolioTxn? saved;

  /// The id to delete, when they tapped Delete.
  final String? deletedId;

  const PortfolioEntryOutcome.save(this.saved) : deletedId = null;
  const PortfolioEntryOutcome.delete(this.deletedId) : saved = null;
}

final _money = NumberFormat('#,##0.00');

/// Opens the add / edit sheet. Qty, price and side are read-only - they come
/// from the result screen - while the stock (a single code-or-name box), the
/// date and the total are editable.
Future<PortfolioEntryOutcome?> showPortfolioEntrySheet(
  BuildContext context, {
  required String market,
  required String currency,
  required String side,
  required double qty,
  required double price,
  required double total,
  PortfolioTxn? existing,
  List<PortfolioTxn> allTxns = const [],
  bool allowDelete = false,
  SymbolLookup? lookup,
}) {
  return showModalBottomSheet<PortfolioEntryOutcome>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PortfolioEntrySheet(
      market: market,
      currency: currency,
      side: side,
      qty: qty,
      price: price,
      total: total,
      existing: existing,
      allTxns: allTxns,
      allowDelete: allowDelete,
      lookup: lookup,
    ),
  );
}

class _PortfolioEntrySheet extends StatefulWidget {
  final String market;
  final String currency;
  final String side;
  final double qty;
  final double price;
  final double total;
  final PortfolioTxn? existing;
  final List<PortfolioTxn> allTxns;
  final bool allowDelete;
  final SymbolLookup? lookup;

  const _PortfolioEntrySheet({
    required this.market,
    required this.currency,
    required this.side,
    required this.qty,
    required this.price,
    required this.total,
    this.existing,
    required this.allTxns,
    required this.allowDelete,
    this.lookup,
  });

  @override
  State<_PortfolioEntrySheet> createState() => _PortfolioEntrySheetState();
}

class _PortfolioEntrySheetState extends State<_PortfolioEntrySheet> {
  late final TextEditingController _total;
  late DateTime _date;
  String? _error;

  /// What the single identifier box resolved to: the dictionary's code and
  /// short name when it knows the stock, otherwise exactly what was typed.
  String _code = '';
  String _name = '';

  /// Used only for [SymbolAliases] when a sell is matched to a holding. The
  /// identifier field owns the suggestion list.
  SymbolLookup? _lookup;

  bool get _isSell => widget.side == 'sell';
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // Seed from the record being edited; the identifier field re-resolves on
    // its first frame, so a dictionary match always wins.
    _code = (e?.code ?? '').trim();
    _name = (e?.name ?? '').trim();
    _total = TextEditingController(
        text: (e?.total ?? widget.total).toStringAsFixed(2));
    _date = _tryParseDate(e?.date) ?? DateTime.now();
    _total.addListener(_validate);
    _lookup = widget.lookup;
    SymbolLookup.current.addListener(_onLookupChanged);
    if (widget.lookup == null) {
      SymbolLookup.instance().then((loaded) {
        if (!mounted) return;
        setState(() => _lookup = loaded);
        _validate();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
  }

  void _onLookupChanged() {
    if (!mounted || widget.lookup != null) return;
    final latest = SymbolLookup.current.value;
    if (identical(latest, _lookup)) return;
    setState(() => _lookup = latest);
    _validate();
  }

  @override
  void dispose() {
    SymbolLookup.current.removeListener(_onLookupChanged);
    _total.dispose();
    super.dispose();
  }

  /// The identifier box resolved a code and a short name.
  void _onIdentifierResolved(String code, String name) {
    if (code == _code && name == _name) return;
    setState(() {
      _code = code;
      _name = name;
    });
    _validate();
  }

  static DateTime? _tryParseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  String get _isoDate {
    final m = _date.month.toString().padLeft(2, '0');
    final d = _date.day.toString().padLeft(2, '0');
    return '${_date.year}-$m-$d';
  }

  double? get _parsedTotal =>
      double.tryParse(_total.text.replaceAll(',', '').trim());

  /// Enforces: a stock (code or name), total > 0, and - for a sell - that a
  /// purchase record exists and the qty does not exceed the holding.
  void _validate() {
    final code = _code.trim();
    final name = _name.trim();
    final total = _parsedTotal;
    String? err;

    if (code.isEmpty && name.isEmpty) {
      err = 'Enter a stock code or name';
    } else if (total == null || total <= 0) {
      err = 'Enter a total greater than zero';
    } else if (_isSell) {
      final positions = PortfolioStore.aggregate(widget.allTxns,
          excludeId: widget.existing?.id, aliases: _lookup?.aliases);
      final pos = PortfolioStore.findPosition(
        positions,
        market: widget.market,
        currency: widget.currency,
        code: code,
        name: name,
        aliases: _lookup?.aliases,
      );
      if (pos == null) {
        err = 'No purchase record for ${code.isNotEmpty ? code : name}';
      } else if (widget.qty > pos.qty + 1e-9) {
        err = 'Quantity exceeds holding (${_plain(pos.qty)})';
      }
    }

    if (err != _error && mounted) setState(() => _error = err);
  }

  static String _plain(double v) {
    final s = v.toStringAsFixed(4);
    if (s.endsWith('.0000')) return s.substring(0, s.length - 5);
    var t = s;
    while (t.contains('.') && t.endsWith('0')) {
      t = t.substring(0, t.length - 1);
    }
    return t.endsWith('.') ? t.substring(0, t.length - 1) : t;
  }

  void _save() {
    if (_error != null) return;
    final txn = PortfolioTxn(
      id: widget.existing?.id ?? PortfolioStore.newId(),
      market: widget.market,
      currency: widget.currency,
      code: _code.trim(),
      name: _name.trim(),
      date: _isoDate,
      side: widget.side,
      qty: widget.qty,
      total: _parsedTotal!,
      note: widget.existing?.note ?? '',
    ).canonical();
    Navigator.of(context).pop(PortfolioEntryOutcome.save(txn));
  }

  void _delete() {
    final id = widget.existing?.id;
    if (id == null) return;
    Navigator.of(context).pop(PortfolioEntryOutcome.delete(id));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      lastDate: DateTime(2100),
      firstDate: DateTime(1990),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final sideLabel = _isSell ? 'SELL' : 'BUY';
    final sideColor =
        _isSell ? theme.colorScheme.error : theme.colorScheme.primary;
    final total = _parsedTotal;
    final unit =
        (total != null && widget.qty > 0) ? total / widget.qty : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.business_center, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isEdit ? 'Edit Transaction' : 'Add to Portfolio',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ]),
            Text(
              '${marketFlag(widget.market)} ${widget.market} - ${widget.currency}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: sideColor),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  sideLabel,
                  style: TextStyle(
                      color: sideColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'from result',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
            const SizedBox(height: 12),
            // One box: type a code or a name and pick a match to store the
            // dictionary's code and short name.
            StockIdentifierField(
              market: widget.market,
              initialCode: widget.existing?.code ?? '',
              initialName: widget.existing?.name ?? '',
              lookup: widget.lookup,
              onResolved: _onIdentifierResolved,
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  prefixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(DateFormat('dd MMM yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _readOnly('Qty', _plain(widget.qty))),
              const SizedBox(width: 10),
              Expanded(
                child: _readOnly('Buy Price', _money.format(widget.price)),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _total,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Total (${widget.currency})',
                prefixIcon: const Icon(Icons.payments, size: 18),
                helperText:
                    unit == null ? null : 'Price/unit ${_money.format(unit)}',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.error_outline,
                    size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            Row(children: [
              if (widget.allowDelete)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _error == null ? _save : null,
                child: Text(_isEdit ? 'Save changes' : 'Save'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// A non-editable value that still matches the TextField look.
  Widget _readOnly(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, filled: true),
      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}