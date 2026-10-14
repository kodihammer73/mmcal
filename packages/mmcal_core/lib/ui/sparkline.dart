import 'package:flutter/material.dart';

/// Tiny flat line chart (no axes) for the 30-day closes of a holding.
/// Deliberately minimal: one stroke, colour from the trend (green up,
/// red down), sized to sit inside an expanded portfolio row.
class Sparkline extends StatelessWidget {
  final List<double> closes;
  final double width;
  final double height;
  final Color? color;

  const Sparkline({
    super.key,
    required this.closes,
    this.width = 100,
    this.height = 30,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (closes.length < 2) return const SizedBox.shrink();
    final up = closes.last >= closes.first;
    final line = color ??
        (up ? Colors.green.shade700 : Theme.of(context).colorScheme.error);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(closes: closes, color: line),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> closes;
  final Color color;

  _SparklinePainter({required this.closes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final min = closes.reduce((a, b) => a < b ? a : b);
    final max = closes.reduce((a, b) => a > b ? a : b);
    final span = (max - min) <= 0 ? 1.0 : (max - min);
    final dx = size.width / (closes.length - 1);
    final path = Path();
    for (var i = 0; i < closes.length; i++) {
      final x = i * dx;
      final y =
          size.height - 2 - ((closes[i] - min) / span) * (size.height - 4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.closes.length != closes.length || old.color != color;
}
