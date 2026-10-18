import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/models.dart';

enum MmKind { income, expense, transferOut, transferIn }

/// One row of a Money Manager (Realbyte) export.
class MmRow {
  final DateTime date;
  final String account;

  /// For transfers Money Manager puts the other account in this column.
  final String category;
  final String subcategory;
  final String note;
  final String description;
  final int amount;
  final MmKind kind;

  const MmRow({
    required this.date,
    required this.account,
    required this.category,
    required this.subcategory,
    required this.note,
    required this.description,
    required this.amount,
    required this.kind,
  });
}

class MmParseResult {
  final List<MmRow> rows;
  final List<String> warnings;

  const MmParseResult(this.rows, this.warnings);
}

/// Parses a Money Manager export. The app's "Excel" export is often a
/// tab-separated text file with an .xlsx name, so both real spreadsheets and
/// TSV/CSV text are accepted.
MmParseResult parseMoneyManagerExport(Uint8List bytes) {
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  final table = isZip ? _readXlsx(bytes) : _readText(bytes);
  return parseMoneyManagerTable(table);
}

List<List<Object?>> _readXlsx(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) return const [];
  final sheet = excel.tables.values.first;
  return [
    for (final row in sheet.rows)
      [
        for (final cell in row)
          switch (cell?.value) {
            null => null,
            TextCellValue(:final value) => value.toString(),
            IntCellValue(:final value) => value,
            DoubleCellValue(:final value) => value,
            DateTimeCellValue c => DateTime(c.year, c.month, c.day, c.hour, c.minute, c.second),
            DateCellValue c => DateTime(c.year, c.month, c.day),
            final CellValue other => other.toString(),
          },
      ],
  ];
}

List<List<Object?>> _readText(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final lines = const LineSplitter()
      .convert(text)
      .where((l) => l.trim().isNotEmpty && !l.startsWith('##'))
      .toList();
  if (lines.isEmpty) return const [];
  final tab = lines.first.contains('\t');
  return [for (final l in lines) tab ? l.split('\t') : _splitCsv(l)];
}

List<String> _splitCsv(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString());
  return out;
}

String _norm(Object? v) => (v ?? '').toString().trim().toLowerCase();

MmParseResult parseMoneyManagerTable(List<List<Object?>> table) {
  final warnings = <String>[];
  final headerIdx = table.indexWhere((r) => r.any((c) => _norm(c) == 'income/expense'));
  if (headerIdx < 0) {
    throw const FormatException(
      'Could not find the "Income/Expense" column. Export from Money Manager '
      'using Settings › Backup › Export data to Excel.',
    );
  }
  final header = table[headerIdx].map(_norm).toList();
  int col(List<String> names) => header.indexWhere(names.contains);

  final cDate = col(['date', 'period']);
  final cAccount = col(['account', 'accounts']);
  final cCategory = col(['category']);
  final cSub = col(['subcategory']);
  final cNote = col(['note', 'contents']);
  final cKind = col(['income/expense']);
  final cDesc = col(['description']);
  // The column just before Income/Expense holds the amount in the base
  // currency (it is titled with the currency code, e.g. "PKR").
  final cBase = cKind - 1;
  final cAmount = col(['amount']);

  if (cDate < 0 || cAccount < 0 || cKind < 0) {
    throw const FormatException('The file is missing the Date, Account or Income/Expense column.');
  }

  Object? at(List<Object?> r, int i) => i >= 0 && i < r.length ? r[i] : null;
  String str(List<Object?> r, int i) => (at(r, i) ?? '').toString().trim();

  final rows = <MmRow>[];
  for (var i = headerIdx + 1; i < table.length; i++) {
    final r = table[i];
    if (r.every((c) => _norm(c).isEmpty)) continue;
    final line = i + 1;

    final date = parseMmDate(at(r, cDate));
    if (date == null) {
      warnings.add('Row $line: unreadable date "${str(r, cDate)}", skipped.');
      continue;
    }
    final kind = _parseKind(_norm(at(r, cKind)));
    if (kind == null) {
      warnings.add('Row $line: unknown type "${str(r, cKind)}", skipped.');
      continue;
    }
    var amount = _parseAmount(at(r, cBase > cNote ? cBase : -1));
    amount ??= _parseAmount(at(r, cAmount));
    if (amount == null) {
      warnings.add('Row $line: unreadable amount, skipped.');
      continue;
    }
    final account = str(r, cAccount);
    if (account.isEmpty) {
      warnings.add('Row $line: no account, skipped.');
      continue;
    }
    rows.add(MmRow(
      date: date,
      account: account,
      category: str(r, cCategory),
      subcategory: str(r, cSub),
      note: str(r, cNote),
      description: str(r, cDesc),
      amount: amount.abs(),
      kind: kind,
    ));
  }
  return MmParseResult(rows, warnings);
}

MmKind? _parseKind(String v) {
  if (v.contains('transfer')) return v.contains('in') && !v.contains('out') ? MmKind.transferIn : MmKind.transferOut;
  if (v.startsWith('inc')) return MmKind.income;
  if (v.startsWith('exp')) return MmKind.expense;
  return null;
}

int? _parseAmount(Object? v) {
  if (v is num) return (v * 100).round();
  final s = (v ?? '').toString().replaceAll(',', '').trim();
  if (s.isEmpty) return null;
  final d = double.tryParse(s);
  return d == null ? null : (d * 100).round();
}

