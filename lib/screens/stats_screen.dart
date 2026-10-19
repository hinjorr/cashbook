import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/period.dart';
import '../logic/stats.dart';
import '../widgets/common.dart';
import '../widgets/labeled_pie.dart';
import 'accounts_screen.dart';
import 'category_detail_screen.dart';

const _statKinds = [PeriodKind.weekly, PeriodKind.monthly, PeriodKind.yearly, PeriodKind.all, PeriodKind.custom];

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsData {
  final List<Txn> txns;
  final Map<int, int> balances;

  const _StatsData(this.txns, this.balances);
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, initialIndex: 1, vsync: this);
  Period _period = Period.of(PeriodKind.monthly, DateTime.now());

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: Column(
        children: [
          PeriodBar(period: _period, kinds: _statKinds, onChanged: (p) => setState(() => _period = p)),
          Expanded(
            child: Reloading<_StatsData>(
              deps: [_period],
              load: () async => _StatsData(
                await s.db.txnsBetween(_period.start, _period.end),
                await s.db.balances(),
              ),
              builder: (context, data) {
                final tot = totalsOf(data.txns);
                final inv = investmentSummary(
                  data.txns,
                  s.accountById,
                  _period,
                  firstDate: data.txns.isEmpty ? null : data.txns.last.date,
                  lastDate: data.txns.isEmpty ? null : data.txns.first.date,
                );
                return Column(
                  children: [
                    TabBar(
                      controller: _tabs,
                      labelPadding: EdgeInsets.zero,
                      tabs: [
                        _tabLabel('Income', s.money(tot.income)),
                        _tabLabel('Expenses', s.money(tot.expense)),
                        _tabLabel('Invested', s.money(inv.net)),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _CategoryStats(type: TxnType.income, txns: data.txns, period: _period),
                          _CategoryStats(type: TxnType.expense, txns: data.txns, period: _period),
                          _InvestmentStats(summary: inv, balances: data.balances, txns: data.txns),
                        ],
                      ),
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

  Widget _tabLabel(String title, String amount) => Tab(
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title),
            FittedBox(child: Text(amount, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _CategoryStats extends StatelessWidget {
  const _CategoryStats({required this.type, required this.txns, required this.period});

  final TxnType type;
  final List<Txn> txns;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final totals = categoryTotals(txns, type, s.categoryById);
    final sum = totals.fold<int>(0, (a, c) => a + c.amount);
    if (sum == 0) return EmptyHint('No ${type == TxnType.income ? 'income' : 'expenses'} in this period.');

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          child: LabeledPie(slices: [
            for (var i = 0; i < totals.length; i++)
              PieSlice(
                totals[i].category?.name ?? 'Uncategorized',
                totals[i].amount.toDouble(),
                chartColors[i % chartColors.length],
              ),
          ]),
        ),
        const Divider(height: 1),
        for (var i = 0; i < totals.length; i++)
          ListTile(
            leading: _PercentBadge(percent: totals[i].amount / sum, color: chartColors[i % chartColors.length]),
            title: Text(totals[i].category?.name ?? 'Uncategorized'),
            trailing: Text(s.money(totals[i].amount)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CategoryDetailScreen(
                category: totals[i].category,
                type: type,
                period: period,
              ),
            )),
          ),
      ],
    );
  }
}

class _InvestmentStats extends StatelessWidget {
  const _InvestmentStats({required this.summary, required this.balances, required this.txns});

  final InvestmentSummary summary;
  final Map<int, int> balances;
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final invAccounts = s.accounts.where((a) => a.isInvestment).toList();
    if (invAccounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.trending_up, size: 48, color: investColor),
            const SizedBox(height: 12),
            const Text(
              'Put the accounts you invest into (stocks, funds, gold…) in the Investments group. '
              'Transfers into them will then show up here as investments.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountsScreen())),
              child: const Text('Open accounts'),
            ),
          ],
        ),
      );
    }

    final holdings = invAccounts.fold<int>(0, (a, acc) => a + (balances[acc.id] ?? 0));
    final invTxns = txns.where((t) {
      if (t.type != TxnType.transfer) return false;
      final a = s.accountById[t.accountId]?.isInvestment ?? false;
      final b = s.accountById[t.toAccountId]?.isInvestment ?? false;
      return a != b;
    }).toList();

    Widget stat(String label, int v, Color? c) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  FittedBox(child: Text(s.money(v), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c))),
                ],
              ),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        Row(children: [
          stat('Invested', summary.invested, investColor),
          stat('Withdrawn', summary.withdrawn, expenseColor),
        ]),
        Row(children: [
          stat('Net invested', summary.net, null),
          stat('Returns / income', summary.returns, incomeColor),
        ]),
        Card(
          child: ListTile(
            leading: const Icon(Icons.savings_outlined, color: investColor),
            title: const Text('Current holdings'),
            subtitle: Text('Balance of ${invAccounts.length} investment account${invAccounts.length == 1 ? '' : 's'}, all time'),
            trailing: Text(s.money(holdings), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        if (summary.buckets.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text('Investments over time', style: Theme.of(context).textTheme.titleSmall),
          ),
          SizedBox(height: 220, child: _InvestBars(buckets: summary.buckets)),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              _Legend(color: investColor, label: 'Invested'),
              SizedBox(width: 16),
              _Legend(color: expenseColor, label: 'Withdrawn'),
            ]),
          ),
        ],
        if (summary.byAccount.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
            child: Text('By account', style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final f in summary.byAccount)
            Card(
              child: ListTile(
                title: Text(f.account.name),
                subtitle: Text([
                  'In ${s.money(f.invested)}',
                  if (f.withdrawn > 0) 'Out ${s.money(f.withdrawn)}',
                  if (f.returns > 0) 'Returns ${s.money(f.returns)}',
                ].join(' · ')),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(s.money(f.net, showSign: true), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Bal ${s.money(balances[f.account.id] ?? 0)}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
          child: Text('Investment transfers (${invTxns.length})', style: Theme.of(context).textTheme.titleSmall),
        ),
        if (invTxns.isEmpty) const EmptyHint('No transfers into or out of investment accounts in this period.'),
        for (final t in invTxns) TxnTile(txn: t, showDate: true),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _InvestBars extends StatelessWidget {
  const _InvestBars({required this.buckets});

  final List<InvestmentBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final maxV = buckets.fold<int>(0, (m, b) => math.max(m, math.max(b.invested, b.withdrawn)));
    final top = maxV == 0 ? 1.0 : maxV / 100 * 1.15;
    final labelEvery = (buckets.length / 8).ceil();
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: BarChart(
        BarChartData(
          maxY: top,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                '${buckets[group.x].label}\n${rodIndex == 0 ? 'In' : 'Out'} ${s.money((rod.toY * 100).round())}',
                const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(NumberFormat.compact().format(v), style: const TextStyle(fontSize: 10)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i % labelEvery != 0 || i >= buckets.length) return const SizedBox.shrink();
                  return SideTitleWidget(meta: meta, child: Text(buckets[i].label, style: const TextStyle(fontSize: 10)));
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(x: i, barsSpace: 2, barRods: [
                BarChartRodData(toY: buckets[i].invested / 100, color: investColor, width: buckets.length > 12 ? 4 : 8),
                BarChartRodData(toY: buckets[i].withdrawn / 100, color: expenseColor, width: buckets.length > 12 ? 4 : 8),
              ]),
          ],
        ),
      ),
    );
  }
}

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: Text('${(percent * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      );
}
