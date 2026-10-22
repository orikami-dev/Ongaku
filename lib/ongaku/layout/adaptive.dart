/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:material_ui/material_ui.dart';

/// Material 3 window size classes, used to pick the navigation style and
/// page layouts (phones, unfolded foldables, tablets, desktops).
enum WindowSize {
  /// Phones in portrait, folded foldables (< 600dp).
  compact,

  /// Unfolded book-style foldables, small tablets, phones in landscape.
  medium,

  /// Tablets in landscape, desktops (>= 840dp).
  expanded,

  /// Large desktop windows (>= 1200dp): sidebar with labels.
  large,
}

WindowSize windowSizeOf(BuildContext context) =>
    windowSizeForWidth(MediaQuery.sizeOf(context).width);

WindowSize windowSizeForWidth(double width) {
  if (width < 600) return WindowSize.compact;
  if (width < 840) return WindowSize.medium;
  if (width < 1200) return WindowSize.expanded;
  return WindowSize.large;
}

/// A fold or hinge that splits the screen in two usable halves.
///
/// Flat foldables (e.g. an unfolded Galaxy Z Fold) report a zero-width fold
/// that content can safely cross, so it is ignored unless the device is half
/// opened. Physical hinges (Surface Duo style) always split the screen.
class FoldSplit {
  const FoldSplit({required this.axis, required this.bounds});

  /// [Axis.horizontal]: panes side by side (book posture, vertical hinge).
  /// [Axis.vertical]: panes stacked (tabletop posture, horizontal hinge).
  final Axis axis;

  /// The hinge area, in logical pixels of the [MediaQuery] it was read from.
  final Rect bounds;

  bool get isSideBySide => axis == Axis.horizontal;
}

FoldSplit? foldSplitOf(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  return foldSplitFrom(mediaQuery.displayFeatures, mediaQuery.size);
}

FoldSplit? foldSplitFrom(List<DisplayFeature> features, Size screen) {
  for (final feature in features) {
    final isHinge = feature.type == DisplayFeatureType.hinge;
    final isFold = feature.type == DisplayFeatureType.fold;
    if (!isHinge && !isFold) continue;

    final halfOpened = feature.state == DisplayFeatureState.postureHalfOpened;
    final occludes = feature.bounds.width > 0 && feature.bounds.height > 0;
    if (!(halfOpened || occludes || isHinge)) continue;

    final b = feature.bounds;
    final isVerticalLine = b.height >= screen.height * 0.9;
    final isHorizontalLine = b.width >= screen.width * 0.9;
    if (isVerticalLine) {
      return FoldSplit(axis: Axis.horizontal, bounds: b);
    }
    if (isHorizontalLine) {
      return FoldSplit(axis: Axis.vertical, bounds: b);
    }
  }
  return null;
}

/// Lays out two panes on each side of a fold/hinge when there is one,
/// otherwise uses [fallback]. Panes never overlap the hinge.
class FoldAwareTwoPane extends StatelessWidget {
  const FoldAwareTwoPane({
    super.key,
    required this.first,
    required this.second,
    required this.fallback,
    this.origin = Offset.zero,
  });

  final Widget first;
  final Widget second;
  final Widget fallback;

  /// Top-left corner of this widget on screen, used to place the hinge.
  final Offset origin;

  @override
  Widget build(BuildContext context) {
    final split = foldSplitOf(context);
    if (split == null) return fallback;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Convert the hinge (screen coordinates) to this widget's coordinates.
        final hinge = split.bounds.shift(-origin);

        if (split.isSideBySide) {
          final firstWidth = hinge.left.clamp(0.0, constraints.maxWidth);
          final secondStart = hinge.right.clamp(0.0, constraints.maxWidth);
          if (firstWidth < 200 || constraints.maxWidth - secondStart < 200) {
            return fallback;
          }
          return Row(
            children: [
              SizedBox(width: firstWidth, child: first),
              SizedBox(width: secondStart - firstWidth),
              Expanded(child: second),
            ],
          );
        }

        final firstHeight = hinge.top.clamp(0.0, constraints.maxHeight);
        final secondStart = hinge.bottom.clamp(0.0, constraints.maxHeight);
        if (firstHeight < 160 || constraints.maxHeight - secondStart < 160) {
          return fallback;
        }
        return Column(
          children: [
            SizedBox(height: firstHeight, child: first),
            SizedBox(height: secondStart - firstHeight),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
