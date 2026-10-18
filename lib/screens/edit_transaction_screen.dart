import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/money.dart';
import '../widgets/common.dart';

class EditTransactionScreen extends StatefulWidget {
  const EditTransactionScreen({super.key, this.txn, this.initialDate});

  final Txn? txn;
  final DateTime? initialDate;

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late TxnType _type;
  late DateTime _date;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _desc = TextEditingController();

  @override
  void initState() {
    super.initState();
    final t = widget.txn;
    final s = context.read<AppState>();
    if (t != null) {
      _type = t.type;
      _date = t.date;
      _accountId = t.accountId;
      _toAccountId = t.toAccountId;
      _categoryId = t.categoryId;
      _amount.text = moneyToInput(t.amount);
      _note.text = t.note;
      _desc.text = t.description;
    } else {
      _type = TxnType.expense;
      final now = DateTime.now();
      final d = widget.initialDate ?? now;
      _date = DateTime(d.year, d.month, d.day, now.hour, now.minute);
      final visible = s.accounts.where((a) => !a.hidden);
      _accountId = visible.isEmpty ? null : visible.first.id;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    setState(() => _date = DateTime(d.year, d.month, d.day, tm?.hour ?? _date.hour, tm?.minute ?? _date.minute));
  }

  Future<int?> _pickAccount(String title, {int? exclude}) {
    final s = context.read<AppState>();
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            for (final a in s.accounts.where((a) => !a.hidden && a.id != exclude))
              ListTile(
                leading: Icon(a.isInvestment ? Icons.trending_up : Icons.account_balance_wallet_outlined,
                    color: a.isInvestment ? investColor : null),
                title: Text(a.name),
                subtitle: Text(a.group),
                onTap: () => Navigator.pop(context, a.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    final s = context.read<AppState>();
    final top = s.topCategories(_type);
    final picked = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in top)
                ActionChip(
                  label: Text(c.name),
                  onPressed: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final subs = s.subcategories(picked.id!);
    if (subs.isEmpty) {
      setState(() => _categoryId = picked.id);
      return;
    }
    final sub = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(picked.name), subtitle: const Text('No subcategory'), onTap: () => Navigator.pop(context, picked)),
            for (final c in subs) ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c)),
          ],
        ),
      ),
    );
    if (sub != null) setState(() => _categoryId = sub.id);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final amount = parseMoney(_amount.text);
    String? error;
    if (amount == null || amount <= 0) {
      error = 'Enter an amount.';
    } else if (_accountId == null) {
      error = 'Choose an account.';
    } else if (_type == TxnType.transfer && (_toAccountId == null || _toAccountId == _accountId)) {
      error = 'Choose a different account to transfer to.';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final isTransfer = _type == TxnType.transfer;
    await s.db.saveTxn(Txn(
      id: widget.txn?.id,
      type: _type,
      date: _date,
      amount: amount!,
      accountId: _accountId!,
      toAccountId: isTransfer ? _toAccountId : null,
      categoryId: isTransfer ? null : _categoryId,
      note: _note.text.trim(),
      description: _desc.text.trim(),
    ));
    await s.changed();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<AppState>();
    await s.db.deleteTxn(widget.txn!.id!);
    await s.changed();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final color = colorFor(_type);
    final toInv = _type == TxnType.transfer &&
        (s.accountById[_toAccountId]?.isInvestment ?? false) &&
        !(s.accountById[_accountId]?.isInvestment ?? false);

    Widget row(String label, Widget child, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(width: 96, child: Text(label, style: TextStyle(color: Theme.of(context).hintColor))),
                Expanded(child: child),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.txn == null ? 'Add' : 'Edit'),
        actions: [
          if (widget.txn != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<TxnType>(
              segments: const [
                ButtonSegment(value: TxnType.income, label: Text('Income')),
                ButtonSegment(value: TxnType.expense, label: Text('Expense')),
                ButtonSegment(value: TxnType.transfer, label: Text('Transfer')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() {
                _type = v.first;
                if (s.categoryById[_categoryId]?.type != _type) _categoryId = null;
              }),
            ),
          ),
          row('Date', Text(DateFormat('EEE, d MMM yyyy  h:mm a').format(_date)), onTap: _pickDate),
          const Divider(height: 1),
          row(_type == TxnType.transfer ? 'From' : 'Account', Text(s.accountName(_accountId)), onTap: () async {
            final id = await _pickAccount('Account');
            if (id != null) setState(() => _accountId = id);
          }),
          const Divider(height: 1),
          if (_type == TxnType.transfer)
            row(
              'To',
              Row(children: [
                Text(s.accountName(_toAccountId)),
                if (toInv) ...[
                  const SizedBox(width: 8),
                  const Chip(label: Text('Investment'), visualDensity: VisualDensity.compact),
                ],
              ]),
              onTap: () async {
                final id = await _pickAccount('Transfer to', exclude: _accountId);
                if (id != null) setState(() => _toAccountId = id);
              },
            )
          else
            row('Category', Text(_categoryId == null ? 'Choose…' : s.categoryLabel(_categoryId)), onTap: _pickCategory),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 22, color: color, fontWeight: FontWeight.w600),
              decoration: InputDecoration(labelText: 'Amount', prefixText: '${s.currency} '),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _desc,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ),
          if (_type == TxnType.transfer)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tip: transfers into an account marked "Investment account" count towards your investment stats.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
