/// Core data types. Amounts are stored as integer minor units (e.g. paisa),
/// so Rs 1,234.50 is stored as 123450.
library;

enum TxnType { income, expense, transfer }

const accountGroups = [
  'Cash',
  'Bank Accounts',
  'Card',
  'Savings',
  'Investments',
  'Loan',
  'Insurance',
  'Others',
];

class Account {
  final int? id;
  final String name;
  final String group;
  final bool isInvestment;
  final int initialBalance;
  final bool hidden;
  final int sort;

  const Account({
    this.id,
    required this.name,
    this.group = 'Others',
    this.isInvestment = false,
    this.initialBalance = 0,
    this.hidden = false,
    this.sort = 0,
  });

  Account copyWith({
    String? name,
    String? group,
    bool? isInvestment,
    int? initialBalance,
    bool? hidden,
    int? sort,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        group: group ?? this.group,
        isInvestment: isInvestment ?? this.isInvestment,
        initialBalance: initialBalance ?? this.initialBalance,
        hidden: hidden ?? this.hidden,
        sort: sort ?? this.sort,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'grp': group,
        'is_investment': isInvestment ? 1 : 0,
        'initial': initialBalance,
        'hidden': hidden ? 1 : 0,
        'sort': sort,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        group: (m['grp'] as String?) ?? 'Others',
        isInvestment: (m['is_investment'] as int? ?? 0) == 1,
        initialBalance: m['initial'] as int? ?? 0,
        hidden: (m['hidden'] as int? ?? 0) == 1,
        sort: m['sort'] as int? ?? 0,
      );
}

class Category {
  final int? id;
  final String name;

  /// Either [TxnType.income] or [TxnType.expense].
  final TxnType type;
  final int? parentId;
  final int sort;

  const Category({
    this.id,
    required this.name,
    required this.type,
    this.parentId,
    this.sort = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.index,
        'parent_id': parentId,
        'sort': sort,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: TxnType.values[m['type'] as int],
        parentId: m['parent_id'] as int?,
        sort: m['sort'] as int? ?? 0,
      );
}

class Txn {
  final int? id;
  final TxnType type;
  final DateTime date;
  final int amount;

  /// Source account (for transfers: the account money leaves).
  final int accountId;

  /// Destination account, only for transfers.
  final int? toAccountId;

  /// Category, for income and expense only. May point at a subcategory.
  final int? categoryId;
  final String note;
  final String description;

  const Txn({
    this.id,
    required this.type,
    required this.date,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.note = '',
    this.description = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.index,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category_id': categoryId,
        'note': note,
        'description': description,
      };

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int?,
        type: TxnType.values[m['type'] as int],
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        amount: m['amount'] as int,
        accountId: m['account_id'] as int,
        toAccountId: m['to_account_id'] as int?,
        categoryId: m['category_id'] as int?,
        note: (m['note'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
      );
}

class Budget {
  final int categoryId;
  final int amount;

  const Budget({required this.categoryId, required this.amount});
}
