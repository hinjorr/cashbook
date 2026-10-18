import 'dart:convert';
import 'dart:io';

import 'package:cashbook/data/database.dart';
import 'package:cashbook/data/models.dart';
import 'package:cashbook/logic/period.dart';
import 'package:cashbook/logic/stats.dart';
import 'package:cashbook/services/money_manager_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppDatabase> memoryDb() {
  sqfliteFfiInit();
  return AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
}

void main() {
  final fixture = File('test/fixtures/money_manager_export.xlsx').readAsBytesSync();

  group('Money Manager parser', () {
    test('reads the tab-separated export with Excel serial dates', () {
      final r = parseMoneyManagerExport(fixture);
      expect(r.warnings, isEmpty);
      expect(r.rows, hasLength(8));

      final first = r.rows.first;
      expect(first.date, DateTime(2026, 10, 18, 23, 24, 10));
      expect(first.account, 'Daily');
      expect(first.category, 'Transport🚕');
      expect(first.kind, MmKind.expense);
      expect(first.amount, 450000);

      final food = r.rows[1];
      expect(food.subcategory, 'Lunch');
      expect(food.note, 'burgers');
      expect(food.amount, 247050);

      expect(r.rows[2].kind, MmKind.transferOut);
      expect(r.rows[2].category, 'Stocks');
    });

    test('reads comma-separated text too', () {
      const csv = 'Date,Account,Category,Subcategory,Note,PKR,Income/Expense,Description,Amount,Currency,Account\n'
          '10/18/2026 09:30:00,Cash,"Food, drinks",,tea,"1,200.00",Exp.,,1200,PKR,1200\n';
      final r = parseMoneyManagerExport(utf8.encode(csv));
      expect(r.rows.single.date, DateTime(2026, 10, 18, 9, 30));
      expect(r.rows.single.category, 'Food, drinks');
      expect(r.rows.single.amount, 120000);
      expect(r.rows.single.kind, MmKind.expense);
    });

    test('rejects files without the Income/Expense column', () {
      expect(() => parseMoneyManagerExport(utf8.encode('a\tb\n1\t2\n')), throwsFormatException);
    });
  });

  group('import + investment stats', () {
    late AppDatabase db;

    setUp(() async {
      db = await memoryDb();
      await applyMoneyManagerImport(db, parseMoneyManagerExport(fixture), replaceExisting: true);
    });

    tearDown(() => db.close());

    test('creates accounts, flags investment accounts, keeps transfer direction', () async {
      final accounts = {for (final a in await db.accounts()) a.name: a};
      expect(accounts.keys, containsAll(['Daily', 'Salary', 'Stocks', 'Savings Fund']));
      expect(accounts['Stocks']!.isInvestment, isTrue);
      expect(accounts['Savings Fund']!.isInvestment, isTrue);
      expect(accounts['Daily']!.isInvestment, isFalse);

      final bal = await db.balances();
      // 237928 income - 2470.5 food - 25000 - 1400 - 70000 - 25000 out + 5000 back
      expect(bal[accounts['Salary']!.id], 11905750);
      expect(bal[accounts['Stocks']!.id], 4500000);
      expect(bal[accounts['Daily']!.id], 140000 - 450000);

      final cats = await db.categories();
      final lunch = cats.firstWhere((c) => c.name == 'Lunch');
      expect(cats.firstWhere((c) => c.id == lunch.parentId).name, 'Food🍔');
    });

    test('importing the same file again skips duplicates', () async {
      final again = await applyMoneyManagerImport(db, parseMoneyManagerExport(fixture));
      expect(again.imported, 0);
      expect(again.duplicates, 8);
    });

    test('monthly and yearly invested totals', () async {
      final accounts = {for (final a in await db.accounts()) a.id!: a};
      final oct = Period.of(PeriodKind.monthly, DateTime(2026, 10, 1));
      final s = investmentSummary(await db.txnsBetween(oct.start, oct.end), accounts, oct);
      expect(s.invested, 9500000);
      expect(s.withdrawn, 500000);
      expect(s.net, 9000000);
      expect(s.buckets.fold<int>(0, (a, b) => a + b.invested), 9500000);

      final year = Period.of(PeriodKind.yearly, DateTime(2026));
      final y = investmentSummary(await db.txnsBetween(year.start, year.end), accounts, year);
      expect(y.invested, 12000000);
      expect(y.buckets, hasLength(12));
      expect(y.buckets[8].invested, 2500000); // September
      expect(y.buckets[9].invested, 9500000); // October
      expect(y.byAccount.map((f) => f.account.name), containsAll(['Stocks', 'Savings Fund']));

      // Transfers are not income or expense.
      final t = totalsOf(await db.txnsBetween(oct.start, oct.end));
      expect(t.income, 23792800);
      expect(t.expense, 450000 + 247050);
    });

    test('backup export/import round-trips everything', () async {
      final dump = jsonDecode(jsonEncode(await db.exportData())) as Map<String, Object?>;
      final other = await memoryDb();
      await other.importData(dump);
      expect((await other.allTxns()).length, 8);
      expect(await other.balances(), await db.balances());
      await other.close();
    });
  });

  test('categoryTotals rolls subcategories into parents', () {
    const food = Category(id: 1, name: 'Food', type: TxnType.expense);
    const lunch = Category(id: 2, name: 'Lunch', type: TxnType.expense, parentId: 1);
    final txns = [
      Txn(type: TxnType.expense, date: DateTime(2026), amount: 100, accountId: 1, categoryId: 1),
      Txn(type: TxnType.expense, date: DateTime(2026), amount: 50, accountId: 1, categoryId: 2),
      Txn(type: TxnType.expense, date: DateTime(2026), amount: 30, accountId: 1),
    ];
    final r = categoryTotals(txns, TxnType.expense, {1: food, 2: lunch});
    expect(r.first.category?.name, 'Food');
    expect(r.first.amount, 150);
    expect(r.last.category, isNull);
  });

  test('period stepping', () {
    final p = Period.of(PeriodKind.monthly, DateTime(2026, 12, 15));
    expect(p.step(1).start, DateTime(2027, 1));
    expect(Period.of(PeriodKind.weekly, DateTime(2026, 10, 18)).start, DateTime(2026, 10, 12));
  });

  test('custom month start day', () {
    monthStartDay = 5;
    addTearDown(() => monthStartDay = 1);
    final p = Period.of(PeriodKind.monthly, DateTime(2026, 10, 3));
    expect(p.start, DateTime(2026, 9, 5));
    expect(p.end, DateTime(2026, 10, 5));
    expect(p.step(1).start, DateTime(2026, 10, 5));
    expect(p.step(-1).start, DateTime(2026, 8, 5));
    expect(Period.of(PeriodKind.monthly, DateTime(2026, 10, 3), startDay: 1).start, DateTime(2026, 10, 1));
    final weeks = bucketsFor(Period.of(PeriodKind.monthly, DateTime(2026, 10, 5)));
    expect(weeks.first.start, DateTime(2026, 10, 5));
    expect(weeks.last.end, DateTime(2026, 11, 5));
  });
}
