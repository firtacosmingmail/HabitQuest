/// Small, dependency-free charts for the stats dashboard, built to the
/// dataviz rules (see admin/README.md, "Charts"):
///
/// * one measure per chart, never a second y-axis; every chart is a single
///   series, so it uses categorical slot 1 (blue) and no legend box — the
///   card title names what is plotted;
/// * columns ≤ 24 px wide with a 4 px rounded data end, square at the
///   baseline, and at least a 2 px surface gap between neighbours; lines are
///   2 px with a 10 % area wash and an 8 px end dot ringed in the surface;
/// * hairline solid gridlines and a recessive baseline; clean, thousands-
///   separated y ticks; text always in ink tokens, never the series colour;
/// * selective direct labels (the last value of a line, the tallest column);
/// * hover: a crosshair snapping to the nearest day on lines, per-column hit
///   areas on columns, one tooltip with the value first;
/// * every chart has a table view (ChartCard), so nothing hides behind hover.
///
/// Palette validated with the dataviz validator: #2a78d6 on #fcfcfb (light)
/// and #3987e5 on #1a1a19 (dark) pass every check.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Chart colour roles, light and dark (dataviz reference palette).
@immutable
class VizTokens extends ThemeExtension<VizTokens> {
  final Color surface;
  final Color page;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color grid;
  final Color baseline;
  final Color series;
  final Color border;

  const VizTokens({
    required this.surface,
    required this.page,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.grid,
    required this.baseline,
    required this.series,
    required this.border,
  });

  static const light = VizTokens(
    surface: Color(0xFFFCFCFB),
    page: Color(0xFFF9F9F7),
    inkPrimary: Color(0xFF0B0B0B),
    inkSecondary: Color(0xFF52514E),
    inkMuted: Color(0xFF898781),
    grid: Color(0xFFE1E0D9),
    baseline: Color(0xFFC3C2B7),
    series: Color(0xFF2A78D6),
    border: Color(0x1A0B0B0B),
  );

  static const dark = VizTokens(
    surface: Color(0xFF1A1A19),
    page: Color(0xFF0D0D0D),
    inkPrimary: Color(0xFFFFFFFF),
    inkSecondary: Color(0xFFC3C2B7),
    inkMuted: Color(0xFF898781),
    grid: Color(0xFF2C2C2A),
    baseline: Color(0xFF383835),
    series: Color(0xFF3987E5),
    border: Color(0x1AFFFFFF),
  );

  static VizTokens of(BuildContext context) =>
      Theme.of(context).extension<VizTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  VizTokens copyWith() => this;

  @override
  VizTokens lerp(ThemeExtension<VizTokens>? other, double t) =>
      t < 0.5 ? this : (other as VizTokens? ?? this);
}

