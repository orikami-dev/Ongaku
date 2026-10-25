/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';

/// Which way a swipe on the artwork goes, if it is far or fast enough.
/// A swipe to the left plays the next song, to the right the previous one.
int swipeSkipDirection(double dx, double velocity, double width) {
  const flingVelocity = 700.0;
  if (velocity <= -flingVelocity || dx <= -width * 0.28) return 1;
  if (velocity >= flingVelocity || dx >= width * 0.28) return -1;
  return 0;
}

/// The artwork follows the finger sideways: let go far enough and it flies
/// out while the next (or previous) song comes in from the other side.
class OngakuSwipeToSkip extends StatefulWidget {
  const OngakuSwipeToSkip({
    super.key,
    required this.child,
    required this.onNext,
    required this.onPrevious,
  });

  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  State<OngakuSwipeToSkip> createState() => _OngakuSwipeToSkipState();
}

class _OngakuSwipeToSkipState extends State<OngakuSwipeToSkip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 1;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  Future<void> _end(DragEndDetails details) async {
    final direction = swipeSkipDirection(
      _dx.value,
      details.primaryVelocity ?? 0,
      _width,
    );
    if (direction == 0) {
      await _dx.animateTo(
        0,
        duration: OngakuMotion.medium,
        curve: Curves.easeOutBack,
      );
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    await _dx.animateTo(
      -direction * _width,
      duration: OngakuMotion.quick,
      curve: Curves.easeInCubic,
    );
    if (!mounted) return;
    direction > 0 ? widget.onNext() : widget.onPrevious();
    _dx.value = direction * _width * 0.6;
    await _dx.animateTo(
      0,
      duration: OngakuMotion.slow,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite ? constraints.maxWidth : 400;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dx.stop(),
          onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
          onHorizontalDragEnd: _end,
          child: AnimatedBuilder(
            animation: _dx,
            builder: (context, child) {
              final t = (_dx.value.abs() / _width).clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - t * 0.6,
                child: Transform.translate(
                  offset: Offset(_dx.value, 0),
                  child: Transform.rotate(
                    angle: _dx.value / _width * 0.06,
                    child: child,
                  ),
                ),
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
