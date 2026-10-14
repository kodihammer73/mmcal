import 'dart:async';

import 'package:flutter/material.dart';

import '../services/symbol_lookup.dart';
import 'input_formatters.dart';

/// A single "stock code or name" input backed by the symbol dictionary.
///
/// One box instead of separate code and name fields: as the user types, the
/// dictionary for [market] is searched and the matches are offered for tapping.
/// The parent always receives the resolution through [onResolved]:
///
///  * the dictionary's code and short name when the user tapped a suggestion,
///  * the same pair when what they typed is an exact dictionary match,
///  * the pair already stored on the record when this is an edit that was left
///    untouched and the dictionary has no better answer,
///  * otherwise exactly what they typed, so a stock the dictionary does not
///    know still saves.
class StockIdentifierField extends StatefulWidget {
  const StockIdentifierField({
    super.key,
    required this.market,
    this.initialCode = '',
    this.initialName = '',
    this.lookup,
    this.onResolved,
    this.labelText = 'Stock code or name',
    this.hintText = 'e.g. MAYBANK or 1155',
  });

  /// Market whose dictionary entries are searched.
  final String market;

  /// Values stored on the record being edited (empty when adding).
  final String initialCode;
  final String initialName;

  /// Caller-supplied dictionary, which keeps tests offline and deterministic.
  final SymbolLookup? lookup;

  /// Receives the resolved (code, name) after every change, including once
  /// after the first frame.
  final void Function(String code, String name)? onResolved;

  final String labelText;
  final String hintText;

  @override
  State<StockIdentifierField> createState() => _StockIdentifierFieldState();
}

class _StockIdentifierFieldState extends State<StockIdentifierField> {
  late final TextEditingController _controller;
  late final String _initialText;

  SymbolLookup? _lookup;
  SymbolEntry? _picked;
  Timer? _debounce;
  List<SymbolEntry> _suggestions = const [];
  bool _searching = false;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _initialText = widget.initialCode.trim().isNotEmpty
        ? widget.initialCode.trim()
        : widget.initialName.trim();
    _controller = TextEditingController(text: _initialText);
    _controller.addListener(_onChanged);
    SymbolLookup.current.addListener(_onDictionaryUpdated);
    _initLookup();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
  }

  /// Resolves the dictionary once per field. A caller-supplied instance wins,
  /// which keeps widget tests offline and deterministic.
  void _initLookup() {
    final provided = widget.lookup;
    if (provided != null) {
      _lookup = provided;
      return;
    }
    SymbolLookup.instance().then((loaded) {
      if (!mounted || identical(loaded, _lookup)) return;
      setState(() => _lookup = loaded);
      _notify();
      _scheduleSearch();
    });
  }

  /// The background refresh swapped in a newer published dictionary.
  void _onDictionaryUpdated() {
    if (!mounted || widget.lookup != null) return;
    final latest = SymbolLookup.current.value;
    if (identical(latest, _lookup)) return;
    setState(() => _lookup = latest);
    _notify();
    _scheduleSearch();
  }

  /// What will be saved: dictionary values when known, the typed text otherwise.
  (String code, String name) _resolve() {
    final picked = _picked;
    if (picked != null) return (picked.code, picked.displayName);

    final typed = _controller.text.trim();

    final lookup = _lookup;
    if (lookup != null) {
      final match = lookup.exactMatch(widget.market, typed);
      if (match != null) return (match.code, match.displayName);
    }

    final untouched = _initialText.isNotEmpty && typed == _initialText;
    if (untouched &&
        (widget.initialCode.isNotEmpty || widget.initialName.isNotEmpty)) {
      return (widget.initialCode, widget.initialName);
    }

    return (typed, typed);
  }

  void _notify() {
    final (code, name) = _resolve();
    widget.onResolved?.call(code, name);
  }

  void _onChanged() {
    // Typing again means an earlier pick no longer applies.
    if (_picked != null) setState(() => _picked = null);
    _notify();
    _scheduleSearch();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (_lookup == null || query.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final lookup = _lookup;
    if (lookup == null || !mounted) return;
    final seq = ++_searchSeq;
    setState(() => _searching = true);

    final found = await lookup.suggestWithFallback(widget.market, query);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      _suggestions = found;
    });
  }

  /// Remembers a tapped suggestion; the typed text is left alone so the user
  /// can still see what they entered while the chip confirms the stored values.
  void _applySuggestion(SymbolEntry entry) {
    _debounce?.cancel();
    _searchSeq++;
    setState(() {
      _picked = entry;
      _suggestions = const [];
      _searching = false;
    });
    _notify();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    SymbolLookup.current.removeListener(_onDictionaryUpdated);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('stock-identifier'),
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseTextFormatter()],
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search, size: 18),
          ),
        ),
        if (picked != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.check_circle,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${picked.code} · ${picked.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Clear selection',
              onPressed: () => setState(() => _picked = null),
              icon: const Icon(Icons.close),
            ),
          ]),
        ],
        if (_searching || _suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          _suggestionsPanel(theme),
        ],
      ],
    );
  }

  /// Autocomplete list shown under the field. Tapping a row stores that code
  /// and short name; the user can ignore it and type something else instead.
  Widget _suggestionsPanel(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(children: [
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Looking up ${widget.market} symbols...',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
            )
          else
            for (final s in _suggestions)
              InkWell(
                key: ValueKey('suggestion-${s.market}-${s.code}'),
                onTap: () => _applySuggestion(s),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        s.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (s.name.isNotEmpty)
                      Text(
                        s.code,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ]),
                ),
              ),
        ],
      ),
    );
  }
}