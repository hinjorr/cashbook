import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../logic/period.dart';
import '../widgets/common.dart';

final _dayFmt = DateFormat('EEE, d MMM yyyy');

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Asks for the day the new month starts (default today) and closes the
/// month [current]. Returns the new month's first day, or null if cancelled.
Future<DateTime?> closeMonthFlow(BuildContext context, Period current) async {
  final s = context.read<AppState>();
  final first = current.start.add(const Duration(days: 1));
  var day = _today();
  if (day.isBefore(first)) day = first;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final lastDay = day.subtract(const Duration(days: 1));
        final days = lastDay.difference(current.start).inDays + 1;
        return AlertDialog(
          title: Text('Close ${current.label}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A new month starts on'),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_dayFmt.format(day)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: day,
                    firstDate: first,
                    lastDate: _today().add(const Duration(days: 31)),
                  );
                  if (picked != null) setState(() => day = picked);
                },
              ),
              const SizedBox(height: 12),
              Text(
                '${current.label} will run ${DateFormat('d MMM').format(current.start)} – '
                '${DateFormat('d MMM').format(lastDay)} ($days days). '
                'Entries dated from ${DateFormat('d MMM').format(day)} go into the new month.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'You can reopen it or change the date later under More › Month closing.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close month')),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  await s.closeMonth(day);
  return day;
}

/// Lists every closing date, with options to reopen a month, move its
/// closing date, or add closing dates for past months.
class MonthClosingScreen extends StatelessWidget {
  const MonthClosingScreen({super.key});

  Future<void> _addPast(BuildContext context) async {
    final s = context.read<AppState>();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Day a past month started (salary day)',
      initialDate: _today(),
      firstDate: DateTime(2000),
      lastDate: _today().add(const Duration(days: 31)),
    );
    if (picked != null) await s.closeMonth(picked);
  }

  Future<void> _actions(BuildContext context, DateTime close) async {
    final s = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_calendar),
            title: const Text('Change date'),
            onTap: () => Navigator.pop(ctx, 'move'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_open),
            title: const Text('Reopen'),
            subtitle: const Text('Joins this month onto the one before it'),
            onTap: () => Navigator.pop(ctx, 'reopen'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (action == 'reopen') {
      await s.reopenMonth(close);
    } else if (action == 'move') {
      final i = monthCloses.indexOf(close);
      final before = i > 0 ? monthCloses[i - 1].add(const Duration(days: 1)) : DateTime(2000);
      final after = i + 1 < monthCloses.length
          ? monthCloses[i + 1].subtract(const Duration(days: 1))
          : _today().add(const Duration(days: 31));
      final picked = await showDatePicker(
        context: context,
        initialDate: close,
        firstDate: before,
        lastDate: after,
      );
      if (picked != null && picked != close) await s.moveMonthClose(close, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final closes = monthCloses.reversed.toList();
    final current = Period.of(PeriodKind.monthly, DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Month closing')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _addPast(context),
        icon: const Icon(Icons.history),
        label: const Text('Add past closing'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Close a month on the day your salary arrives; a new month starts that day. '
              'Months can be any length. Reopening a month joins it onto the one before.',
            ),
          ),
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: Text('Current month: ${current.label}'),
              subtitle: Text(current.range ?? current.label),
              trailing: FilledButton.tonal(
                onPressed: () => closeMonthFlow(context, current),
                child: const Text('Close month'),
              ),
            ),
          ),
          if (closes.isEmpty)
            const EmptyHint('No months closed yet.\nUse "Add past closing" to line up earlier months with your salary days.'),
          for (final c in closes)
            Builder(builder: (context) {
              // The month that ended at this close.
              final ended = Period.of(PeriodKind.monthly, c.subtract(const Duration(days: 1)));
              return ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text('New month from ${_dayFmt.format(c)}'),
                subtitle: Text('Closed ${ended.label}: ${ended.range ?? ''}'),
                trailing: const Icon(Icons.more_vert),
                onTap: () => _actions(context, c),
              );
            }),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Before your first closing'),
            subtitle: const Text('Months start on this day of the month'),
            trailing: DropdownButton<int>(
              value: s.monthStartDay,
              underline: const SizedBox(),
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (d) => s.setMonthStartDay(d!),
            ),
          ),
        ],
      ),
    );
  }
}
