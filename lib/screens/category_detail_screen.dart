import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/period.dart';
import '../widgets/common.dart';

class CategoryDetailScreen extends StatefulWidget {
  const CategoryDetailScreen({super.key, required this.category, required this.type, required this.period});

  /// Top-level category, or null for uncategorised.
  final Category? category;
  final TxnType type;
  final Period period;

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late Period _period = widget.period;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cat = widget.category;
    final ids = cat == null ? null : {cat.id, for (final c in s.subcategories(cat.id!)) c.id};
    bool matches(Txn t) =>
        t.type == widget.type &&
        (ids == null ? (t.categoryId == null || !s.categoryById.containsKey(t.categoryId)) : ids.contains(t.categoryId));

    return Scaffold(
      appBar: AppBar(title: Text(cat?.name ?? 'Uncategorized')),
      body: Column(
        children: [
          PeriodBar(period: _period, onChanged: (p) => setState(() => _period = p)),
          Expanded(
            child: Reloading<List<Txn>>(
              deps: [_period],
              load: () => s.db.txnsBetween(_period.start, _period.end),
              builder: (context, all) {
                final list = all.where(matches).toList();
                final total = list.fold<int>(0, (a, t) => a + t.amount);
                final subs = <int?, int>{};
                for (final t in list) {
                  final key = t.categoryId == cat?.id ? null : t.categoryId;
                  subs[key] = (subs[key] ?? 0) + t.amount;
                }
                return ListView(
                  children: [
                    ListTile(
                      title: const Text('Total'),
                      trailing: Text(s.money(total), style: TextStyle(color: colorFor(widget.type), fontWeight: FontWeight.w700)),
                    ),
                    if (subs.length > 1 || (subs.length == 1 && subs.keys.first != null))
                      for (final e in subs.entries)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.subdirectory_arrow_right, size: 18),
                          title: Text(e.key == null ? '(no subcategory)' : s.categoryById[e.key]?.name ?? '?'),
                          trailing: Text(s.money(e.value)),
                        ),
                    const Divider(),
                    if (list.isEmpty) const EmptyHint('Nothing in this period.'),
                    for (final t in list) TxnTile(txn: t, showDate: true),
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
