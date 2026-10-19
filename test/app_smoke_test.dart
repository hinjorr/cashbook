import 'dart:io';

import 'package:cashbook/data/app_state.dart';
import 'package:cashbook/data/database.dart';
import 'package:cashbook/main.dart';
import 'package:cashbook/services/money_manager_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('main screens render with imported data', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();

    late AppState state;
    await tester.runAsync(() async {
      final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
      final bytes = File('test/fixtures/money_manager_export.xlsx').readAsBytesSync();
      await applyMoneyManagerImport(db, parseMoneyManagerExport(bytes), replaceExisting: true);
      state = AppState(db, await SharedPreferences.getInstance());
      await state.load();
    });

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(CashbookApp(state: state));
    await settle();
    expect(find.text('Transactions'), findsOneWidget);

    // Stats › Invested tab.
    await tester.tap(find.text('Stats'));
    await settle();
    expect(find.text('Expenses'), findsWidgets);
    await tester.tap(find.text('Invested').first);
    await tester.pumpAndSettle();
    await settle();
    expect(find.text('Net invested'), findsOneWidget);
    expect(find.text('Current holdings'), findsOneWidget);

    // Accounts.
    await tester.tap(find.text('Accounts'));
    await settle();
    expect(find.text('Investments'), findsOneWidget);
    expect(find.text('Stocks'), findsOneWidget);

    // More › Import screen opens.
    await tester.tap(find.text('More'));
    await settle();
    await tester.tap(find.text('Import from Money Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Choose export file'), findsOneWidget);

    await tester.runAsync(() => state.db.close());
  });
}
