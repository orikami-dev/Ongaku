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

import 'package:musify/ongaku/sound/crossfade.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/services/audio_service.dart';

/// Starts the calibrated sound and the smooth transitions (mobile).
void ongakuStartSound(MusifyAudioHandler handler) {
  unawaited(OngakuSoundEngine.start(handler));
  OngakuCrossfade.start(handler);
}
