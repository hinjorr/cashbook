import 'dart:math' as math;

import 'package:flutter/material.dart';

class PieSlice {
  final String label;
  final double value;
  final Color color;

  const PieSlice(this.label, this.value, this.color);
}

/// A pie chart with every slice labelled outside the circle, joined to its
/// slice by a thin leader line in the slice's colour. Slices run clockwise
/// from 12 o'clock, largest first. Labels on each side are spread vertically
/// so they never overlap; if there are more than fit, the smallest slices
/// lose their labels (they still show in the list under the chart).
class LabeledPie extends StatelessWidget {
  const LabeledPie({super.key, required this.slices, this.height = 300});

  final List<PieSlice> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PiePainter(
          slices: slices,
          gap: theme.scaffoldBackgroundColor,
          nameStyle: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
          percentStyle: theme.textTheme.bodySmall!.copyWith(fontSize: 12),
          textScaler: MediaQuery.textScalerOf(context),
        ),
      ),
    );
  }
}

class _Label {
  final int index;
  final double angle;
  final bool right;
  double y;
  final TextPainter name;
  final TextPainter percent;

  _Label(this.index, this.angle, this.right, this.y, this.name, this.percent);

  double get height => name.height + percent.height;
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.slices,
    required this.gap,
    required this.nameStyle,
    required this.percentStyle,
    required this.textScaler,
  });

  final List<PieSlice> slices;
  final Color gap;
  final TextStyle nameStyle;
  final TextStyle percentStyle;
  final TextScaler textScaler;

  static const _elbow = 10.0; // leader line length out from the slice
  static const _run = 12.0; // horizontal run before the text
  static const _textGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;

    // Leave most of the width either side of the pie for labels.
    final r = math.min(size.height * 0.34, size.width * 0.18);
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Slices, separated by thin gaps in the background colour.
    var start = -math.pi / 2;
    final mids = <double>[];
    for (final s in slices) {
      final sweep = s.value / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = s.color);
      mids.add(start + sweep / 2);
      start += sweep;
    }
    if (slices.length > 1) {
      final sep = Paint()
        ..color = gap
        ..strokeWidth = 1.5;
      start = -math.pi / 2;
      for (final s in slices) {
        canvas.drawLine(c, c + Offset(math.cos(start), math.sin(start)) * r, sep);
        start += s.value / total * 2 * math.pi;
      }
    }

    // Labels.
    final textWidth = math.max(40.0, size.width / 2 - r - _elbow - _run - _textGap - 4);
    TextPainter tp(String text, TextStyle style) => TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
          textScaler: textScaler,
        )..layout(maxWidth: textWidth);

    final labels = <_Label>[];
    for (var i = 0; i < slices.length; i++) {
      final a = mids[i];
      final pct = slices[i].value / total * 100;
      labels.add(_Label(
        i,
        a,
        math.cos(a) >= 0,
        c.dy + math.sin(a) * (r + _elbow),
        tp(slices[i].label, nameStyle),
        tp('${pct.toStringAsFixed(1)} %', percentStyle),
      ));
    }

    for (final right in [true, false]) {
      var side = labels.where((l) => l.right == right).toList();
      if (side.isEmpty) continue;
      final h = side.first.height + 2;
      // Drop the smallest slices' labels if they can't all fit.
      final capacity = (size.height / h).floor();
      if (side.length > capacity) {
        side.sort((a, b) => slices[b.index].value.compareTo(slices[a.index].value));
        side = side.take(capacity).toList();
      }
      side.sort((a, b) => a.y.compareTo(b.y));
      // Centre each label on its anchor, then push apart top-down and pull
      // back inside bottom-up.
      for (final l in side) {
        l.y -= l.height / 2;
      }
      for (var i = 0; i < side.length; i++) {
        final minY = i == 0 ? 0.0 : side[i - 1].y + h;
        if (side[i].y < minY) side[i].y = minY;
      }
      for (var i = side.length - 1; i >= 0; i--) {
        final maxY = i == side.length - 1 ? size.height - h : side[i + 1].y - h;
        if (side[i].y > maxY) side[i].y = maxY;
      }

      for (final l in side) {
        final color = slices[l.index].color;
        final dir = Offset(math.cos(l.angle), math.sin(l.angle));
        final p0 = c + dir * r;
        final p1 = c + dir * (r + _elbow);
        final textY = l.y + l.name.height / 2;
        final xEnd = right ? c.dx + r + _elbow + _run : c.dx - r - _elbow - _run;
        final path = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(xEnd, textY);
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        final x = right ? xEnd + _textGap : xEnd - _textGap - math.max(l.name.width, l.percent.width);
        l.name.paint(canvas, Offset(x, l.y));
        l.percent.paint(canvas, Offset(x, l.y + l.name.height));
      }
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.slices != slices || old.gap != gap || old.nameStyle != nameStyle || old.textScaler != textScaler;
}
