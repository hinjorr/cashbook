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
/// Used for months before the first closing date.
int monthStartDay = 1;

/// Days on which the user closed a month, sorted, each at midnight. Each one
/// starts a new month: the month before runs up to the day before it, and the
/// month starting on the last one stays open until the next close.
List<DateTime> monthCloses = const [];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Far-future end of the open month, so entries dated ahead still show in it.
final _openEnd = DateTime(3000);

/// A half-open date range [start, end) with a kind that controls how it
/// steps forward and backward.
class Period {
  final PeriodKind kind;
  final DateTime start;
  final DateTime end;

  /// Set for calendar-style months (the calendar grid), which ignore closing
  /// dates and always start on this day of the month.
  final int? startDay;

  const Period._(this.kind, this.start, this.end, [this.startDay]);

  /// [startDay] overrides closing dates and [monthStartDay] for monthly
  /// periods, e.g. 1 for a calendar month grid.
  factory Period.of(PeriodKind kind, DateTime anchor, {int? startDay}) {
    final d = _day(anchor);
    switch (kind) {
      case PeriodKind.weekly:
        // Weeks start on Monday.
        final s = d.subtract(Duration(days: d.weekday - 1));
        return Period._(kind, s, DateTime(s.year, s.month, s.day + 7));
      case PeriodKind.monthly:
        if (startDay != null) return _byStartDay(d, startDay, startDay);
        return _month(d);
      case PeriodKind.yearly:
        return Period._(kind, DateTime(d.year), DateTime(d.year + 1));
      case PeriodKind.all:
        return Period._(kind, DateTime(1970), DateTime(3000));
      case PeriodKind.custom:
        return Period._(kind, d, DateTime(d.year, d.month, d.day + 1));
    }
  }

  factory Period.custom(DateTime start, DateTime endInclusive) {
    final s = _day(start);
    final e = DateTime(endInclusive.year, endInclusive.month, endInclusive.day + 1);
    return Period._(PeriodKind.custom, s, e);
  }

  static Period _byStartDay(DateTime d, int sd, [int? keep]) {
    final s = d.day >= sd ? DateTime(d.year, d.month, sd) : DateTime(d.year, d.month - 1, sd);
    return Period._(PeriodKind.monthly, s, DateTime(s.year, s.month + 1, sd), keep);
  }

  /// The month containing [d], from closing dates where they apply.
  static Period _month(DateTime d) {
    final closes = monthCloses;
    if (closes.isEmpty) return _byStartDay(d, monthStartDay);
    final first = closes.first;
    if (d.isBefore(first)) {
      // The last month before the first close ends at that close. If that
      // leaves a stub of a few days, it joins the month before it.
      var lastStart = _byStartDay(first.subtract(const Duration(days: 1)), monthStartDay).start;
      if (first.difference(lastStart).inDays < 10) {
        lastStart = _byStartDay(lastStart.subtract(const Duration(days: 1)), monthStartDay).start;
      }
      if (!d.isBefore(lastStart)) return Period._(PeriodKind.monthly, lastStart, first);
      return _byStartDay(d, monthStartDay);
    }
    var i = closes.length - 1;
    while (closes[i].isAfter(d)) {
      i--;
    }
    final end = i + 1 < closes.length ? closes[i + 1] : _openEnd;
    return Period._(PeriodKind.monthly, closes[i], end);
  }

  /// The same period worked out again, e.g. after a month was closed.
  Period refreshed() => kind == PeriodKind.monthly && startDay == null ? _month(start) : this;

  /// True for the current month while it hasn't been closed yet.
  bool get isOpen => kind == PeriodKind.monthly && end == _openEnd;

  bool get canStep => kind != PeriodKind.all && kind != PeriodKind.custom;

  /// Whether there is a next period to step to.
  bool get hasNext => canStep && !isOpen;

  Period step(int delta) {
    switch (kind) {
      case PeriodKind.weekly:
        return Period.of(kind, DateTime(start.year, start.month, start.day + 7 * delta));
      case PeriodKind.monthly:
        if (startDay != null) {
          return _byStartDay(DateTime(start.year, start.month + delta, start.day), startDay!, startDay);
        }
        var p = this;
        for (var i = 0; i < delta.abs(); i++) {
          if (delta > 0 && p.isOpen) break;
          p = _month(delta > 0 ? p.end : p.start.subtract(const Duration(days: 1)));
        }
        return p;
      case PeriodKind.yearly:
        return Period.of(kind, DateTime(start.year + delta));
      case PeriodKind.all:
      case PeriodKind.custom:
        return this;
    }
  }

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// Last day of the period; for the open month, today (or the start day).
  DateTime get lastDay {
    if (isOpen) {
      final today = _day(DateTime.now());
      return today.isBefore(start) ? start : today;
    }
    return end.subtract(const Duration(days: 1));
  }

  int get days => lastDay.difference(start).inDays + 1;

  String get label {
    switch (kind) {
      case PeriodKind.weekly:
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(lastDay)}';
      case PeriodKind.monthly:
        // Named after the month most of it falls in, so 5 Oct – 4 Nov is
        // "Oct 2026" and 30 Oct – 28 Nov is "Nov 2026".
        final mid = isOpen ? start.add(const Duration(days: 14)) : start.add(Duration(days: days ~/ 2));
        return DateFormat('MMM yyyy').format(mid);
      case PeriodKind.yearly:
        return '${start.year}';
      case PeriodKind.all:
        return 'All time';
      case PeriodKind.custom:
        return '${DateFormat('d MMM yy').format(start)} – ${DateFormat('d MMM yy').format(lastDay)}';
    }
  }

  /// The exact dates, shown under [label] for months that don't run from the
  /// 1st to the end of the month (e.g. "5 Oct – 4 Nov · 31 days"). Null
  /// otherwise.
  String? get range {
    if (kind != PeriodKind.monthly || startDay != null) return null;
    final f = DateFormat('d MMM');
    final n = days == 1 ? '1 day' : '$days days';
    if (isOpen) return 'Since ${f.format(start)} · $n · open';
    if (start.day == 1 && end.day == 1) return null;
    return '${f.format(start)} – ${f.format(lastDay)} · $n';
  }

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.startDay == startDay;

  @override
  int get hashCode => Object.hash(kind, start, end, startDay);
}
