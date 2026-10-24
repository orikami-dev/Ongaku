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
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';

/// Opens a small panel that grows out of the button at [anchor] (the
/// context of the button), above or below it, like iOS menus. A tap outside
/// closes it.
Future<T?> showOngakuPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 320,
  bool dark = true,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(anchor, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject() as RenderBox;
  final rect = box == null
      ? Rect.fromCenter(
          center: overlay.size.center(Offset.zero),
          width: 0,
          height: 0,
        )
      : box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return navigator.push<T>(
    _PopoverRoute<T>(
      anchor: rect,
      builder: builder,
      width: width,
      dark: dark,
      theme: Theme.of(anchor),
    ),
  );
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.width,
    required this.dark,
    required this.theme,
  });

  final Rect anchor;
  final WidgetBuilder builder;
  final double width;
  final bool dark;
  final ThemeData theme;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.18);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'close';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => OngakuMotion.quick;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safe = media.padding;
    final w = math.min(width, screen.width - 24);
    final spaceBelow = screen.height - anchor.bottom - safe.bottom;
    final spaceAbove = anchor.top - safe.top;
    final below = spaceBelow >= spaceAbove;
    final left = (anchor.center.dx - w / 2).clamp(12.0, screen.width - w - 12);
    // The panel grows from the button: its origin is the button's centre.
    final originX = ((anchor.center.dx - left) / w * 2 - 1).clamp(-1.0, 1.0);
    final data = dark
        ? theme.copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: theme.colorScheme.primary,
              brightness: Brightness.dark,
            ),
          )
        : theme;
    final scheme = data.colorScheme;

    final panel = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(160, (below ? spaceBelow : spaceAbove) - 20),
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: ColoredBox(
            color: (dark ? const Color(0xFF26262A) : scheme.surface).withValues(
              alpha: 0.88,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: scheme.onSurface),
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: OngakuMotion.curveIn,
    );
    return Theme(
      data: data,
      child: Stack(
        children: [
          Positioned(
            left: left,
            width: w,
            top: below ? anchor.bottom + 8 : null,
            bottom: below ? null : screen.height - anchor.top + 8,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0, 0.6),
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.4, end: 1).animate(curved),
                alignment: Alignment(originX, below ? -1 : 1),
                child: panel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
