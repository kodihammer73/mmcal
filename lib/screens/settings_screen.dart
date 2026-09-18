import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/settings.dart';
import '../main.dart';
import '../ui/branding.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> _ctrls = {};

  /// App version (e.g. "1.0.3"), fetched once via PackageInfo. Null if
  /// unavailable, in which case the footer attribution omits it.
  String? _appVersion;

  static const _groups = [
    _Group('General', [
      _Field('offlinebrk', 'Min Offline Brokerage (RM)'),
      _Field('onlinebrk', 'Min Online Brokerage (RM)'),
      _Field('minstampduty', 'Min Stamp Duty (RM)'),
      _Field('maxstampduty', 'Max Stamp Duty (RM)'),
      _Field('gstrate', 'SST/GST Rate (%)'),
      _Field('rmbrkamt', 'RM Threshold for Brokerage Rate'),
    ]),
    _Group('Malaysia', [
      _Field('malclrfeerate', 'Clearing Fee Rate (%)'),
      _Field('malstmpdutyrate', 'Stamp Duty Rate (%)'),
      _Field('maloffbrkrate1', 'Offline Brk Rate < RM100K (%)'),
      _Field('maloffbrkrate2', 'Offline Brk Rate >= RM100K (%)'),
      _Field('malonbrkrate1', 'Online Brk Rate < RM100K (%)'),
      _Field('malonbrkrate2', 'Online Brk Rate >= RM100K (%)'),
      _Field('malminbrk', 'Min Brokerage RM12'),
      _Field('malminbrk8', 'Min Brokerage RM8'),
      _Field('dfintrate', 'DF Interest Rate (% p.a.)'),
      _Field('dfintbasis', 'DF Interest Day Basis (days/year)'),
      _Field('dfminfee', 'Min DF Fee (RM)'),
      _Field('dffeeamt', 'DF Fee Tier Threshold (RM)'),
      _Field('dffeerate1', 'DF Fee Rate Below Threshold (%)'),
      _Field('dffeerate2', 'DF Fee Rate At/Above Threshold (%)'),
      _Field('dfmindays', 'DF Free Days (no interest/fee up to)'),
      _Field('dfmaxdays', 'Max DF Days'),
    ]),
    _Group('United States (US)', [
      _Field('usaforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('usasecfeerate', 'SEC Fee Rate (%)'),
      _Field('usastmpdutyrate', 'Stamp Duty Rate (%)'),
      _Field('usaoffminrmbrkrate', 'Offline Brk < RM100K (%)'),
      _Field('usaoffmaxrmbrkrate', 'Offline Brk >= RM100K (%)'),
      _Field('usaonminrmbrkrate', 'Online Brk < RM100K (%)'),
      _Field('usaonmaxrmbrkrate', 'Online Brk >= RM100K (%)'),
      _Field('usaminbroff', 'Min Offline Brokerage (USD)'),
      _Field('usaminbron', 'Min Online Brokerage (USD)'),
      _Field('usaminforbrk', 'Min Foreign Brokerage (USD)'),
      _Field('usaminbrtoff', 'Min Total Brokerage Offline (USD)'),
    ]),
    _Group('Singapore', [
      _Field('sinforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('sintrdfeerate', 'Trading Fee Rate (%)'),
      _Field('sinclrfeerate', 'Clearing Fee Rate (%)'),
      _Field('sinstmpdutyrate', 'Stamp Duty Rate (%)'),
      _Field('sinoffminrmbrkrate', 'Offline Brk < RM100K (%)'),
      _Field('sinoffmaxrmbrkrate', 'Offline Brk >= RM100K (%)'),
      _Field('sinonminrmbrkrate', 'Online Brk < RM100K (%)'),
      _Field('sinonmaxrmbrkrate', 'Online Brk >= RM100K (%)'),
      _Field('sinminbroff', 'Min Offline Brokerage (SGD)'),
      _Field('sinminbron', 'Min Online Brokerage (SGD)'),
      _Field('sinminbronpromo', 'Min Online Special-Rate Brk (SGD)'),
      _Field('sinminforbrk', 'Min Foreign Brokerage (SGD)'),
    ]),
    _Group('Hong Kong', [
      _Field('hkdforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('hkdtrdfeerate', 'Trading Fee Rate (%)'),
      _Field('hkdlevyfeerate', 'Levy Fee Rate (%)'),
      _Field('hkdccassfeerate', 'CCASS Fee Rate (%)'),
      _Field('hkdminccassfee', 'Min CCASS Fee (HKD)'),
      _Field('hkdstampdutyrate', 'Foreign Stamp Duty Rate (%)'),
      _Field('hkdlocalstampdutyrate', 'Local Stamp Duty Rate (%)'),
      _Field('hkdoffminrmbrkrate', 'Offline Brk < RM100K (%)'),
      _Field('hkdoffmaxrmbrkrate', 'Offline Brk >= RM100K (%)'),
      _Field('hkdonminrmbrkrate', 'Online Brk < RM100K (%)'),
      _Field('hkdonmaxrmbrkrate', 'Online Brk >= RM100K (%)'),
      _Field('hkdminbroff', 'Min Offline Brokerage (HKD)'),
      _Field('hkdminbronpromo', 'Min Online Promo Brokerage (HKD)'),
      _Field('hkdminforbrk', 'Min Foreign Brokerage (HKD)'),
      _Field('hkdminbrton', 'Min Total Brokerage Online (HKD)'),
    ]),
    _Group('Thailand', [
      _Field('thaforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('thaoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('thaoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
      _Field('thaminbrtcomb', 'Min Combined Brokerage (THB)'),
    ]),
    _Group('Indonesia', [
      _Field('indforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('indoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('indoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
      _Field('indminbrtcomb', 'Min Combined Brokerage (IDR)'),
    ]),
    _Group('United Kingdom (UK)', [
      _Field('ukdforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('ukdoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('ukdoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
      _Field('ukdminbroff', 'Min Local Brokerage (GBP)'),
      _Field('ukdminforbrk', 'Min Foreign Brokerage (GBP)'),
      _Field('ukdminbrtcomb', 'Min Combined Brokerage (GBP)'),
      _Field('ukdminibfee', 'Min IB Fee (GBP)'),
    ]),
    _Group('Australia', [
      _Field('ausforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('ausoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('ausoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
      _Field('ausminbroff', 'Min Local Brokerage (AUD)'),
      _Field('ausminforbrk', 'Min Foreign Brokerage (AUD)'),
      _Field('ausminbrtcomb', 'Min Combined Brokerage (AUD)'),
      _Field('ausminibfee', 'Min IB Fee (AUD)'),
    ]),
    _Group('Japan', [
      _Field('japforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('japoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('japoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
      _Field('japminbroff', 'Min Local Brokerage (JPY)'),
      _Field('japminforbrk', 'Min Foreign Brokerage (JPY)'),
      _Field('japminbrtcomb', 'Min Combined Brokerage (JPY)'),
      _Field('japminibfee', 'Min IB Fee (JPY)'),
    ]),
    _Group('Canada', [
      _Field('canforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('canoffminrmbrkrate', 'Offline Brk < RM100K (%)'),
      _Field('canoffmaxrmbrkrate', 'Offline Brk >= RM100K (%)'),
      _Field('canminbroff', 'Min Offline Brokerage (CAD)'),
      _Field('canminbrton', 'Min Online Brokerage (CAD)'),
      _Field('canminibfee', 'Min IB Fee (CAD)'),
    ]),
    _Group('Germany', [
      _Field('gerforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('geroffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('geroffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
      _Field('germinbroff', 'Min Local Brokerage (EUR)'),
      _Field('germinforbrk', 'Min Foreign Brokerage (EUR)'),
      _Field('germinbrtcomb', 'Min Combined Brokerage (EUR)'),
      _Field('germinibfee', 'Min IB Fee (EUR)'),
    ]),
  ];


  @override
  void initState() {
    super.initState();
    final s = SettingsManager.instance;
    for (final g in _groups) {
      for (final f in g.fields) {
        _ctrls[f.key] = TextEditingController(text: s.get(f.key).toString());
      }
    }
    // Best-effort: fetch the app version once for the footer attribution.
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // Not available (e.g. in tests / non-Android/iOS). Keep it null.
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }

    super.dispose();
  }

  Future<void> _save() async {
    final s = SettingsManager.instance;
    for (final entry in _ctrls.entries) {
      final v = double.tryParse(entry.value.text);
      if (v != null) s.set(entry.key, v);
    }
    await s.save();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_saveMsg()), duration: const Duration(seconds: 2)),
      );
    }
  }


  String _saveMsg() {
    final invalid = _ctrls.values
        .where((ctrl) => double.tryParse(ctrl.text) == null)
        .length;
    return invalid == 0
        ? 'Settings saved'
        : 'Saved valid values ($invalid invalid field${invalid == 1 ? '' : 's'} ignored)';
  }
  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text('Reset all settings to default values?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    await SettingsManager.instance.resetToDefaults();
    final s = SettingsManager.instance;
    for (final g in _groups) {
      for (final f in g.fields) {
        _ctrls[f.key]?.text = s.get(f.key).toString();
      }
    }
    setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Explicit so the way back never depends on theme inference - iOS has
        // no system back button, so this arrow is the primary affordance.
        leading: const BackButton(),
        backgroundColor: Colors.transparent,
        flexibleSpace: _appBarGradient(context),
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: Text(
              'Reset',
              style: TextStyle(
                color: Theme.of(context).appBarTheme.foregroundColor ??
                    Colors.white,
              ),
            ),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ..._groups.map((g) => _buildGroup(g)),
          const SizedBox(height: 8),
          _buildAttribution(),
        ],
      ),
    );
  }

  /// Bottom attribution line (moved here from the market results footer).
  Widget _buildAttribution() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${DateTime.now().year} · Developed by Hemerjit · v${_appVersion ?? ''}',
              style: TextStyle(
                  color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(_Group g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: g.title == 'General'
            ? Icon(Icons.tune, color: Theme.of(context).colorScheme.primary)
            : Text(marketFlag(g.title), style: const TextStyle(fontSize: 18)),
        title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        initiallyExpanded: g.title == 'General',
        children: g.fields.map((f) => _buildField(f)).toList(),
      ),
    );
  }

  Widget _buildField(_Field f) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _ctrls[f.key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: f.label,
          errorText: double.tryParse(_ctrls[f.key]?.text ?? '') == null
              ? 'Enter a valid number'
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}


class _Group {
  final String title;
  final List<_Field> fields;
  const _Group(this.title, this.fields);
}

class _Field {
  final String key;
  final String label;
  const _Field(this.key, this.label);
}
