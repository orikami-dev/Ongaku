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
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/settings_manager.dart';

/// Starts the calibrated sound and the smooth transitions (mobile).
void ongakuStartSound(MusifyAudioHandler handler) {
  // Musify's own equalizer is hidden in Ongaku: keep it off so it never
  // stacks with the calibrated sound.
  // Musify reads this value when it sets its equalizer up.
  if (equalizerEnabled.value) {
    equalizerEnabled.value = false;
    unawaited(addOrUpdateData<bool>('settings', 'equalizerEnabled', false));
    unawaited(handler.setEqualizerEnabled(false));
  }
  unawaited(OngakuSoundEngine.start(handler));
  OngakuCrossfade.start(handler);
}
