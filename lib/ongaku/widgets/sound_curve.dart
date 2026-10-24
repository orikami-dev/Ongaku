/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/sound/sound_math.dart';

/// One curve of [SoundCurve], in dB per band.
class CurveSeries {
  const CurveSeries(this.values, this.color, {this.fill = false});

  final List<double> values;
  final Color color;
  final bool fill;
}

/// Gains (or a response) across the 10 bands, as smooth curves around a
/// 0 dB line, with the frequencies underneath.
class SoundCurve extends StatelessWidget {
  const SoundCurve({
    super.key,
    required this.series,
    this.range = 12,
    this.height = 140,
  });

  final List<CurveSeries> series;
  final double range;
  final double height;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _CurvePainter(
              series,
              range,
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in ['31', '125', '500', '2k', '8k', '16k'])
              Text(label, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.series, this.range, this.grid);

  final List<CurveSeries> series;
  final double range;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), gridPaint);
    for (final f in [0.25, 0.75]) {
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        gridPaint..color = grid.withValues(alpha: grid.a * 0.5),
      );
    }

    for (final s in series) {
      if (s.values.isEmpty) continue;
      final points = [
        for (var i = 0; i < bandCentres.length; i++)
          Offset(
            size.width * i / (bandCentres.length - 1),
            mid - (i < s.values.length ? s.values[i] : 0).clamp(-range, range) /
                    range *
                    (size.height / 2 - 4),
          ),
      ];
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final p0 = points[math.max(0, i - 1)];
        final p1 = points[i];
        final p2 = points[i + 1];
        final p3 = points[math.min(points.length - 1, i + 2)];
        path.cubicTo(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
          p2.dx,
          p2.dy,
        );
      }
      if (s.fill) {
        final area = Path.from(path)
          ..lineTo(size.width, mid)
          ..lineTo(0, mid)
          ..close();
        canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: 0.18));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.series != series || old.range != range || old.grid != grid;
}
