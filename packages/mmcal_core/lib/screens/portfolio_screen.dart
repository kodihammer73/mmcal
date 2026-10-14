import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/settings.dart';
import '../engine/engine.dart';
import '../mmcal_app.dart';
import '../markets/market_registry.dart';
import '../services/portfolio_codec.dart';
import '../services/portfolio_store.dart';
import '../services/portfolio_transfer.dart';
import '../services/quote_service.dart';
import '../services/symbol_lookup.dart';
import '../ui/branding.dart';
import '../ui/sparkline.dart';
import '../ui/stock_identifier_field.dart';
import 'add_portfolio_sheet.dart';

final _money = NumberFormat('#,##0.00');
final _dayFmt = DateFormat('dd MMM yy');

/// Holdings grouped by market, then by settlement currency. Everything shown
/// is derived from the transaction ledger, so edits always stay consistent.
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List<PortfolioTxn> _txns = [];
  bool _loading = true;

  /// Symbol dictionary, used only to bridge code-only and name-only entries
  /// when grouping. Null until loaded; grouping then falls back to raw
  /// code/name comparison.
  SymbolLookup? _lookup;

  /// Quote fetcher built once the dictionary is available (it needs the
  /// per-market exchange suffixes).
  QuoteService? _quoteService;

  /// Fetched last-done prices, keyed by [PortfolioPosition.quoteKey]. Empty
  /// until a price is fetched; a missing entry just means "no price shown".
  final Map<String, Quote> _quotes = {};

  /// Positions whose price was fetched this session, so the on-load pass
  /// (and any re-pass after a ledger edit) only requests the missing ones.
  final Set<String> _fetchedKeys = {};

  /// Guards against two automatic passes running at once.
  bool _pricePassRunning = false;

  /// Sell what-if percentage per position (quoteKey -> selected pct).
  final Map<String, int> _whatIfPct = {};

  /// 30-day closes per position (quoteKey), fetched lazily on expand.
  final Map<String, List<double>> _history = {};

  /// Positions whose history was already requested this session.
  final Set<String> _histFetched = {};

  /// Portfolio filter text and sort key ('market' | 'value' | 'pl').
  final TextEditingController _filterCtrl = TextEditingController();
  String _sort = 'market';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final all = await PortfolioStore.load();
    if (!mounted) return;
    setState(() {
      _txns = all;
      _loading = false;
    });
    // Loaded after the list is on screen: the dictionary can come from the
    // network, and the ledger must never wait on it.
    final lookup = await SymbolLookup.instance();
    if (!mounted) return;
    setState(() {
      _lookup = lookup;
      _quoteService ??= QuoteService.shared(lookup);
    });
    // Automatic pass - skips lines already fetched this session, so after an
    // edit/import only the new or previously-failed lines are requested.
    _refreshPrices();
  }

  /// Fetches a price for [p] when its row is expanded - a lazy top-up so an
  /// expanded line never waits behind the sequential on-load pass.
  Future<void> _fetchQuoteFor(PortfolioPosition p) async {
    final service = _quoteService;
    if (service == null ||
        _quotes.containsKey(p.quoteKey) ||
        _fetchedKeys.contains(p.quoteKey)) {
      return;
    }
    final q = await service.fetch(p.market, p.code, name: p.name);
    if (q == null || !mounted) return;
    setState(() {
      _quotes[p.quoteKey] = q;
      _fetchedKeys.add(p.quoteKey);
    });
  }

  /// Fetches prices for every line, sequentially so Yahoo is not hammered.
  /// Called automatically after the ledger loads, and from "Refresh prices"
  /// with [force] to bypass the already-fetched skip and the session cache.
  Future<void> _refreshPrices({bool force = false}) async {
    if (_pricePassRunning) return;
    _pricePassRunning = true;
    try {
      if (_quoteService == null) {
        // The dictionary may still be loading; try once more.
        final lookup = await SymbolLookup.instance();
        if (!mounted) return;
        _lookup = lookup;
        _quoteService = QuoteService.shared(lookup);
      }
      final service = _quoteService!;
      if (force) {
        service.clearCache();
        _fetchedKeys.clear();
      }
      for (final p in _txnsByPosition()) {
        if (!force && _fetchedKeys.contains(p.quoteKey)) continue;
        final q = await service.fetch(p.market, p.code, name: p.name);
        if (q != null && mounted) {
          setState(() => _quotes[p.quoteKey] = q);
        }
        // Marked fetched either way so a pass never retries a dead code on
        // every rebuild; "Refresh prices" (force) clears this and retries.
        if (mounted) _fetchedKeys.add(p.quoteKey);
      }
    } finally {
      _pricePassRunning = false;
    }
    // Only the manual action reports back; the automatic pass on screen open
    // is silent (prices just appear).
    if (force && mounted) {
      HapticFeedback.mediumImpact();
      _snack('Prices updated.');
    }
  }

  /// Distinct open positions from the current ledger, in display order.
  List<PortfolioPosition> _txnsByPosition() =>
      PortfolioStore.aggregate(_txns, aliases: _lookup?.aliases);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// SnackBar with a 6-second Undo that restores [snapshot] as the ledger.
  void _snackUndo(String message, List<PortfolioTxn> snapshot) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await PortfolioStore.saveAll(snapshot);
            await _refresh();
          },
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Export / import / clear
  // ----------------------------------------------------------------

  Future<void> _exportJson() async {
    if (_txns.isEmpty) return _snack('Nothing to export yet.');
    try {
      await PortfolioTransfer.exportJson(_txns);
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  Future<void> _exportCsv() async {
    if (_txns.isEmpty) return _snack('Nothing to export yet.');
    try {
      await PortfolioTransfer.exportCsv(_txns);
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  Future<void> _import() async {
    String? raw;
    try {
      raw = await PortfolioTransfer.pickJson();
    } catch (e) {
      return _snack('Could not read the file: $e');
    }
    if (raw == null) return; // cancelled

    final result = PortfolioCodec.decode(raw);
    if (!result.ok) return _snack(result.fatal!);
    if (result.txns.isEmpty) {
      return _snack('No valid transactions found in that file.');
    }

    final mode = await _askImportMode(result);
    if (mode == null) return;

    final existing = await PortfolioStore.load();
    final next = mode == 'replace'
        ? result.txns
        : PortfolioCodec.merge(existing, result.txns);
    await PortfolioStore.saveAll(next);
    await _refresh();

    final skipped = result.skipped > 0 ? ', skipped ${result.skipped}' : '';
    _snack('Imported ${result.txns.length} transaction'
        '${result.txns.length == 1 ? '' : 's'}$skipped.');
  }

  /// Asks whether to replace everything or merge (de-duplicating by id).
  Future<String?> _askImportMode(ImportResult result) {
    final existing = _txns.length;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import portfolio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This file has ${result.txns.length} transaction'
                '${result.txns.length == 1 ? '' : 's'}.'),
            if (result.skipped > 0) ...[
              const SizedBox(height: 6),
              Text('${result.skipped} row(s) will be skipped.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Text('Your portfolio currently has $existing transaction'
                '${existing == 1 ? '' : 's'}.'),
            const SizedBox(height: 8),
            const Text(
              'Merge skips entries you already have, so importing the same '
              'file twice will not double your holdings.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('Replace'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll() async {
    if (_txns.isEmpty) return _snack('Portfolio is already empty.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear portfolio'),
        content: Text('Delete all ${_txns.length} transactions? '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final snapshot = List<PortfolioTxn>.of(_txns);
    await PortfolioStore.clearAll();
    await _refresh();
    _snackUndo('Portfolio cleared.', snapshot);
  }

  // ----------------------------------------------------------------
  // Editing
  // ----------------------------------------------------------------

  /// Position level edit: rename / re-code every lot of the line, using the
  /// same single-box dictionary lookup as the add sheet. Average price and
  /// total are always auto-calculated, so they are not editable here.
  Future<void> _editPosition(PortfolioPosition p) async {
    var code = p.code;
    var name = p.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update stock'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StockIdentifierField(
                market: p.market,
                initialCode: p.code,
                initialName: p.name,
                lookup: _lookup,
                onResolved: (c, n) {
                  code = c;
                  name = n;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Applies to all ${p.lots.length} transaction(s). Average price '
                'and total stay auto-calculated.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (code.isEmpty && name.isEmpty) {
      return _snack('Enter a stock code or name.');
    }

    final positionsBefore =
        PortfolioStore.aggregate(_txns, aliases: _lookup?.aliases).length;
    final updated =
        PortfolioStore.applyPositionEdit(_txns, p, code: code, name: name);
    final positionsAfter =
        PortfolioStore.aggregate(updated, aliases: _lookup?.aliases).length;

    await PortfolioStore.saveAll(updated);
    await _refresh();
    _snack(positionsAfter < positionsBefore
        ? 'Updated - merged with an existing line.'
        : 'Stock updated.');
  }

  /// Lot level edit: reuses the add sheet so validation is identical. Only the
  /// code, name, date and total are editable.
  Future<void> _editLot(PortfolioTxn lot) async {
    final outcome = await showPortfolioEntrySheet(
      context,
      market: lot.market,
      currency: lot.currency,
      side: lot.side,
      qty: lot.qty,
      price: lot.effectivePrice,
      total: lot.total,
      existing: lot,
      allTxns: _txns,
      allowDelete: true,
      lookup: _lookup,
    );
    if (outcome == null) return;

    if (outcome.deletedId != null) {
      await PortfolioStore.delete(outcome.deletedId!);
      await _refresh();
      return _snack('Transaction deleted.');
    }
    final saved = outcome.saved;
    if (saved == null) return;
    await PortfolioStore.update(saved);
    await _refresh();
    _snack('Transaction updated.');
  }

  /// Deletes the whole line immediately and offers a 6-second Undo.
  Future<void> _deleteWholeLine(PortfolioPosition p) async {
    final snapshot = List<PortfolioTxn>.of(_txns);
    await PortfolioStore.deletePosition(_txns, p);
    await _refresh();
    _snackUndo('Line deleted.', snapshot);
  }

  /// Deletes one transaction immediately and offers a 6-second Undo.
  Future<void> _deleteLot(PortfolioTxn lot) async {
    final snapshot = List<PortfolioTxn>.of(_txns);
    await PortfolioStore.delete(lot.id);
    await _refresh();
    _snackUndo('Transaction deleted.', snapshot);
  }

  /// Matches the Home header gradient so pushed screens feel continuous.
  Widget _appBarGradient(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? AppColors.appBarGradientDark
                : AppColors.appBarGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final positions =
        PortfolioStore.aggregate(_txns, aliases: _lookup?.aliases);
    final groups = PortfolioStore.group(positions);
    final totals = PortfolioStore.totals(positions, quotes: _quotes);

    return Scaffold(
      appBar: AppBar(
        // Explicit so the way back never depends on theme inference - iOS has
        // no system back button, so this arrow is the primary affordance.
        leading: const BackButton(),
        backgroundColor: Colors.transparent,
        flexibleSpace: _appBarGradient(context),
        title: const Text('Portfolio Log'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Portfolio log options',
            onSelected: (v) {
              if (v == 'json') {
                _exportJson();
              } else if (v == 'csv') {
                _exportCsv();
              } else if (v == 'import') {
                _import();
              } else if (v == 'prices') {
                _refreshPrices(force: true);
              } else if (v == 'clear') {
                _clearAll();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'json',
                child: Text('Export JSON (re-importable)'),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Text('Export CSV (spreadsheet)'),
              ),
              PopupMenuItem(value: 'import', child: Text('Import JSON...')),
              PopupMenuItem(value: 'prices', child: Text('Refresh prices')),
              PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
              ? _emptyState()
              : Column(
                  children: [
                    _buildFilterBar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => _refreshPrices(force: true),
                        child: _buildList(groups, totals),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Filter field + sort menu shown above the holdings list.
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _filterCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Filter',
                hintText: 'Code or name',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Sort holdings',
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'market', child: Text('Sort: Market')),
              PopupMenuItem(value: 'value', child: Text('Sort: Value')),
              PopupMenuItem(value: 'pl', child: Text('Sort: P/L %')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<PortfolioGroup> groups, PortfolioTotals totals) {
    final filtered = _filteredGroups(groups);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No holdings match the filter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          ...filtered.map(_buildGroup),
          _buildTotals(totals),
        ],
      ],
    );
  }

  /// Applies the filter box and the sort menu to the grouped positions.
  /// Totals are always computed over ALL positions, so filtering only hides
  /// lines - it never changes the money.
  List<PortfolioGroup> _filteredGroups(List<PortfolioGroup> groups) {
    final f = _filterCtrl.text.trim().toLowerCase();
    Iterable<PortfolioGroup> out = groups;
    if (f.isNotEmpty) {
      out = groups
          .map((g) => PortfolioGroup(
                market: g.market,
                currency: g.currency,
                positions: g.positions
                    .where((p) =>
                        p.code.toLowerCase().contains(f) ||
                        p.name.toLowerCase().contains(f))
                    .toList(),
              ))
          .where((g) => g.positions.isNotEmpty);
    }
    if (_sort == 'market') return out.toList();
    double valueFor(PortfolioPosition p) {
      final q = _quotes[p.quoteKey];
      return q == null ? -1 : p.marketValue(q);
    }

    double plFor(PortfolioPosition p) {
      final q = _quotes[p.quoteKey];
      if (q == null || p.cost <= 0) return double.negativeInfinity;
      return p.unrealisedPL(q) / p.cost;
    }

    final cmp = _sort == 'value'
        ? (PortfolioPosition a, PortfolioPosition b) =>
            valueFor(b).compareTo(valueFor(a))
        : (PortfolioPosition a, PortfolioPosition b) =>
            plFor(b).compareTo(plFor(a));
    return out
        .map((g) => PortfolioGroup(
              market: g.market,
              currency: g.currency,
              positions: [...g.positions]..sort(cmp),
            ))
        .toList();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_center_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No holdings yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'The Portfolio Log is a manual, on-device record of your own '
              'past transactions - record-keeping only. MMCal cannot place '
              'orders. Calculate a trade, then tap + next to Copy on the '
              'results to add it here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('Import JSON'),
            ),
          ],
        ),
      ),
    );
  }

  /// One total row per settlement currency, summed across all groups. Currencies
  /// are never converted or combined with each other. When quotes have been
  /// fetched, Value and unrealised P/L rows are added per currency - summed
  /// only over lines that have a price.
  Widget _buildTotals(PortfolioTotals totals) {
    if (totals.byCurrency.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final multi = !totals.isSingleCurrency;
    final hasQuotes = totals.byCurrency.any((t) => t.value != null);
    final unquoted =
        totals.byCurrency.fold<int>(0, (a, t) => a + t.unquoted);
    return Card(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in totals.byCurrency)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total (${t.currency})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  multi ? FontWeight.w600 : FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          _money.format(t.cost),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (t.value != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text('Value (${t.currency})',
                                style: theme.textTheme.bodySmall),
                          ),
                          Text(_money.format(t.value!),
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    if (t.pl != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text('P/L (${t.currency})',
                                style: theme.textTheme.bodySmall),
                          ),
                          Text(
                            '${t.pl! >= 0 ? '+' : ''}${_money.format(t.pl!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: t.pl! >= 0
                                  ? Colors.green.shade700
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              multi
                  ? 'Per-currency totals are never converted.'
                  : _linesMarkets(
                      totals.byCurrency.first.lines,
                      totals.byCurrency.first.markets,
                    ),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (hasQuotes && unquoted > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Value/P/L cover $unquoted line(s) without a price.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _linesMarkets(int lines, int markets) {
    final l = '$lines line${lines == 1 ? '' : 's'}';
    if (markets <= 1) return l;
    return '$l · $markets markets';
  }

  Widget _buildGroup(PortfolioGroup g) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Text(marketFlag(g.market),
                style: const TextStyle(fontSize: 20)),
            title: Text('${g.market} - ${g.currency}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${g.positions.length} line${g.positions.length == 1 ? '' : 's'}'),
            trailing: Text(
              '${_money.format(g.subtotal)} ${g.currency}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary),
            ),
          ),
          const Divider(height: 1),
          ...g.positions.map(_buildPosition),
        ],
      ),
    );
  }

  Widget _buildPosition(PortfolioPosition p) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        onExpansionChanged: (open) {
          if (open) _fetchQuoteFor(p);
        },
        title: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                p.displayCode,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(p.displayName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(_shortDate(p.lastDate), style: theme.textTheme.bodySmall),
              const SizedBox(width: 10),
              Text('Qty ${_plain(p.qty)}', style: theme.textTheme.bodySmall),
              const SizedBox(width: 10),
              Text('Avg ${_money.format(p.avgPrice)}',
                  style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(
                _money.format(p.cost),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
        children: [
          _buildQuoteLine(p),
          _buildWhatIf(p),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _editPosition(p),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Update name / code'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _deleteWholeLine(p),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete line'),
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error),
              ),
            ],
          ),
          const Divider(height: 1),
          ...p.lots.map((lot) => _buildLot(lot, p)),
        ],
      ),
    );
  }

  /// Last done price, market value and unrealised P/L for an expanded line.
  /// Nothing is shown until a quote arrives; a failed fetch leaves the row
  /// exactly as before.
  Widget _buildQuoteLine(PortfolioPosition p) {
    final q = _quotes[p.quoteKey];
    if (q == null) return const SizedBox.shrink();
    // Lazily top up the 30-day history the first time this line is expanded.
    _fetchHistoryFor(p);
    final theme = Theme.of(context);
    final pl = p.unrealisedPL(q);
    final pct = p.cost > 0 ? pl / p.cost * 100 : null;
    final plLabel = pct == null
        ? 'P/L ${pl >= 0 ? '+' : ''}${_money.format(pl)} ${p.currency}'
        : 'P/L ${pl >= 0 ? '+' : ''}${_money.format(pl)} ${p.currency} '
            '(${pl >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)';
    final plColor = pl > 0
        ? Colors.green.shade700
        : pl < 0
            ? theme.colorScheme.error
            : null;
    final hist = _history[p.quoteKey];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Last ${_money.format(q.price)} ${q.currency}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Text('(reference price)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('Value ${_money.format(p.marketValue(q))} ${p.currency}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: 10),
              Text(
                plLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: plColor,
                ),
              ),
            ],
          ),
          if (hist != null && hist.length >= 2) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Sparkline(closes: hist),
                const SizedBox(width: 8),
                Text('30 days',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Fetches the 30-day daily closes for [p] once per session (QuoteService
  /// caches them for an hour). Empty/failed history simply never appears.
  Future<void> _fetchHistoryFor(PortfolioPosition p) async {
    final service = _quoteService;
    if (service == null ||
        _history.containsKey(p.quoteKey) ||
        _histFetched.contains(p.quoteKey)) {
      return;
    }
    _histFetched.add(p.quoteKey);
    final closes = await service.history(p.market, p.code);
    if (closes.isEmpty || !mounted) return;
    setState(() => _history[p.quoteKey] = closes);
  }

  /// Sell what-if preview: estimated net proceeds and realised P/L for selling
  /// a slice of the holding at the last reference price, using the market's
  /// real fee engine. Preview only - nothing is saved, no order is placed.
  Widget _buildWhatIf(PortfolioPosition p) {
    final q = _quotes[p.quoteKey];
    if (q == null || p.qty <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    const pcts = [25, 50, 75, 100];
    final sel = _whatIfPct[p.quoteKey] ?? 100;
    final qty = p.qty * sel / 100.0;
    final est = _whatIfEstimate(p, qty, q.price);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sell what-if',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final pc in pcts)
                ChoiceChip(
                  label: Text('$pc%'),
                  selected: pc == sel,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _whatIfPct[p.quoteKey] = pc),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (est != null) ...[
            Text(
              'Sell ${_plain(qty)} @ ${_money.format(q.price)} '
              '${p.currency} -> net ~${_money.format(est.$1)} ${p.currency}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Realised P/L ~${est.$2 >= 0 ? '+' : ''}'
              '${_money.format(est.$2)} ${p.currency}'
              '${p.cost > 0 ? ' (${est.$2 >= 0 ? '+' : ''}${(est.$2 / (p.cost * sel / 100.0)).toStringAsFixed(1)}%)' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: est.$2 > 0
                    ? Colors.green.shade700
                    : est.$2 < 0
                        ? theme.colorScheme.error
                        : null,
              ),
            ),
          ],
          Text('Estimate only - the app cannot place orders.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  /// Net proceeds (settlement currency) and realised P/L for selling [qty] at
  /// [price], computed with the market's real online fee schedule. GST is not
  /// applied (the app's default), matching the calculator's default state.
  (double, double)? _whatIfEstimate(
      PortfolioPosition p, double qty, double price) {
    if (qty <= 0 || price <= 0) return null;
    SettingsManager s;
    try {
      s = SettingsManager.instance;
    } catch (_) {
      s = SettingsManager(); // defaults (tests)
    }
    Market? m;
    for (final mk in getAllMarkets(s)) {
      if (mk.name == p.market) {
        m = mk;
        break;
      }
    }
    if (m == null) return null;
    // Foreign holdings stored in local currency estimate in local currency
    // (settle-in-local, rate 1.0); MYR-settled holdings estimate in MYR.
    final local = p.currency != 'MYR';
    final flag = 16 | (local ? 8 : 0);
    final calc = m.calculate(
        mode: 6,
        buysel: 2,
        flag: flag,
        qty: qty,
        price: price,
        rate: 1.0,
        brkrate: 0);
    final net = p.market == 'Malaysia'
        ? calc.get('val1')
        : local
            ? calc.get('val2')
            : calc.get('net_value');
    final costSlice = p.cost * qty / p.qty;
    return (net, net - costSlice);
  }

  /// One transaction row inside an expanded holding. A buy also shows how much
  /// of it is still held, so a sell knocking off the oldest purchase (FIFO) is
  /// visible rather than implied.
  Widget _buildLot(PortfolioTxn lot, PortfolioPosition p) {
    final theme = Theme.of(context);
    final sideColor =
        lot.isBuy ? theme.colorScheme.primary : theme.colorScheme.error;
    // Contract price when stored; older entries fall back to total / qty.
    final price = lot.effectivePrice;
    final openQty = lot.isBuy ? (p.openQtyByLot[lot.id] ?? 0.0) : 0.0;
    return ListTile(
      dense: true,
      leading: Container(
        width: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: sideColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          lot.isBuy ? 'BUY' : 'SELL',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: sideColor),
        ),
      ),
      title: Text(
        '${_shortDate(lot.date)}   ${_plain(lot.qty)} @ ${_money.format(price)}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        lot.isBuy
            ? (openQty > 0
                ? 'Total ${_money.format(lot.total)} ${lot.currency} '
                    '· ${_plain(openQty)} open'
                : 'Total ${_money.format(lot.total)} ${lot.currency} · sold')
            : 'Total ${_money.format(lot.total)} ${lot.currency}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: lot.isBuy && openQty <= 0
              ? theme.colorScheme.onSurfaceVariant
              : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Edit transaction',
            onPressed: () => _editLot(lot),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete transaction',
            onPressed: () => _deleteLot(lot),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  /// '2026-08-25' -> '25 Aug 26'.
  static String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : _dayFmt.format(d);
  }

  /// Drops trailing zeros: 1500.0000 -> '1500', 7.5000 -> '7.5'.
  static String _plain(double v) {
    var t = v.toStringAsFixed(4);
    if (t.contains('.')) {
      while (t.endsWith('0')) {
        t = t.substring(0, t.length - 1);
      }
      if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    }
    return t;
  }
}



