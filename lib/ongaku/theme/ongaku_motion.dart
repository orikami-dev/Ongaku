/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/animation.dart';

/// Shared timings, so every part of the app moves at the same pace.
abstract final class OngakuMotion {
  /// Small things: a toast, a chip, a switch.
  static const quick = Duration(milliseconds: 180);

  /// Panels and sheets.
  static const medium = Duration(milliseconds: 300);

  static const curve = Curves.easeOutCubic;
  static const curveIn = Curves.easeInCubic;
}

/// Toasts slide in and out quickly (Musify's took about a quarter second
/// each way and queued up).
const ongakuToastAnimation = AnimationStyle(
  duration: OngakuMotion.quick,
  reverseDuration: Duration(milliseconds: 140),
  curve: OngakuMotion.curve,
  reverseCurve: OngakuMotion.curveIn,
);
