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
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/sound/sound_math.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/services/audio_service.dart';
import 'package:ongaku_sound/ongaku_sound.dart';
import 'package:permission_handler/permission_handler.dart';

/// Applies the calibrated sound: the profile of the output in use (phone
/// speaker, earbuds, car with Android Auto) plus the chosen layer, on the
/// player's audio session. In Auto, the layer follows the music.
class OngakuSoundEngine {
  OngakuSoundEngine._();

  /// Android 9 or later.
  static final supported = ValueNotifier<bool>(false);
  static final route = ValueNotifier<OutputRoute>(OutputRoute.speaker);

  /// What the Auto layer currently hears.
  static final autoLayer = ValueNotifier<SoundLayer?>(null);

  /// Loudness of the music (dB, smoothed), for the automatic crossfade.
  static final loudness = ValueNotifier<double?>(null);

  static bool _started = false;
  static StreamSubscription<List<double>>? _spectrum;
  static List<double>? _average;
  static SoundLayer? _candidate;
  static int _candidateTicks = 0;
  static List<double> _layerNow = List.filled(10, 0);
  static Timer? _blend;

  /// Called once the audio handler exists (Android only).
  static Future<void> start(MusifyAudioHandler handler) async {
    if (_started || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    try {
      supported.value = await OngakuSound.isSupported();
      if (!supported.value) return;
      handler.audioPlayer.androidAudioSessionIdStream.listen((id) async {
        if (id == null) return;
        await OngakuSound.attach(id);
        await _push();
      });
      OngakuSound.routes().listen((r) {
        route.value = r;
        _push();
      });
      for (final notifier in <Listenable>[
        soundEnabled,
        soundLayer,
        soundWidening,
        soundProfiles,
        crossfadeMode,
      ]) {
        notifier.addListener(_settingsChanged);
      }
      handler.audioPlayer.playingStream.listen((_) => _updateSpectrum());
      _layerNow = _targetLayer();
      await _updateSpectrum();
    } catch (e, stackTrace) {
      logger.log(
        'Ongaku sound: start failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  static void _settingsChanged() {
    _blendTo(_targetLayer());
    _updateSpectrum();
  }

  static List<double> _targetLayer() {
    final layer = soundLayer.value;
    if (layer != SoundLayer.auto) return layerGains[layer]!;
    final heard = autoLayer.value ?? SoundLayer.pop;
    // Auto stays a little gentler than the fixed layers.
    return [for (final g in layerGains[heard]!) g * 0.8];
  }

  /// Moves the layer to [target] over two seconds, so changes are smooth.
  static void _blendTo(List<double> target) {
    _blend?.cancel();
    final from = List<double>.from(_layerNow);
    var step = 0;
    const steps = 10;
    _blend = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      step++;
      final t = step / steps;
      _layerNow = [
        for (var i = 0; i < from.length; i++)
          from[i] + (target[i] - from[i]) * t,
      ];
      _push();
      if (step >= steps) timer.cancel();
    });
  }

  static Future<void> _push() async {
    if (!supported.value) return;
    final profile =
        soundProfiles.value[route.value.id]?.gains ??
        List<double>.filled(10, 0);
    try {
      await OngakuSound.setGains(
        combineGains(profile, _layerNow),
        enabled: soundEnabled.value,
      );
      await OngakuSound.setWidening(
        soundEnabled.value && route.value.isHeadphones
            ? soundWidening.value
            : 0,
      );
    } catch (e) {
      logger.log('Ongaku sound: apply failed', error: e);
    }
  }

  /// Listens to the music while Auto (layer or crossfade) needs it.
  static Future<void> _updateSpectrum() async {
    final wanted =
        (soundEnabled.value && soundLayer.value == SoundLayer.auto) ||
        crossfadeMode.value == CrossfadeMode.auto;
    final granted = wanted && await Permission.microphone.isGranted;
    if (granted && _spectrum == null) {
      _spectrum = OngakuSound.spectrum().listen(
        _onSpectrum,
        onError: (Object e) => logger.log('Ongaku sound: spectrum', error: e),
      );
    } else if (!granted && _spectrum != null) {
      await _spectrum?.cancel();
      _spectrum = null;
      _average = null;
      loudness.value = null;
    }
  }

  static void _onSpectrum(List<double> levels) {
    // About 4 frames a second: a 5-second average.
    const keep = 0.95;
    final average = _average;
    _average = average == null
        ? List<double>.from(levels)
        : [
            for (var i = 0; i < levels.length; i++)
              average[i] * keep + levels[i] * (1 - keep),
          ];
    final total = levels.fold<double>(
      0,
      (sum, l) => sum + math.pow(10, l / 10),
    );
    final db = 10 * math.log(total + 1e-9) / math.ln10;
    loudness.value = loudness.value == null
        ? db
        : loudness.value! * 0.7 + db * 0.3;

    if (soundLayer.value != SoundLayer.auto) return;
    final heard = classifySpectrum(_average!);
    if (heard == _candidate) {
      _candidateTicks++;
    } else {
      _candidate = heard;
      _candidateTicks = 0;
    }
    // A new style must hold for about 8 seconds before the layer changes.
    if (_candidateTicks == 32 && autoLayer.value != heard) {
      autoLayer.value = heard;
      _blendTo(_targetLayer());
    }
  }

  /// Asks for the microphone (measurement, Auto). True when granted.
  static Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    await _updateSpectrum();
    return status.isGranted;
  }
}
