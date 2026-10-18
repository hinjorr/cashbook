import 'package:intl/intl.dart';

final _fmt = NumberFormat('#,##0.00', 'en_US');

/// Formats minor units (paisa) as "Rs 1,234.50".
String formatMoney(int minor, {String symbol = 'Rs', bool showSign = false}) {
  final sign = minor < 0 ? '-' : (showSign && minor > 0 ? '+' : '');
  final body = _fmt.format(minor.abs() / 100);
  return symbol.isEmpty ? '$sign$body' : '$sign$symbol $body';
}

/// Parses user input like "1,234.5" into minor units. Returns null if invalid.
int? parseMoney(String input) {
  final cleaned = input.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

/// Minor units to an editable string without grouping, e.g. 123450 -> "1234.5".
String moneyToInput(int minor) {
  final v = minor / 100;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
