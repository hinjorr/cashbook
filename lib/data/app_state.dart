import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/money.dart';
import '../logic/period.dart' as period;
import 'database.dart';
import 'models.dart';

/// Holds the database plus cached accounts/categories, and notifies listeners
/// whenever data changes so screens can reload.
class AppState extends ChangeNotifier {
  AppState(this.db, this.prefs);

  final AppDatabase db;
  final SharedPreferences prefs;

  List<Account> accounts = [];
  List<Category> categories = [];
  Map<int, Account> accountById = {};
  Map<int, Category> categoryById = {};

  /// Bumped on every change; screens use it as a reload key.
  int revision = 0;

  String get currency => prefs.getString('currency') ?? 'Rs';

  Future<void> setCurrency(String v) async {
    await prefs.setString('currency', v.trim());
    notifyListeners();
  }

  int get monthStartDay => prefs.getInt('month_start') ?? 1;

  Future<void> setMonthStartDay(int day) async {
    await prefs.setInt('month_start', day);
    period.monthStartDay = day;
    await changed();
  }

  String money(int minor, {bool showSign = false}) =>
      formatMoney(minor, symbol: currency, showSign: showSign);

  Future<void> load() async {
    period.monthStartDay = monthStartDay;
    accounts = await db.accounts();
    categories = await db.categories();
    accountById = {for (final a in accounts) a.id!: a};
    categoryById = {for (final c in categories) c.id!: c};
  }

  /// Call after any write so caches refresh and screens rebuild.
  Future<void> changed() async {
    await load();
    revision++;
    notifyListeners();
  }

  List<Category> topCategories(TxnType type) =>
      categories.where((c) => c.type == type && c.parentId == null).toList();

  List<Category> subcategories(int parentId) =>
      categories.where((c) => c.parentId == parentId).toList();

  String categoryLabel(int? id) {
    final c = categoryById[id];
    if (c == null) return 'Uncategorized';
    final parent = categoryById[c.parentId];
    return parent == null ? c.name : '${parent.name} / ${c.name}';
  }

  String accountName(int? id) => accountById[id]?.name ?? '—';
}
