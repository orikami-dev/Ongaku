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
import 'package:musify/ongaku/theme/artwork_palette.dart';

/// Slowly moving colour fields taken from the current artwork, like the
/// Apple Music player and lyrics backgrounds. Only gradients are painted
/// (no blur), so it stays smooth on any phone.
class ArtworkBackground extends StatefulWidget {
  const ArtworkBackground({super.key, this.dim = 0, this.child});

  /// Extra darkening, 0 to 1, for panels that sit on top of the background.
  final double dim;
  final Widget? child;

  @override
  State<ArtworkBackground> createState() => _ArtworkBackgroundState();
}

class _ArtworkBackgroundState extends State<ArtworkBackground>
    with TickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  )..repeat();

  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  late ArtworkPalette _from = currentArtworkPalette.value;
  late ArtworkPalette _to = currentArtworkPalette.value;

  @override
  void initState() {
    super.initState();
    currentArtworkPalette.addListener(_onPalette);
  }

  void _onPalette() {
    _from = ArtworkPalette.lerp(
      _from,
      _to,
      Curves.easeInOut.transform(_fade.value),
    );
    _to = currentArtworkPalette.value;
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    currentArtworkPalette.removeListener(_onPalette);
    _drift.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FieldsPainter(
          drift: _drift,
          fade: _fade,
          palette: () => ArtworkPalette.lerp(
            _from,
            _to,
            Curves.easeInOut.transform(_fade.value),
          ),
          dim: widget.dim,
        ),
        child: widget.child,
      ),
    );
  }
}

class _FieldsPainter extends CustomPainter {
  _FieldsPainter({
    required this.drift,
    required Animation<double> fade,
    required this.palette,
    required this.dim,
  }) : super(repaint: Listenable.merge([drift, fade]));

  final Animation<double> drift;
  final ArtworkPalette Function() palette;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = palette().colors;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colors[0]);

    final t = drift.value * 2 * math.pi;
    final extent = math.max(size.width, size.height);
    // Each field follows its own slow loop.
    final fields = [
      (colors[1], 0.25 + 0.18 * math.sin(t), 0.22 + 0.14 * math.cos(t), 0.85),
      (
        colors[2],
        0.80 + 0.14 * math.cos(t + 1.7),
        0.40 + 0.20 * math.sin(t + 1.1),
        0.75,
      ),
      (
        colors[3],
        0.40 + 0.22 * math.sin(t + 3.3),
        0.85 + 0.12 * math.cos(t + 2.4),
        0.80,
      ),
      (
        colors[1],
        0.90 + 0.08 * math.sin(t + 4.4),
        0.95 + 0.10 * math.cos(t + 0.6),
        0.55,
      ),
    ];

    for (final (color, fx, fy, radius) in fields) {
      final center = Offset(fx * size.width, fy * size.height);
      final r = radius * extent;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.9),
              color.withValues(alpha: 0.35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // Keep white text readable whatever the artwork.
    canvas.drawRect(
      rect,
      Paint()..color = Colors.black.withValues(alpha: 0.18 + 0.5 * dim),
    );
  }

  @override
  bool shouldRepaint(_FieldsPainter oldDelegate) => oldDelegate.dim != dim;
}
