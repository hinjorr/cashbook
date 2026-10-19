import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

const _defaultExpenseCategories = [
  'Food',
  'Transport',
  'Home',
  'Bills',
  'Shopping',
  'Health',
  'Education',
  'Entertainment',
  'Subscriptions',
  'Gift',
  'Other',
];

const _defaultIncomeCategories = [
  'Salary',
  'Bonus',
  'Allowance',
  'Profit',
  'Other',
];

const _defaultAccounts = [
  Account(name: 'Cash', group: 'Cash'),
  Account(name: 'Salary', group: 'Bank Accounts', sort: 1),
  Account(
    name: 'Investments',
    group: investmentGroup,
    sort: 2,
  ),
];

/// Thin wrapper around the SQLite database.
class AppDatabase {
  AppDatabase(this.db);

  final Database db;

  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'cashbook.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: (db, from, _) async {
          // v2: the Investments group replaces the per-account switch.
          if (from < 2) {
            await db.execute("UPDATE accounts SET grp = 'Investments' WHERE is_investment = 1");
          }
        },
        onCreate: (db, _) async {
          await _createSchema(db);
          await _seed(db);
        },
      ),
    );
    return AppDatabase(db);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        grp TEXT NOT NULL DEFAULT 'Others',
        is_investment INTEGER NOT NULL DEFAULT 0,
        initial INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0,
        sort INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type INTEGER NOT NULL,
        parent_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
        sort INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE txns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type INTEGER NOT NULL,
        date INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        to_account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        note TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('CREATE INDEX txns_date ON txns(date)');
    await db.execute('''
      CREATE TABLE budgets(
        category_id INTEGER PRIMARY KEY REFERENCES categories(id) ON DELETE CASCADE,
        amount INTEGER NOT NULL
      )''');
  }

  static Future<void> _seed(DatabaseExecutor db) async {
    for (final a in _defaultAccounts) {
      await db.insert('accounts', a.toMap());
    }
    var i = 0;
    for (final n in _defaultExpenseCategories) {
      await db.insert(
        'categories',
        Category(name: n, type: TxnType.expense, sort: i++).toMap(),
      );
    }
    i = 0;
    for (final n in _defaultIncomeCategories) {
      await db.insert(
        'categories',
        Category(name: n, type: TxnType.income, sort: i++).toMap(),
      );
    }
  }

  Future<void> close() => db.close();

  // ---- Accounts ----

  Future<List<Account>> accounts() async {
    final rows = await db.query('accounts', orderBy: 'sort, id');
    return rows.map(Account.fromMap).toList();
  }

  Future<int> saveAccount(Account a) async {
    if (a.id == null) {
      final map = a.toMap()..remove('id');
      return db.insert('accounts', map);
    }
    await db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
    return a.id!;
  }

  Future<void> deleteAccount(int id) =>
      db.delete('accounts', where: 'id = ?', whereArgs: [id]);

  /// Current balance for every account, keyed by account id.
  Future<Map<int, int>> balances() async {
    final result = <int, int>{};
    for (final a in await accounts()) {
      result[a.id!] = a.initialBalance;
    }
    final rows = await db.rawQuery('''
      SELECT account_id AS acc, SUM(CASE type WHEN 0 THEN amount ELSE -amount END) AS s
        FROM txns GROUP BY account_id
      UNION ALL
      SELECT to_account_id AS acc, SUM(amount) AS s
        FROM txns WHERE type = 2 AND to_account_id IS NOT NULL GROUP BY to_account_id
    ''');
    for (final r in rows) {
      final acc = r['acc'] as int;
      result[acc] = (result[acc] ?? 0) + ((r['s'] as num?)?.toInt() ?? 0);
    }
    return result;
  }

  // ---- Categories ----

  Future<List<Category>> categories() async {
    final rows = await db.query('categories', orderBy: 'sort, id');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> saveCategory(Category c) async {
    if (c.id == null) {
      final map = c.toMap()..remove('id');
      return db.insert('categories', map);
    }
    await db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  Future<void> deleteCategory(int id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);

  // ---- Transactions ----

  Future<List<Txn>> txnsBetween(DateTime start, DateTime end) async {
    final rows = await db.query(
      'txns',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> txnsForAccount(int accountId, DateTime start, DateTime end) async {
    final rows = await db.query(
      'txns',
      where: '(account_id = ? OR to_account_id = ?) AND date >= ? AND date < ?',
      whereArgs: [
        accountId,
        accountId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> allTxns() async {
    final rows = await db.query('txns', orderBy: 'date DESC, id DESC');
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> search(String query) async {
    final like = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await db.rawQuery(r'''
      SELECT t.* FROM txns t
        LEFT JOIN categories c ON c.id = t.category_id
       WHERE t.note LIKE ? ESCAPE '\' OR t.description LIKE ? ESCAPE '\'
          OR c.name LIKE ? ESCAPE '\'
       ORDER BY t.date DESC, t.id DESC
       LIMIT 500
    ''', [like, like, like]);
    return rows.map(Txn.fromMap).toList();
  }

  Future<DateTime?> earliestTxnDate() async {
    final r = await db.rawQuery('SELECT MIN(date) AS d FROM txns');
    final d = r.first['d'] as int?;
    return d == null ? null : DateTime.fromMillisecondsSinceEpoch(d);
  }

  Future<int> saveTxn(Txn t) async {
    if (t.id == null) {
      final map = t.toMap()..remove('id');
      return db.insert('txns', map);
    }
    await db.update('txns', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    return t.id!;
  }

  Future<void> deleteTxn(int id) =>
      db.delete('txns', where: 'id = ?', whereArgs: [id]);

  // ---- Budgets ----

  Future<Map<int, int>> budgets() async {
    final rows = await db.query('budgets');
    return {for (final r in rows) r['category_id'] as int: r['amount'] as int};
  }

  Future<void> setBudget(int categoryId, int? amount) async {
    if (amount == null || amount <= 0) {
      await db.delete('budgets', where: 'category_id = ?', whereArgs: [categoryId]);
    } else {
      await db.insert(
        'budgets',
        {'category_id': categoryId, 'amount': amount},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---- Backup ----

  static const _tables = ['accounts', 'categories', 'txns', 'budgets'];

  /// Dumps every table into a JSON-serialisable map.
  Future<Map<String, Object?>> exportData() async {
    final out = <String, Object?>{
      'app': 'cashbook',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final t in _tables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  /// Replaces all data with the contents of a backup made by [exportData].
  Future<void> importData(Map<String, Object?> data) async {
    if (data['app'] != 'cashbook') {
      throw const FormatException('This is not a Cashbook backup file.');
    }
    await db.transaction((tx) async {
      // Children first, so foreign keys never dangle.
      for (final t in _tables.reversed) {
        await tx.delete(t);
      }
      // Parents before subcategories.
      final cats = List<Map<String, Object?>>.from(
        (data['categories'] as List? ?? const []).cast<Map>().map(Map<String, Object?>.from),
      )..sort((a, b) => (a['parent_id'] == null ? 0 : 1) - (b['parent_id'] == null ? 0 : 1));
      final rows = {
        'accounts': (data['accounts'] as List? ?? const []),
        'categories': cats,
        'txns': (data['txns'] as List? ?? const []),
        'budgets': (data['budgets'] as List? ?? const []),
      };
      for (final t in _tables) {
        for (final r in rows[t]!) {
          await tx.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
      // Backups from before v2 marked investments with a switch.
      await tx.execute("UPDATE accounts SET grp = 'Investments' WHERE is_investment = 1");
    });
  }

  /// Deletes every transaction, account, category and budget.
  Future<void> wipe({bool reseed = false}) async {
    await db.transaction((tx) async {
      for (final t in _tables.reversed) {
        await tx.delete(t);
      }
      if (reseed) await _seed(tx);
    });
  }
}
