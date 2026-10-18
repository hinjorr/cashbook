import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/period.dart';
import '../logic/stats.dart';
import '../widgets/common.dart';
import 'edit_transaction_screen.dart';
import 'search_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
  DateTime _anchor = DateTime.now();

  Period get _period => switch (_tabs.index) {
        0 => Period.of(PeriodKind.monthly, _anchor),
        // The calendar grid always shows a whole calendar month.
        1 => Period.of(PeriodKind.monthly, _anchor, startDay: 1),
        _ => Period.of(PeriodKind.yearly, _anchor),
      };

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _add([DateTime? date]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditTransactionScreen(initialDate: date),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final period = _period;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Daily'), Tab(text: 'Calendar'), Tab(text: 'Monthly')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          PeriodBar(
            period: period,
            onChanged: (p) => setState(() {
              _anchor = _tabs.index == 1 ? DateTime(p.start.year, p.start.month, monthStartDay) : p.start;
            }),
          ),
          Expanded(
            child: Reloading<List<Txn>>(
              deps: [period],
              load: () => s.db.txnsBetween(period.start, period.end),
              builder: (context, txns) {
                final totals = totalsOf(txns);
                return Column(
                  children: [
                    TotalsStrip(income: totals.income, expense: totals.expense),
                    const Divider(height: 1),
                    Expanded(
                      child: switch (_tabs.index) {
                        0 => _DailyList(txns: txns),
                        1 => _CalendarView(month: period.start, txns: txns, onAdd: _add),
                        _ => _MonthlyList(year: period.start.year, txns: txns),
                      },
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

class _DailyList extends StatelessWidget {
  const _DailyList({required this.txns});

  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) return const EmptyHint('No transactions this month.\nTap + to add one.');
    final s = context.watch<AppState>();
    final days = <DateTime, List<Txn>>{};
    for (final t in txns) {
      days.putIfAbsent(DateTime(t.date.year, t.date.month, t.date.day), () => []).add(t);
    }
    final keys = days.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final day = keys[i];
        final list = days[day]!;
        final tot = totalsOf(list);
        return Card(
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Text('${day.day}', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: 8),
                    Text(DateFormat('EEE, MMM yyyy').format(day), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(children: [
                            if (tot.income > 0) Text(s.money(tot.income), style: const TextStyle(color: incomeColor)),
                            const SizedBox(width: 12),
                            if (tot.expense > 0) Text(s.money(tot.expense), style: const TextStyle(color: expenseColor)),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final t in list) TxnTile(txn: t),
            ],
          ),
        );
      },
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({required this.month, required this.txns, required this.onAdd});

  final DateTime month;
  final List<Txn> txns;
  final void Function(DateTime) onAdd;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final cells = ((lead + daysInMonth + 6) ~/ 7) * 7;
    final byDay = <int, Totals>{};
    for (var d = 1; d <= daysInMonth; d++) {
      byDay[d] = totalsOf(txns.where((t) => t.date.day == d));
    }
    final today = DateTime.now();
    String short(int v) => NumberFormat.compact().format(v / 100);

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Row(
          children: [
            for (final w in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
              Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(6), child: Text(w, style: Theme.of(context).textTheme.bodySmall)))),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.72),
          itemBuilder: (context, i) {
            final d = i - lead + 1;
            if (d < 1 || d > daysInMonth) return const SizedBox();
            final tot = byDay[d]!;
            final date = DateTime(month.year, month.month, d);
            final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
            return InkWell(
              onTap: () => _showDay(context, date),
              onLongPress: () => onAdd(date),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4), width: 0.5),
                  color: isToday ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$d', style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    if (tot.income > 0)
                      FittedBox(child: Text(short(tot.income), style: const TextStyle(color: incomeColor, fontSize: 11))),
                    if (tot.expense > 0)
                      FittedBox(child: Text(short(tot.expense), style: const TextStyle(color: expenseColor, fontSize: 11))),
                  ],
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Tap a day to see its entries, long-press to add one. ${s.currency} amounts are shortened.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }

  void _showDay(BuildContext context, DateTime day) {
    final list = txns.where((t) => t.date.day == day.day).toList();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(DateFormat('EEEE, d MMMM yyyy').format(day)),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.pop(context);
                  onAdd(day);
                },
              ),
            ),
            if (list.isEmpty) const EmptyHint('No entries.'),
            for (final t in list) TxnTile(txn: t),
          ],
        ),
      ),
    );
  }
}

class _MonthlyList extends StatelessWidget {
  const _MonthlyList({required this.year, required this.txns});

  final int year;
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (var m = 12; m >= 1; m--)
          Builder(builder: (context) {
            final tot = totalsOf(txns.where((t) => t.date.month == m));
            if (tot.income == 0 && tot.expense == 0) return const SizedBox.shrink();
            return ListTile(
              title: Text(DateFormat('MMMM').format(DateTime(year, m))),
              subtitle: Text('Total ${s.money(tot.net)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(s.money(tot.income), style: const TextStyle(color: incomeColor)),
                  Text(s.money(tot.expense), style: const TextStyle(color: expenseColor)),
                ],
              ),
            );
          }),
      ],
    );
  }
}