/// 1,284 / 12.9K / 4.2M.
String compactNumber(num v) {
  final a = v.abs();
  String trim(double x) {
    final s = x.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (a >= 1e6) return '${trim(v / 1e6)}M';
  if (a >= 1e4) return '${trim(v / 1e3)}K';
  return groupThousands(v);
}

/// 1284 → 1,284 (one decimal kept for fractional values).
String groupThousands(num v) {
  final isInt = v == v.roundToDouble();
  final whole = v.abs().truncate().toString();
  final buf = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  if (!isInt) {
    buf.write('.${((v.abs() - v.abs().truncate()) * 10).round() % 10}');
  }
  return buf.toString();
}

/// Clean y-axis ticks from 0 to ≥ [max] (about 4 steps of 1/2/5 × 10^n).
List<double> niceTicks(double max) {
  if (max <= 0) return const [0, 1];
  final raw = max / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final step =
      (norm <= 1
          ? 1
          : norm <= 2
          ? 2
          : norm <= 5
          ? 5
          : 10) *
      mag;
  final top = (max / step).ceil() * step;
  return [for (var v = 0.0; v <= top + step / 2; v += step) v];
}

enum ChartKind { line, column }

/// A single-series chart over [labels] with [values].
class SeriesChart extends StatefulWidget {
  final ChartKind kind;

  /// Axis/tooltip label of each point (dates or bucket names).
  final List<String> labels;
  final List<num> values;

  /// Unit for the tooltip, e.g. "users".
  final String unit;
  final double height;

  const SeriesChart({
    super.key,
    required this.kind,
    required this.labels,
    required this.values,
    required this.unit,
    this.height = 220,
  });

  @override
  State<SeriesChart> createState() => _SeriesChartState();
}

class _SeriesChartState extends State<SeriesChart> {
  int? _hover;

  static const _left = 44.0;
  static const _right = 40.0;
  static const _top = 18.0;
  static const _bottom = 26.0;

  int? _indexAt(Offset p, Size size) {
    final n = widget.values.length;
    if (n == 0) return null;
    final w = size.width - _left - _right;
    if (p.dx < _left - 12 || p.dx > size.width - _right + 12) return null;
    if (widget.kind == ChartKind.line) {
      if (n == 1) return 0;
      return (((p.dx - _left) / w) * (n - 1)).round().clamp(0, n - 1);
    }
    return (((p.dx - _left) / w) * n).floor().clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = VizTokens.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, widget.height);
          final hover = _hover;
          final chart = MouseRegion(
            onHover: (e) =>
                setState(() => _hover = _indexAt(e.localPosition, size)),
            onExit: (_) => setState(() => _hover = null),
            child: CustomPaint(
              size: size,
              painter: _SeriesPainter(
                kind: widget.kind,
                labels: widget.labels,
                values: widget.values,
                tokens: t,
                hover: hover,
                tickStyle: (text.labelSmall ?? const TextStyle()).copyWith(
                  color: t.inkMuted,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                labelStyle: (text.labelSmall ?? const TextStyle()).copyWith(
                  color: t.inkSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                insets: const EdgeInsets.fromLTRB(_left, _top, _right, _bottom),
              ),
            ),
          );
          if (hover == null || hover >= widget.values.length) return chart;
          final n = widget.values.length;
          final w = size.width - _left - _right;
          final x = widget.kind == ChartKind.line
              ? _left + (n == 1 ? w / 2 : w * hover / (n - 1))
              : _left + w * (hover + 0.5) / n;
          const tipWidth = 150.0;
          final left = (x + 12 + tipWidth > size.width)
              ? x - 12 - tipWidth
              : x + 12;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              chart,
              Positioned(
                left: left.clamp(0, math.max(0, size.width - tipWidth)),
                top: 4,
                width: tipWidth,
                child: IgnorePointer(
                  child: _Tooltip(
                    value: groupThousands(widget.values[hover]),
                    unit: widget.unit,
                    label: widget.labels[hover],
                    tokens: t,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tooltip extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final VizTokens tokens;

  const _Tooltip({
    required this.value,
    required this.unit,
    required this.label,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.border),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x22000000))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.labelSmall?.copyWith(color: tokens.inkSecondary),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(width: 12, height: 2, color: tokens.series),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: text.titleSmall?.copyWith(
                    color: tokens.inkPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    unit,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: tokens.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  final ChartKind kind;
  final List<String> labels;
  final List<num> values;
  final VizTokens tokens;
  final int? hover;
  final TextStyle tickStyle;
  final TextStyle labelStyle;
  final EdgeInsets insets;

  _SeriesPainter({
    required this.kind,
    required this.labels,
    required this.values,
    required this.tokens,
    required this.hover,
    required this.tickStyle,
    required this.labelStyle,
    required this.insets,
  });

  void _text(
    Canvas c,
    String s,
    TextStyle style,
    Offset at, {
    double align = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(at.dx - tp.width * align, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      insets.left,
      insets.top,
      size.width - insets.right,
      size.height - insets.bottom,
    );
    final n = values.length;
    final maxV = values.fold<double>(0, (m, v) => math.max(m, v.toDouble()));
    final ticks = niceTicks(maxV);
    final top = ticks.last;
    double y(num v) => plot.bottom - plot.height * (v / top);

    // Gridlines (hairline, solid) and y ticks.
    final grid = Paint()
      ..color = tokens.grid
      ..strokeWidth = 1;
    for (final tk in ticks) {
      final yy = y(tk).roundToDouble() + 0.5;
      if (tk > 0) {
        canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      }
      _text(
        canvas,
        compactNumber(tk),
        tickStyle,
        Offset(plot.left - 8, yy),
        align: 1,
      );
    }
    if (n == 0) return;

    double xLine(int i) =>
        n == 1 ? plot.center.dx : plot.left + plot.width * i / (n - 1);
    double xCol(int i) => plot.left + plot.width * (i + 0.5) / n;
    final xAt = kind == ChartKind.line ? xLine : xCol;

    // X labels: thinned so they never collide (about one per 70 px).
    final every = math.max(1, (n / math.max(1, plot.width / 70)).ceil());
    for (var i = 0; i < n; i += every) {
      _text(
        canvas,
        labels[i],
        tickStyle,
        Offset(xAt(i), plot.bottom + 14),
        align: 0.5,
      );
    }

    final seriesPaint = Paint()..color = tokens.series;
    if (kind == ChartKind.column) {
      final slot = plot.width / n;
      final barW = math.max(2.0, math.min(24.0, slot - 2)).toDouble();
      var maxI = 0;
      for (var i = 0; i < n; i++) {
        if (values[i] > values[maxI]) maxI = i;
      }
      for (var i = 0; i < n; i++) {
        final v = values[i].toDouble();
        if (v <= 0) continue;
        final rect = Rect.fromLTRB(
          xCol(i) - barW / 2,
          y(v),
          xCol(i) + barW / 2,
          plot.bottom,
        );
        final r = Radius.circular(math.min(4, barW / 2));
        final paint = hover == null || hover == i
            ? seriesPaint
            : (Paint()..color = tokens.series.withValues(alpha: 0.55));
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: r, topRight: r),
          paint,
        );
      }
      // Selective direct label: the tallest column's value at its tip.
      if (values[maxI] > 0) {
        _text(
          canvas,
          groupThousands(values[maxI]),
          labelStyle,
          Offset(xCol(maxI), y(values[maxI]) - 9),
          align: 0.5,
        );
      }
    } else {
      final path = Path()..moveTo(xLine(0), y(values[0]));
      for (var i = 1; i < n; i++) {
        path.lineTo(xLine(i), y(values[i]));
      }
      final area = Path.from(path)
        ..lineTo(xLine(n - 1), plot.bottom)
        ..lineTo(xLine(0), plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = tokens.series.withValues(alpha: 0.10),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = tokens.series
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      void dot(int i) {
        final c = Offset(xLine(i), y(values[i]));
        canvas.drawCircle(c, 6, Paint()..color = tokens.surface); // 2px ring
        canvas.drawCircle(c, 4, seriesPaint);
      }

      final h = hover;
      if (h != null) {
        canvas.drawLine(
          Offset(xLine(h), plot.top),
          Offset(xLine(h), plot.bottom),
          Paint()
            ..color = tokens.baseline
            ..strokeWidth = 1,
        );
        dot(h);
      }
      dot(n - 1);
      // Direct label: the last value, at the line end.
      _text(
        canvas,
        groupThousands(values[n - 1]),
        labelStyle,
        Offset(xLine(n - 1) + 8, y(values[n - 1])),
      );
    }

    // Baseline last, above the fills.
    canvas.drawLine(
      Offset(plot.left, plot.bottom + 0.5),
      Offset(plot.right, plot.bottom + 0.5),
      Paint()
        ..color = tokens.baseline
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.hover != hover ||
      old.tokens != tokens ||
      old.kind != kind;
}

/// A dashboard card: title, an optional note on how the figure is derived,
/// and the chart with a chart/table toggle.
class ChartCard extends StatefulWidget {
  final String title;
  final String? note;
  final ChartKind kind;
  final List<String> labels;

  /// Full labels for the table and tooltip (defaults to [labels]).
  final List<String>? longLabels;
  final List<num> values;
  final String unit;
  final String labelHeader;

  const ChartCard({
    super.key,
    required this.title,
    this.note,
    required this.kind,
    required this.labels,
    this.longLabels,
    required this.values,
    required this.unit,
    this.labelHeader = 'Day',
  });

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final t = VizTokens.of(context);
    final text = Theme.of(context).textTheme;
    final long = widget.longLabels ?? widget.labels;
    final total = widget.values.fold<num>(0, (a, b) => a + b);
    return Card(
      color: t.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: text.titleSmall?.copyWith(
                      color: t.inkPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _table ? 'Show chart' : 'Show table',
                  icon: Icon(
                    _table ? Icons.bar_chart : Icons.table_rows_outlined,
                    size: 18,
                  ),
                  color: t.inkSecondary,
                  onPressed: () => setState(() => _table = !_table),
                ),
              ],
            ),
            if (widget.note != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: Text(
                  widget.note!,
                  style: text.bodySmall?.copyWith(color: t.inkSecondary),
                ),
              ),
            if (_table)
              SizedBox(
                height: 220,
                child: SingleChildScrollView(
                  child: Table(
                    columnWidths: const {1: IntrinsicColumnWidth()},
                    children: [
                      TableRow(
                        children: [
                          _cell(widget.labelHeader, t, bold: true),
                          _cell(widget.unit, t, bold: true, right: true),
                        ],
                      ),
                      for (var i = 0; i < widget.values.length; i++)
                        TableRow(
                          children: [
                            _cell(long[i], t),
                            _cell(
                              groupThousands(widget.values[i]),
                              t,
                              right: true,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              )
            else
              Semantics(
                label:
                    '${widget.title}: ${widget.values.length} points, '
                    'total ${groupThousands(total)} ${widget.unit}. '
                    'Use Show table for the values.',
                child: ExcludeSemantics(
                  child: SeriesChart(
                    kind: widget.kind,
                    labels: widget.labels,
                    values: widget.values,
                    unit: widget.unit,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    String s,
    VizTokens t, {
    bool bold = false,
    bool right = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    child: Text(
      s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: bold ? t.inkPrimary : t.inkSecondary,
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// A KPI stat tile: label, value and an optional caption.
class StatTile extends StatelessWidget {
  final String label;
  final num value;
  final String? caption;
  final bool hero;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = VizTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: BoxConstraints(minWidth: hero ? 220 : 150),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: t.inkSecondary)),
          const SizedBox(height: 4),
          Text(
            compactNumber(value),
            style: (hero ? text.displayMedium : text.headlineSmall)?.copyWith(
              color: t.inkPrimary,
              fontWeight: FontWeight.w600,
              fontSize: hero ? 48 : null,
            ),
          ),
          if (caption != null)
            Text(caption!, style: text.bodySmall?.copyWith(color: t.inkMuted)),
        ],
      ),
    );
  }
}
