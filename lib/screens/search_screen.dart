import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../widgets/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search note, description, category', border: InputBorder.none),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      body: _query.isEmpty
          ? const EmptyHint('Type to search all transactions.')
          : Reloading<List<Txn>>(
              deps: [_query],
              load: () => s.db.search(_query),
              builder: (context, list) {
                if (list.isEmpty) return const EmptyHint('No matches.');
                final tot = list.fold<int>(0, (a, t) => a + (t.type == TxnType.expense ? -t.amount : t.type == TxnType.income ? t.amount : 0));
                return ListView(
                  children: [
                    ListTile(title: Text('${list.length} results'), trailing: Text(s.money(tot))),
                    for (final t in list) TxnTile(txn: t, showDate: true),
                  ],
                );
              },
            ),
    );
  }
}
