import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import 'backup_screen.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';
import 'import_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _editCurrency(BuildContext context) async {
    final s = context.read<AppState>();
    final c = TextEditingController(text: s.currency);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Currency symbol'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) await s.setCurrency(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Backup & restore'),
            subtitle: const Text('Google Drive, or a backup file'),
            onTap: () => _open(context, const BackupScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import from Money Manager'),
            subtitle: const Text('Excel export from Realbyte Money Manager'),
            onTap: () => _open(context, const ImportScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            onTap: () => _open(context, const CategoriesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.pie_chart_outline),
            title: const Text('Budgets'),
            onTap: () => _open(context, const BudgetScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Currency symbol'),
            trailing: Text(s.currency),
            onTap: () => _editCurrency(context),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Month starts on day'),
            subtitle: const Text('E.g. your salary day; monthly views run from this day'),
            trailing: DropdownButton<int>(
              value: s.monthStartDay,
              underline: const SizedBox(),
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (d) => s.setMonthStartDay(d!),
            ),
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Cashbook',
            aboutBoxChildren: [Text('Personal finance tracker with investment stats.')],
          ),
        ],
      ),
    );
  }
}
