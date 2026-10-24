/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:ui' show DisplayFeature;

import 'package:material_ui/material_ui.dart';

/// The width the phone layouts were drawn for.
const _designWidth = 392.0;

/// How much the whole interface is scaled on this screen: a little smaller
/// on narrow or low resolution phones so nothing is cut, a little larger on
/// wide phones so it does not look sparse. Tablets and open foldables keep
/// 1, their layouts already use the extra room.
double ongakuUiScale(Size size, double devicePixelRatio) {
  final shortest = size.shortestSide;
  if (shortest <= 0 || shortest >= 600) return 1;
  var scale = (shortest / _designWidth).clamp(0.86, 1.04);
  // Screens with few physical pixels (under 720 across) get a smaller
  // interface, so text and artwork keep enough pixels to stay sharp.
  if (shortest * devicePixelRatio < 720) scale = scale.clamp(0.86, 0.94);
  // Short screens (landscape phones, cover screens) never grow.
  if (size.height < 560 && scale > 1) scale = 1;
  // Close to the drawn width: left as is.
  if ((scale - 1).abs() < 0.03) return 1;
  return (scale * 100).roundToDouble() / 100;
}

/// Scales the whole app as Android's "display size" setting would, from
/// the screen size and resolution of the device.
class OngakuUiScale extends StatelessWidget {
  const OngakuUiScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = ongakuUiScale(media.size, media.devicePixelRatio);
    if (scale == 1) return child;

    EdgeInsets down(EdgeInsets insets) => insets / scale;
    final scaled = media.copyWith(
      size: media.size / scale,
      devicePixelRatio: media.devicePixelRatio * scale,
      padding: down(media.padding),
      viewPadding: down(media.viewPadding),
      viewInsets: down(media.viewInsets),
      systemGestureInsets: down(media.systemGestureInsets),
      displayFeatures: [
        for (final feature in media.displayFeatures)
          DisplayFeature(
            bounds: Rect.fromLTRB(
              feature.bounds.left / scale,
              feature.bounds.top / scale,
              feature.bounds.right / scale,
              feature.bounds.bottom / scale,
            ),
            type: feature.type,
            state: feature.state,
          ),
      ],
    );

    return MediaQuery(
      data: scaled,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: scaled.size.width,
          maxWidth: scaled.size.width,
          minHeight: scaled.size.height,
          maxHeight: scaled.size.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: child,
          ),
        ),
      ),
    );
  }
}
