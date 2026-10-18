import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(tabs: [Tab(text: 'Income'), Tab(text: 'Expense')]),
        ),
        body: const TabBarView(children: [
          _CategoryList(type: TxnType.income),
          _CategoryList(type: TxnType.expense),
        ]),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.type});

  final TxnType type;

  Future<String?> _askName(BuildContext context, String title, [String initial = '']) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, Category c) async {
    final s = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          if (c.parentId == null)
            ListTile(leading: const Icon(Icons.add), title: const Text('Add subcategory'), onTap: () => Navigator.pop(ctx, 'sub')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        final n = await _askName(context, 'Rename', c.name);
        if (n != null && n.isNotEmpty) {
          await s.db.saveCategory(Category(id: c.id, name: n, type: c.type, parentId: c.parentId, sort: c.sort));
        }
      case 'sub':
        final n = await _askName(context, 'New subcategory of ${c.name}');
        if (n != null && n.isNotEmpty) {
          await s.db.saveCategory(Category(name: n, type: c.type, parentId: c.id, sort: s.categories.length));
        }
      case 'delete':
        await s.db.deleteCategory(c.id!);
    }
    await s.changed();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final top = s.topCategories(type);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'cat-${type.name}',
        onPressed: () async {
          final n = await _askName(context, 'New category');
          if (n == null || n.isEmpty) return;
          await s.db.saveCategory(Category(name: n, type: type, sort: s.categories.length));
          await s.changed();
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final c in top) ...[
            ListTile(title: Text(c.name), trailing: const Icon(Icons.more_vert), onTap: () => _menu(context, c)),
            for (final sub in s.subcategories(c.id!))
              ListTile(
                contentPadding: const EdgeInsets.only(left: 40, right: 16),
                dense: true,
                title: Text(sub.name),
                onTap: () => _menu(context, sub),
              ),
          ],
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Deleting a category keeps its transactions as "Uncategorized".'),
          ),
        ],
      ),
    );
  }
}
