import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final double value;
}

/// Accessible horizontal bar list — used for order volume by status.
class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({
    super.key,
    required this.bars,
    this.valueFormatter,
    this.barColor = AppColors.forest,
    this.onBarTap,
  });

  final List<({String label, double value, Color color})> bars;
  final String Function(double)? valueFormatter;
  final Color barColor;

  /// Optional per-bar callback so a bar can act as a filter link.
  final void Function(int index)? onBarTap;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return const _ChartEmpty(message: 'No data for this period yet.');
    }
    final maxValue = bars.map((b) => b.value).fold<double>(0, math.max);
    return Column(
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          _bar(context, bars[i], i, maxValue),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  Widget _bar(BuildContext context, ({String label, double value, Color color}) bar, int index, double maxValue) {
    final content = Row(
      children: [
        SizedBox(
          width: 128,
          child: Text(
            bar.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Stack(
              children: [
                Container(height: 12, color: AppColors.surfaceMuted),
                FractionallySizedBox(
                  widthFactor: maxValue == 0 ? 0 : (bar.value / maxValue).clamp(0.0, 1.0),
                  child: Container(height: 12, color: bar.color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 56,
          child: Text(
            valueFormatter?.call(bar.value) ?? bar.value.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
    if (onBarTap == null) return content;
    return InkWell(
      onTap: () => onBarTap!(index),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: content,
      ),
    );
  }
}

/// Lightweight sparkline for KPI cards.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = AppColors.forest, this.height = 34});

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = size.height - ((values[i] - minV) / range) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.values != values || old.color != color;
}

/// Revenue trend as a filled area + line with a hover tooltip.
class RevenueAreaChart extends StatefulWidget {
  const RevenueAreaChart({
    super.key,
    required this.points,
    this.height = 240,
    this.currency = 'INR',
  });

  final List<ChartPoint> points;
  final double height;
  final String currency;

  @override
  State<RevenueAreaChart> createState() => _RevenueAreaChartState();
}

class _RevenueAreaChartState extends State<RevenueAreaChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return SizedBox(height: widget.height, child: const _ChartEmpty(message: 'No sales yet — revenue appears here as orders complete.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const left = 52.0;
        const right = 14.0;
        const top = 16.0;
        const bottom = 28.0;
        final plotW = (width - left - right).clamp(1.0, double.infinity);
        final plotH = (widget.height - top - bottom).clamp(1.0, double.infinity);
        final maxV = widget.points.map((p) => p.value).fold<double>(0, math.max);
        final niceMax = maxV == 0 ? 100.0 : maxV * 1.18;
        final n = widget.points.length;

        double xFor(int i) => n == 1 ? left + plotW / 2 : left + (plotW * i / (n - 1));
        double yFor(double v) => top + (1 - v / niceMax) * plotH;

        void handleHover(Offset local) {
          final rel = (local.dx - left) / plotW;
          final idx = (rel * (n - 1)).round().clamp(0, n - 1);
          if (idx != _hover) setState(() => _hover = idx);
        }

        return MouseRegion(
          onHover: (e) => handleHover(e.localPosition),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapDown: (d) => handleHover(d.localPosition),
            child: SizedBox(
              height: widget.height,
              width: width,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(width, widget.height),
                    painter: _AreaChartPainter(
                      points: widget.points,
                      niceMax: niceMax,
                      left: left,
                      right: right,
                      top: top,
                      bottom: bottom,
                      hoverIndex: _hover,
                      currency: widget.currency,
                      textStyle: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_hover != null)
                    Positioned(
                      left: (xFor(_hover!) - 70).clamp(4.0, math.max(4.0, width - 150)),
                      top: (yFor(widget.points[_hover!].value) - 62).clamp(0.0, widget.height - 56),
                      child: _Tooltip(
                        label: widget.points[_hover!].label,
                        value: formatMinor(widget.points[_hover!].value.round(), currency: widget.currency),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.forestDeep,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.onForestMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  _AreaChartPainter({
    required this.points,
    required this.niceMax,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.hoverIndex,
    required this.currency,
    required this.textStyle,
  });

  final List<ChartPoint> points;
  final double niceMax;
  final double left;
  final double right;
  final double top;
  final double bottom;
  final int? hoverIndex;
  final String currency;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final n = points.length;

    double xFor(int i) => n == 1 ? left + plotW / 2 : left + (plotW * i / (n - 1));
    double yFor(double v) => top + (1 - v / niceMax) * plotH;

    // Grid + y labels.
    const gridCount = 4;
    final gridPaint = Paint()..color = AppColors.border;
    for (var g = 0; g <= gridCount; g++) {
      final v = niceMax * g / gridCount;
      final y = yFor(v);
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      _text(canvas, formatCompactCurrency(v.round(), currency: currency), Offset(0, y - 7), 46,
          TextAlign.right);
    }

    // Area + line.
    final line = Path();
    for (var i = 0; i < n; i++) {
      final x = xFor(i);
      final y = yFor(points[i].value);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(xFor(n - 1), top + plotH)
      ..lineTo(xFor(0), top + plotH)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.forest.withValues(alpha: 0.26), AppColors.forest.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(left, top, plotW, plotH)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // X labels (about 5).
    final step = (n / 5).ceil().clamp(1, n);
    for (var i = 0; i < n; i += step) {
      _text(canvas, points[i].label, Offset(xFor(i) - 24, size.height - 20), 48, TextAlign.center);
    }

    // Hover guide + markers.
    for (var i = 0; i < n; i++) {
      if (points[i].value <= 0) continue;
      canvas.drawCircle(Offset(xFor(i), yFor(points[i].value)), hoverIndex == i ? 5 : 3,
          Paint()..color = AppColors.forest);
      if (hoverIndex == i) {
        canvas.drawCircle(
          Offset(xFor(i), yFor(points[i].value)),
          8,
          Paint()..color = AppColors.lime.withValues(alpha: 0.6),
        );
      }
    }
    if (hoverIndex != null) {
      final x = xFor(hoverIndex!);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + plotH),
        Paint()..color = AppColors.forest.withValues(alpha: 0.25)..strokeWidth = 1.4,
      );
    }
  }

  void _text(Canvas canvas, String value, Offset offset, double width, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: value, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter old) =>
      old.points != points || old.hoverIndex != hoverIndex || old.niceMax != niceMax;
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights_outlined, color: AppColors.textMuted, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
