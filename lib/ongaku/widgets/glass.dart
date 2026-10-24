/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// Translucent blurred material ("glass"), used by the tab bar, the sidebar
/// and the mini player.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.height,
    this.borderRadius = 0,
    this.showBorder = true,
    this.showShadow = true,
    this.opacity,
  });

  final Widget child;
  final double? height;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final double? opacity;

  static Color tintOf(BuildContext context, {double? opacity}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: opacity ?? 0.82)
        : const Color(0xFFF9F9F9).withValues(alpha: opacity ?? 0.86);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);

    final content = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: tintOf(context, opacity: opacity),
          borderRadius: radius,
          border: showBorder && borderRadius > 0
              ? Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.5,
                )
              : null,
        ),
        child: child,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: showShadow && borderRadius > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: borderRadius > 0
          ? ClipRSuperellipse(borderRadius: radius, child: content)
          : ClipRect(child: content),
    );
  }
}
