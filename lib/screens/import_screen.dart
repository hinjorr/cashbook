import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../services/money_manager_import.dart';
import '../widgets/common.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  MmParseResult? _parsed;
  String? _fileName;
  ImportReport? _report;
  bool _replace = false;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _report = null;
    });
    try {
      final parsed = parseMoneyManagerExport(await f.xFile.readAsBytes());
      setState(() {
        _parsed = parsed;
        _fileName = f.name;
      });
    } catch (e) {
      setState(() {
        _parsed = null;
        _error = e is FormatException ? e.message : '$e';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final r = await applyMoneyManagerImport(s.db, _parsed!, replaceExisting: _replace);
      await s.changed();
      setState(() => _report = r);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from Money Manager')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_report != null) _ReportView(report: _report!) else ..._pickerView(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _pickerView(BuildContext context) {
    final p = _parsed;
    final s = context.watch<AppState>();
    return [
      const Text(
        'In Money Manager open More › Backup › "Export data to Excel", choose the date range, '
        'and share the file to your phone. Then pick it here.',
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.attach_file),
        label: Text(_fileName ?? 'Choose export file'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(_error!, style: const TextStyle(color: expenseColor)),
        ),
      if (p != null) ...[
        const SizedBox(height: 16),
        _Preview(parsed: p),
        const SizedBox(height: 8),
        RadioGroup<bool>(
          groupValue: _replace,
          onChanged: (v) => setState(() => _replace = v ?? false),
          child: const Column(children: [
            RadioListTile(
              value: false,
              title: Text('Add to existing data'),
              subtitle: Text('Entries already in the app are skipped.'),
            ),
            RadioListTile(
              value: true,
              title: Text('Replace all data'),
              subtitle: Text('Deletes every account, category and transaction first.'),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: p.rows.isEmpty ? null : _import,
          child: Text('Import ${p.rows.length} rows'),
        ),
        if (s.accounts.isNotEmpty && !_replace)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Accounts with the same name as existing ones (${s.accounts.map((a) => a.name).join(', ')}) will be merged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ];
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.parsed});

  final MmParseResult parsed;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final rows = parsed.rows;
    if (rows.isEmpty) return const EmptyHint('No transactions found in this file.');
    final dates = rows.map((r) => r.date).toList()..sort();
    int count(MmKind k) => rows.where((r) => r.kind == k).length;
    int sum(MmKind k) => rows.where((r) => r.kind == k).fold(0, (a, r) => a + r.amount);
    final accounts = <String>{
      for (final r in rows) r.account,
      for (final r in rows.where((r) => r.kind == MmKind.transferOut || r.kind == MmKind.transferIn)) r.category,
    }..remove('');
    final f = DateFormat('d MMM yyyy');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${rows.length} transactions, ${f.format(dates.first)} – ${f.format(dates.last)}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Income: ${count(MmKind.income)} (${s.money(sum(MmKind.income))})', style: const TextStyle(color: incomeColor)),
            Text('Expenses: ${count(MmKind.expense)} (${s.money(sum(MmKind.expense))})', style: const TextStyle(color: expenseColor)),
            Text('Transfers: ${count(MmKind.transferOut) + count(MmKind.transferIn)}'),
            const SizedBox(height: 8),
            Text('Accounts: ${accounts.join(', ')}'),
            for (final w in parsed.warnings.take(5))
              Text(w, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: expenseColor)),
            if (parsed.warnings.length > 5)
              Text('…and ${parsed.warnings.length - 5} more warnings', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// After import: confirms the result and lets the user mark investment accounts.
class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: investColor, size: 48),
        const SizedBox(height: 8),
        Text(
          'Imported ${report.imported} transactions'
          '${report.duplicates > 0 ? ', skipped ${report.duplicates} already in the app' : ''}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final w in report.warnings.take(5))
          Text(w, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: expenseColor)),
        const SizedBox(height: 24),
        Text('Which accounts are investments?', style: Theme.of(context).textTheme.titleSmall),
        const Text('Money you transfer into these accounts is counted in Stats › Invested.'),
        const SizedBox(height: 8),
        for (final a in s.accounts)
          SwitchListTile(
            title: Text(a.name),
            subtitle: Text(a.group),
            value: a.isInvestment,
            onChanged: (v) async {
              await s.db.saveAccount(a.copyWith(
                isInvestment: v,
                group: v ? 'Investments' : (a.group == 'Investments' ? 'Others' : a.group),
              ));
              await s.changed();
            },
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
