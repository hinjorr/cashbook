import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/money.dart';
import '../logic/period.dart';
import '../widgets/common.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditAccountScreen())),
        child: const Icon(Icons.add),
      ),
      body: Reloading<Map<int, int>>(
        load: s.db.balances,
        builder: (context, bal) {
          var assets = 0, liabilities = 0, invested = 0;
          for (final a in s.accounts) {
            final b = bal[a.id] ?? 0;
            if (b >= 0) {
              assets += b;
            } else {
              liabilities += b;
            }
            if (a.isInvestment) invested += b;
          }
          final groups = <String, List<Account>>{};
          for (final a in s.accounts) {
            groups.putIfAbsent(a.group, () => []).add(a);
          }
          final order = [...accountGroups, ...groups.keys.where((g) => !accountGroups.contains(g))];

          Widget head(String l, int v, Color? c) => Expanded(
                child: Column(children: [
                  Text(l, style: Theme.of(context).textTheme.bodySmall),
                  FittedBox(child: Text(s.money(v), style: TextStyle(color: c, fontWeight: FontWeight.w600))),
                ]),
              );

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  head('Assets', assets, incomeColor),
                  head('Liabilities', liabilities, expenseColor),
                  head('Total', assets + liabilities, null),
                ]),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
                  leading: const Icon(Icons.trending_up, color: investColor),
                  title: const Text('Invested (holdings)'),
                  trailing: Text(s.money(invested), style: const TextStyle(color: investColor, fontWeight: FontWeight.w600)),
                ),
              ),
              for (final g in order)
                if (groups[g] != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(children: [
                      Text(g, style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Text(s.money(groups[g]!.fold(0, (a, acc) => a + (bal[acc.id] ?? 0))),
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  for (final a in groups[g]!)
                    ListTile(
                      leading: Icon(
                        a.isInvestment ? Icons.trending_up : Icons.account_balance_wallet_outlined,
                        color: a.isInvestment ? investColor : null,
                      ),
                      title: Text(a.name + (a.hidden ? ' (hidden)' : '')),
                      trailing: Text(
                        s.money(bal[a.id] ?? 0),
                        style: TextStyle(color: (bal[a.id] ?? 0) < 0 ? expenseColor : incomeColor),
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountDetailScreen(account: a))),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.account});

  final Account account;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Period _period = Period.of(PeriodKind.monthly, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final acc = s.accountById[widget.account.id] ?? widget.account;
    return Scaffold(
      appBar: AppBar(
        title: Text(acc.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditAccountScreen(account: acc))),
          ),
        ],
      ),
      body: Column(
        children: [
          PeriodBar(
            period: _period,
            kinds: const [PeriodKind.monthly, PeriodKind.yearly, PeriodKind.all],
            onChanged: (p) => setState(() => _period = p),
          ),
          Expanded(
            child: Reloading<List<Txn>>(
              deps: [_period, acc.id],
              load: () => s.db.txnsForAccount(acc.id!, _period.start, _period.end),
              builder: (context, list) {
                var inflow = 0, outflow = 0;
                for (final t in list) {
                  final incoming = t.type == TxnType.income || (t.type == TxnType.transfer && t.toAccountId == acc.id);
                  if (incoming) {
                    inflow += t.amount;
                  } else {
                    outflow += t.amount;
                  }
                }
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(children: [
                        Expanded(child: ListTile(title: const Text('In'), subtitle: Text(s.money(inflow), style: const TextStyle(color: incomeColor)))),
                        Expanded(child: ListTile(title: const Text('Out'), subtitle: Text(s.money(outflow), style: const TextStyle(color: expenseColor)))),
                        Expanded(child: ListTile(title: const Text('Net'), subtitle: Text(s.money(inflow - outflow)))),
                      ]),
                    ),
                    const Divider(height: 1),
                    if (list.isEmpty) const EmptyHint('No transactions in this period.'),
                    for (final t in list) TxnTile(txn: t, showDate: true, forAccountId: acc.id),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key, this.account});

  final Account? account;

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  late final _name = TextEditingController(text: widget.account?.name);
  late final _initial = TextEditingController(
    text: widget.account == null ? '' : moneyToInput(widget.account!.initialBalance),
  );
  late String _group = widget.account?.group ?? 'Bank Accounts';
  late bool _investment = widget.account?.isInvestment ?? false;
  late bool _hidden = widget.account?.hidden ?? false;

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name.')));
      return;
    }
    final s = context.read<AppState>();
    final base = widget.account ?? Account(name: name, sort: s.accounts.length);
    await s.db.saveAccount(base.copyWith(
      name: name,
      group: _group,
      isInvestment: _investment,
      initialBalance: parseMoney(_initial.text) ?? 0,
      hidden: _hidden,
    ));
    await s.changed();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${widget.account!.name}?'),
        content: const Text('All transactions of this account will be deleted too. Consider hiding it instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<AppState>();
    await s.db.deleteAccount(widget.account!.id!);
    await s.changed();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final groups = [...accountGroups, if (!accountGroups.contains(_group)) _group];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account == null ? 'New account' : 'Edit account'),
        actions: [
          if (widget.account != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _group,
            decoration: const InputDecoration(labelText: 'Group'),
            items: [for (final g in groups) DropdownMenuItem(value: g, child: Text(g))],
            onChanged: (v) => setState(() {
              _group = v!;
              if (v == 'Investments') _investment = true;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _initial,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Opening balance'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Investment account'),
            subtitle: const Text('Transfers into this account count as investments in Stats.'),
            value: _investment,
            onChanged: (v) => setState(() => _investment = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide in pickers'),
            value: _hidden,
            onChanged: (v) => setState(() => _hidden = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
