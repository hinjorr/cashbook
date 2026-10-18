import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/period.dart';
import '../screens/edit_transaction_screen.dart';

const incomeColor = Color(0xFF2F80ED);
const expenseColor = Color(0xFFF2675A);
const transferColor = Color(0xFF8E8E93);
const investColor = Color(0xFF27AE60);

/// Chart palette, close to Money Manager's warm-to-cool ordering.
const chartColors = [
  Color(0xFFF2675A),
  Color(0xFFFA9A4B),
  Color(0xFFFFCC4D),
  Color(0xFFF5E663),
  Color(0xFFBFE04A),
  Color(0xFF6CCB7A),
  Color(0xFF4DB6AC),
  Color(0xFF4FA3E0),
  Color(0xFF7E86E6),
  Color(0xFFB57EDC),
  Color(0xFFE77FB3),
  Color(0xFFA1887F),
];

Color colorFor(TxnType t) => switch (t) {
      TxnType.income => incomeColor,
      TxnType.expense => expenseColor,
      TxnType.transfer => transferColor,
    };

/// "‹ Oct 2026 ›" header with an optional period-kind dropdown.
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.period,
    required this.onChanged,
    this.kinds,
  });

  final Period period;
  final ValueChanged<Period> onChanged;

  /// Kinds offered in the dropdown; when null the dropdown is hidden.
  final List<PeriodKind>? kinds;

  Future<void> _pickKind(BuildContext context, PeriodKind k) async {
    if (k == PeriodKind.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(
          start: period.start,
          end: period.end.subtract(const Duration(days: 1)),
        ),
      );
      if (range != null) onChanged(Period.custom(range.start, range.end));
      return;
    }
    onChanged(Period.of(k, period.kind == PeriodKind.all ? DateTime.now() : period.start));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: period.canStep ? () => onChanged(period.step(-1)) : null,
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(period.label, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: period.canStep ? () => onChanged(period.step(1)) : null,
          ),
          const Spacer(),
          if (kinds != null)
            PopupMenuButton<PeriodKind>(
              onSelected: (k) => _pickKind(context, k),
              itemBuilder: (_) => [
                for (final k in kinds!) PopupMenuItem(value: k, child: Text(k.label)),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(period.kind.label), const Icon(Icons.expand_more, size: 18)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Income / Expenses / Total strip.
class TotalsStrip extends StatelessWidget {
  const TotalsStrip({super.key, required this.income, required this.expense});

  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget cell(String label, int v, Color? c) => Expanded(
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(s.money(v), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          cell('Income', income, incomeColor),
          cell('Expenses', expense, expenseColor),
          cell('Total', income - expense, null),
        ],
      ),
    );
  }
}

/// A single transaction row. Tapping opens the editor.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, this.showDate = false, this.forAccountId});

  final Txn txn;
  final bool showDate;

  /// When shown inside an account, transfers display as in/out of that account.
  final int? forAccountId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = txn;
    final isTransfer = t.type == TxnType.transfer;
    final toInv = isTransfer && (s.accountById[t.toAccountId]?.isInvestment ?? false) &&
        !(s.accountById[t.accountId]?.isInvestment ?? false);
    final title = isTransfer ? (toInv ? 'Investment' : 'Transfer') : s.categoryLabel(t.categoryId);
    final subtitle = isTransfer
        ? '${s.accountName(t.accountId)} → ${s.accountName(t.toAccountId)}'
        : s.accountName(t.accountId);
    var color = toInv ? investColor : colorFor(t.type);
    if (forAccountId != null && isTransfer) {
      color = t.toAccountId == forAccountId ? incomeColor : expenseColor;
    }
    final extra = [
      if (showDate) DateFormat('d MMM yyyy').format(t.date),
      if (t.note.isNotEmpty) t.note,
    ].join(' · ');

    return ListTile(
      dense: true,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        extra.isEmpty ? subtitle : '$extra\n$subtitle',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: extra.isNotEmpty,
      trailing: Text(
        s.money(t.amount),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditTransactionScreen(txn: t)),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
        ),
      );
}

/// Loads data with [load] and rebuilds whenever AppState changes or [deps] change.
class Reloading<T> extends StatefulWidget {
  const Reloading({super.key, required this.load, required this.builder, this.deps = const []});

  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final List<Object?> deps;

  @override
  State<Reloading<T>> createState() => _ReloadingState<T>();
}

class _ReloadingState<T> extends State<Reloading<T>> {
  Future<T>? _future;
  int _rev = -1;
  List<Object?> _deps = const [];
  T? _last;

  @override
  Widget build(BuildContext context) {
    final rev = context.watch<AppState>().revision;
    if (_future == null || rev != _rev || !_sameDeps(widget.deps)) {
      _rev = rev;
      _deps = List.of(widget.deps);
      _future = widget.load();
    }
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return EmptyHint('Error: ${snap.error}');
        if (snap.hasData) _last = snap.data;
        final data = snap.data ?? _last;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, data as T);
      },
    );
  }

  bool _sameDeps(List<Object?> d) {
    if (d.length != _deps.length) return false;
    for (var i = 0; i < d.length; i++) {
      if (d[i] != _deps[i]) return false;
    }
    return true;
  }
}