final _dateFormats = [
  'M/d/yyyy H:mm:ss',
  'M/d/yyyy H:mm',
  'M/d/yyyy',
  'yyyy-MM-dd HH:mm:ss',
  'yyyy-MM-dd HH:mm',
  'yyyy-MM-dd',
  'd/M/yyyy H:mm:ss',
  'd/M/yyyy',
];

/// Accepts Excel serial numbers (days since 1899-12-30, local time),
/// DateTime values and common date strings.
DateTime? parseMmDate(Object? v) {
  if (v is DateTime) return v;
  num? serial = v is num ? v : null;
  final s = (v ?? '').toString().trim();
  if (serial == null && s.isEmpty) return null;
  serial ??= num.tryParse(s);
  if (serial != null) {
    if (serial < 1 || serial > 2958465) return null;
    final u = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (serial * 86400000).round()));
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  for (final f in _dateFormats) {
    try {
      return DateFormat(f).parseStrict(s);
    } on FormatException {
      // try the next format
    }
  }
  return null;
}

class ImportReport {
  final int imported;
  final int duplicates;
  final List<String> newAccounts;
  final List<String> warnings;

  const ImportReport({
    required this.imported,
    required this.duplicates,
    required this.newAccounts,
    required this.warnings,
  });
}

const _investmentHints = [
  'invest', 'stock', 'share', 'saving', 'mutual', 'fund', 'gold', 'crypto',
  'bond', 'deposit', 'retire', 'pension', 'etf', 'nsc',
];

bool looksLikeInvestment(String name) {
  final n = name.toLowerCase();
  return _investmentHints.any(n.contains);
}

/// Writes parsed rows into the database. Accounts and categories are matched
/// by name (case-insensitive) and created when missing. Rows that exactly
/// match an existing transaction are skipped, so importing the same file
/// twice is safe.
Future<ImportReport> applyMoneyManagerImport(
  AppDatabase db,
  MmParseResult parsed, {
  bool replaceExisting = false,
}) async {
  if (replaceExisting) await db.wipe();

  final accounts = {for (final a in await db.accounts()) a.name.toLowerCase(): a.id!};
  final cats = await db.categories();
  final catIds = <String, int>{
    for (final c in cats)
      '${c.type.index}|${c.parentId ?? ''}|${c.name.toLowerCase()}': c.id!,
  };
  final newAccounts = <String>[];

  Future<int> accountId(String name) async {
    final key = name.toLowerCase();
    final existing = accounts[key];
    if (existing != null) return existing;
    final inv = looksLikeInvestment(name);
    final id = await db.saveAccount(Account(
      name: name,
      group: inv ? 'Investments' : 'Others',
      isInvestment: inv,
      sort: accounts.length,
    ));
    newAccounts.add(name);
    return accounts[key] = id;
  }

  Future<int?> categoryId(TxnType type, String name, String sub) async {
    if (name.isEmpty) return null;
    Future<int> ensure(String n, int? parent) async {
      final key = '${type.index}|${parent ?? ''}|${n.toLowerCase()}';
      return catIds[key] ??= await db.saveCategory(
        Category(name: n, type: type, parentId: parent, sort: catIds.length),
      );
    }

    final parent = await ensure(name, null);
    return sub.isEmpty ? parent : ensure(sub, parent);
  }

  final existing = <String>{
    for (final t in await db.allTxns())
      '${t.type.index}|${t.date.millisecondsSinceEpoch}|${t.amount}|${t.accountId}|${t.toAccountId}',
  };

  // Money Manager can list a transfer twice (out of one account, into the
  // other). Only use Transfer-In rows when the file has no Transfer-Out rows.
  final hasOut = parsed.rows.any((r) => r.kind == MmKind.transferOut);

  var duplicates = 0;
  final warnings = [...parsed.warnings];
  final toInsert = <Txn>[];
  for (final r in parsed.rows) {
    late Txn t;
    switch (r.kind) {
      case MmKind.income:
      case MmKind.expense:
        final type = r.kind == MmKind.income ? TxnType.income : TxnType.expense;
        t = Txn(
          type: type,
          date: r.date,
          amount: r.amount,
          accountId: await accountId(r.account),
          categoryId: await categoryId(type, r.category, r.subcategory),
          note: r.note,
          description: r.description,
        );
      case MmKind.transferOut:
      case MmKind.transferIn:
        if (r.kind == MmKind.transferIn && hasOut) continue;
        if (r.category.isEmpty) {
          warnings.add('Transfer on ${DateFormat.yMd().format(r.date)} has no target account, skipped.');
          continue;
        }
        final a = await accountId(r.account);
        final b = await accountId(r.category);
        final out = r.kind == MmKind.transferOut;
        t = Txn(
          type: TxnType.transfer,
          date: r.date,
          amount: r.amount,
          accountId: out ? a : b,
          toAccountId: out ? b : a,
          note: r.note,
          description: r.description,
        );
    }
    final key = '${t.type.index}|${t.date.millisecondsSinceEpoch}|${t.amount}|${t.accountId}|${t.toAccountId}';
    if (!existing.add(key)) {
      duplicates++;
      continue;
    }
    toInsert.add(t);
  }

  final batch = db.db.batch();
  for (final t in toInsert) {
    batch.insert('txns', t.toMap()..remove('id'));
  }
  await batch.commit(noResult: true);

  return ImportReport(
    imported: toInsert.length,
    duplicates: duplicates,
    newAccounts: newAccounts,
    warnings: warnings,
  );
}
