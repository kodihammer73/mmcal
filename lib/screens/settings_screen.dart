import 'package:flutter/material.dart';
import '../config/settings.dart';
import '../ui/branding.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> _ctrls = {};

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
    ]),
    _Group('United States (US)', [
      _Field('usaforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('usasecfeerate', 'SEC Fee Rate (%)'),
      _Field('usastmpdutyrate', 'Stamp Duty Rate (%)'),
      _Field('usaoffminrmbrkrate', 'Offline Brk < RM100K (%)'),
      _Field('usaoffmaxrmbrkrate', 'Offline Brk >= RM100K (%)'),
      _Field('usaonminrmbrkrate', 'Online Brk < RM100K (%)'),
      _Field('usaonmaxrmbrkrate', 'Online Brk >= RM100K (%)'),
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
    ]),
    _Group('Thailand', [
      _Field('thaforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('thaoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('thaoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
    ]),
    _Group('Indonesia', [
      _Field('indforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('indoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('indoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
    ]),
    _Group('United Kingdom (UK)', [
      _Field('ukdforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('ukdoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('ukdoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
    ]),
    _Group('Australia', [
      _Field('ausforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('ausoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('ausoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
    ]),
    _Group('Japan', [
      _Field('japforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('japoffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('japoffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
    ]),
    _Group('Canada', [
      _Field('canforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('canoffminrmbrkrate', 'Offline Brk < RM100K (%)'),
      _Field('canoffmaxrmbrkrate', 'Offline Brk >= RM100K (%)'),
    ]),
    _Group('Germany', [
      _Field('gerforchrgrate', 'Foreign Charge Rate (%)'),
      _Field('geroffminrmbrkrate', 'Offline Brk <= RM100K (%)'),
      _Field('geroffmaxrmbrkrate', 'Offline Brk > RM100K (%)'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: _groups.map((g) => _buildGroup(g)).toList(),
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
