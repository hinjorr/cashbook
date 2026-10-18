import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/money.dart';
import '../logic/period.dart';
import '../logic/stats.dart';
import '../widgets/common.dart';

class _BudgetData {
  final Map<int, int> budgets;
  final List<Txn> txns;

  const _BudgetData(this.budgets, this.txns);
}

/// Monthly budget per expense category, with spending progress.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  Period _period = Period.of(PeriodKind.monthly, DateTime.now());

  Future<void> _edit(Category c, int? current) async {
    final s = context.read<AppState>();
    final ctl = TextEditingController(text: current == null ? '' : moneyToInput(current));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Monthly budget: ${c.name}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: '${s.currency} ', helperText: 'Leave empty to remove'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return;
    await s.db.setBudget(c.id!, parseMoney(v));
    await s.changed();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: Column(
        children: [
          PeriodBar(period: _period, onChanged: (p) => setState(() => _period = p)),
          Expanded(
            child: Reloading<_BudgetData>(
              deps: [_period],
              load: () async => _BudgetData(await s.db.budgets(), await s.db.txnsBetween(_period.start, _period.end)),
              builder: (context, d) {
                final spent = {
                  for (final t in categoryTotals(d.txns, TxnType.expense, s.categoryById))
                    if (t.category != null) t.category!.id!: t.amount,
                };
                final cats = s.topCategories(TxnType.expense)
                  ..sort((a, b) => (d.budgets.containsKey(b.id) ? 1 : 0) - (d.budgets.containsKey(a.id) ? 1 : 0));
                final totalBudget = d.budgets.values.fold<int>(0, (a, b) => a + b);
                final totalSpent = d.budgets.keys.fold<int>(0, (a, id) => a + (spent[id] ?? 0));
                return ListView(
                  children: [
                    if (totalBudget > 0)
                      _BudgetTile(title: 'Total', budget: totalBudget, spent: totalSpent, bold: true),
                    for (final c in cats)
                      _BudgetTile(
                        title: c.name,
                        budget: d.budgets[c.id],
                        spent: spent[c.id] ?? 0,
                        onTap: () => _edit(c, d.budgets[c.id]),
                      ),
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

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.title, required this.budget, required this.spent, this.onTap, this.bold = false});

  final String title;
  final int? budget;
  final int spent;
  final VoidCallback? onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final b = budget;
    final ratio = b == null || b == 0 ? 0.0 : spent / b;
    return ListTile(
      onTap: onTap,
      title: Text(title, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
      subtitle: b == null
          ? Text('No budget · spent ${s.money(spent)}')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: ratio.clamp(0, 1),
                  color: ratio > 1 ? expenseColor : (ratio > 0.8 ? Colors.orange : investColor),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Text('${s.money(spent)} of ${s.money(b)} · ${b - spent >= 0 ? '${s.money(b - spent)} left' : '${s.money(spent - b)} over'}'),
              ],
            ),
    );
  }
}
