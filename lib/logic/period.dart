import 'package:intl/intl.dart';

enum PeriodKind { weekly, monthly, yearly, all, custom }

extension PeriodKindLabel on PeriodKind {
  String get label => switch (this) {
        PeriodKind.weekly => 'Weekly',
        PeriodKind.monthly => 'Monthly',
        PeriodKind.yearly => 'Annually',
        PeriodKind.all => 'All time',
        PeriodKind.custom => 'Period',
      };
}

/// Day of the month on which a "month" starts (1-28). Set from settings;
/// e.g. 5 means a month runs from the 5th to the 4th of the next month.
int monthStartDay = 1;

/// A half-open date range [start, end) with a kind that controls how it
/// steps forward and backward.
class Period {
  final PeriodKind kind;
  final DateTime start;
  final DateTime end;

  const Period._(this.kind, this.start, this.end);

  /// [startDay] overrides [monthStartDay] for monthly periods, e.g. 1 for a
  /// calendar month grid.
  factory Period.of(PeriodKind kind, DateTime anchor, {int? startDay}) {
    final d = DateTime(anchor.year, anchor.month, anchor.day);
    switch (kind) {
      case PeriodKind.weekly:
        // Weeks start on Monday.
        final s = d.subtract(Duration(days: d.weekday - 1));
        return Period._(kind, s, DateTime(s.year, s.month, s.day + 7));
      case PeriodKind.monthly:
        final sd = startDay ?? monthStartDay;
        final s = d.day >= sd ? DateTime(d.year, d.month, sd) : DateTime(d.year, d.month - 1, sd);
        return Period._(kind, s, DateTime(s.year, s.month + 1, sd));
      case PeriodKind.yearly:
        return Period._(kind, DateTime(d.year), DateTime(d.year + 1));
      case PeriodKind.all:
        return Period._(kind, DateTime(1970), DateTime(3000));
      case PeriodKind.custom:
        return Period._(kind, d, DateTime(d.year, d.month, d.day + 1));
    }
  }

  factory Period.custom(DateTime start, DateTime endInclusive) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(endInclusive.year, endInclusive.month, endInclusive.day + 1);
    return Period._(PeriodKind.custom, s, e);
  }

  bool get canStep => kind != PeriodKind.all && kind != PeriodKind.custom;

  Period step(int delta) {
    switch (kind) {
      case PeriodKind.weekly:
        return Period.of(kind, DateTime(start.year, start.month, start.day + 7 * delta));
      case PeriodKind.monthly:
        return Period.of(kind, DateTime(start.year, start.month + delta, start.day), startDay: start.day);
      case PeriodKind.yearly:
        return Period.of(kind, DateTime(start.year + delta));
      case PeriodKind.all:
      case PeriodKind.custom:
        return this;
    }
  }

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  String get label {
    final lastDay = end.subtract(const Duration(days: 1));
    switch (kind) {
      case PeriodKind.weekly:
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(lastDay)}';
      case PeriodKind.monthly:
        if (start.day == 1) return DateFormat('MMM yyyy').format(start);
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yy').format(lastDay)}';
      case PeriodKind.yearly:
        return '${start.year}';
      case PeriodKind.all:
        return 'All time';
      case PeriodKind.custom:
        return '${DateFormat('d MMM yy').format(start)} – ${DateFormat('d MMM yy').format(lastDay)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Period && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}
