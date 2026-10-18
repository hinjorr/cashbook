import 'package:intl/intl.dart';

import '../data/models.dart';
import 'period.dart';

class CategoryTotal {
  /// Top-level category; null for uncategorised transactions.
  final Category? category;
  final int amount;

  const CategoryTotal(this.category, this.amount);
}

class Totals {
  final int income;
  final int expense;

  const Totals(this.income, this.expense);

  int get net => income - expense;
}

/// Income and expense totals. Transfers are not income or expense.
Totals totalsOf(Iterable<Txn> txns) {
  var inc = 0, exp = 0;
  for (final t in txns) {
    if (t.type == TxnType.income) inc += t.amount;
    if (t.type == TxnType.expense) exp += t.amount;
  }
  return Totals(inc, exp);
}

/// Sums [type] transactions per top-level category, largest first.
/// Subcategory amounts roll up into their parent.
List<CategoryTotal> categoryTotals(
  Iterable<Txn> txns,
  TxnType type,
  Map<int, Category> categories,
) {
  final sums = <int?, int>{};
  for (final t in txns.where((t) => t.type == type)) {
    var cat = categories[t.categoryId];
    if (cat?.parentId != null) cat = categories[cat!.parentId] ?? cat;
    sums[cat?.id] = (sums[cat?.id] ?? 0) + t.amount;
  }
  final list = [
    for (final e in sums.entries) CategoryTotal(categories[e.key], e.value),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return list;
}

class InvestmentBucket {
  final String label;
  final DateTime start;
  final DateTime end;
  int invested = 0;
  int withdrawn = 0;

  InvestmentBucket(this.label, this.start, this.end);

  int get net => invested - withdrawn;
}

class AccountFlow {
  final Account account;
  int invested = 0;
  int withdrawn = 0;

  /// Income recorded directly on the investment account (dividends, profit).
  int returns = 0;

  AccountFlow(this.account);

  int get net => invested - withdrawn;
}

class InvestmentSummary {
  /// Money moved from regular accounts into investment accounts.
  final int invested;

  /// Money moved from investment accounts back to regular accounts.
  final int withdrawn;

  /// Income booked directly on investment accounts.
  final int returns;

  final List<AccountFlow> byAccount;
  final List<InvestmentBucket> buckets;

  const InvestmentSummary({
    required this.invested,
    required this.withdrawn,
    required this.returns,
    required this.byAccount,
    required this.buckets,
  });

  int get net => invested - withdrawn;
}

/// Works out how much was invested in [period].
///
/// A transfer counts as an investment when it goes from a regular account into
/// an account marked as an investment account, and as a withdrawal when it goes
/// the other way. Transfers between two investment accounts are rebalancing and
/// are ignored.
InvestmentSummary investmentSummary(
  Iterable<Txn> txns,
  Map<int, Account> accounts,
  Period period, {
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  bool isInv(int? id) => id != null && (accounts[id]?.isInvestment ?? false);

  final flows = <int, AccountFlow>{};
  AccountFlow flowFor(int id) => flows.putIfAbsent(id, () => AccountFlow(accounts[id]!));

  final buckets = bucketsFor(period, firstDate: firstDate, lastDate: lastDate);
  InvestmentBucket? bucketOf(DateTime d) {
    for (final b in buckets) {
      if (!d.isBefore(b.start) && d.isBefore(b.end)) return b;
    }
    return null;
  }

  var invested = 0, withdrawn = 0, returns = 0;
  for (final t in txns) {
    if (!period.contains(t.date)) continue;
    if (t.type == TxnType.transfer) {
      final fromInv = isInv(t.accountId);
      final toInv = isInv(t.toAccountId);
      if (toInv && !fromInv) {
        invested += t.amount;
        flowFor(t.toAccountId!).invested += t.amount;
        bucketOf(t.date)?.invested += t.amount;
      } else if (fromInv && !toInv) {
        withdrawn += t.amount;
        flowFor(t.accountId).withdrawn += t.amount;
        bucketOf(t.date)?.withdrawn += t.amount;
      }
    } else if (t.type == TxnType.income && isInv(t.accountId)) {
      returns += t.amount;
      flowFor(t.accountId).returns += t.amount;
    }
  }

  final byAccount = flows.values.toList()..sort((a, b) => b.net.compareTo(a.net));
  return InvestmentSummary(
    invested: invested,
    withdrawn: withdrawn,
    returns: returns,
    byAccount: byAccount,
    buckets: buckets,
  );
}

/// Splits a period into chart buckets: days for a week, weeks for a month,
/// months for a year, and months or years for longer ranges.
List<InvestmentBucket> bucketsFor(Period period, {DateTime? firstDate, DateTime? lastDate}) {
  final out = <InvestmentBucket>[];
  switch (period.kind) {
    case PeriodKind.weekly:
      for (var i = 0; i < 7; i++) {
        final s = DateTime(period.start.year, period.start.month, period.start.day + i);
        out.add(InvestmentBucket(DateFormat('E').format(s), s, DateTime(s.year, s.month, s.day + 1)));
      }
    case PeriodKind.monthly:
      for (var w = 0;; w++) {
        final s = DateTime(period.start.year, period.start.month, period.start.day + 7 * w);
        if (!s.isBefore(period.end)) break;
        var e = DateTime(s.year, s.month, s.day + 7);
        if (e.isAfter(period.end)) e = period.end;
        out.add(InvestmentBucket('W${w + 1}', s, e));
      }
    case PeriodKind.yearly:
      for (var m = 1; m <= 12; m++) {
        final s = DateTime(period.start.year, m);
        out.add(InvestmentBucket(DateFormat('MMM').format(s), s, DateTime(s.year, m + 1)));
      }
    case PeriodKind.all:
    case PeriodKind.custom:
      var s = period.kind == PeriodKind.all ? (firstDate ?? DateTime.now()) : period.start;
      var e = period.kind == PeriodKind.all ? (lastDate ?? DateTime.now()) : period.end;
      if (e.isBefore(s)) e = s;
      final months = (e.year - s.year) * 12 + e.month - s.month + 1;
      if (months <= 24) {
        for (var i = 0; i < months; i++) {
          final bs = DateTime(s.year, s.month + i);
          out.add(InvestmentBucket(DateFormat("MMM ''yy").format(bs), bs, DateTime(bs.year, bs.month + 1)));
        }
      } else {
        for (var y = s.year; y <= e.year; y++) {
          out.add(InvestmentBucket('$y', DateTime(y), DateTime(y + 1)));
        }
      }
  }
  return out;
}
