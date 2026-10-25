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
/// Below this level (dB, from the 8-bit capture) a frame is near silence.
const _quietFrame = 12.0;

class OngakuSoundEngine {
  OngakuSoundEngine._();

  /// Android 9 or later.
  static final supported = ValueNotifier<bool>(false);
  static final route = ValueNotifier<OutputRoute>(OutputRoute.speaker);

  /// What the Auto layer currently hears.
  static final autoLayer = ValueNotifier<SoundLayer?>(null);

  /// Gains heard while comparing before / after a correction; null the
  /// rest of the time.
  static final preview = ValueNotifier<List<double>?>(null);

  /// Loudness of the music (dB, smoothed), for the automatic crossfade.
  static final loudness = ValueNotifier<double?>(null);

  static bool _started = false;
  static StreamSubscription<List<double>>? _spectrum;
  static List<double>? _average;
  static SoundLayer? _candidate;
  static int _candidateTicks = 0;
  static List<double> _layerNow = List.filled(10, 0);
  static Timer? _blend;

  /// Gains on the session now: the spectrum is captured after them, so
  /// they are taken off before Auto judges the music.
  static List<double> _applied = List.filled(10, 0);

  // Auto: loudness moves and bass jumps, and the style the song's words
  // suggest, all reset with each song.
  static double? _loudMean;
  static double _loudVar = 0;
  static double? _lastBass;
  static double _punch = 0;
  static int _frames = 0;
  static SoundLayer? _hint;

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
      preview.addListener(_push);
      handler.audioPlayer.playingStream.listen((_) => _updateSpectrum());
      handler.mediaItem.distinct((a, b) => a?.id == b?.id).listen((item) {
        _resetAuto();
        _hint = item == null
            ? null
            : layerHintFromText(
                '${item.title} ${item.artist ?? ''} ${item.album ?? ''} '
                '${item.genre ?? ''}',
              );
      });
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
    final comparing = preview.value;
    _applied = comparing ?? combineGains(profile, _layerNow);
    try {
      await OngakuSound.setGains(
        _applied,
        enabled: comparing != null || soundEnabled.value,
      );
      await OngakuSound.setWidening(
        comparing == null && soundEnabled.value && route.value.isHeadphones
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

  static void _resetAuto() {
    _average = null;
    _loudMean = null;
    _loudVar = 0;
    _lastBass = null;
    _punch = 0;
    _frames = 0;
    _candidate = null;
    _candidateTicks = 0;
  }

  static void _onSpectrum(List<double> raw) {
    final enabled = soundEnabled.value || preview.value != null;
    final levels = [
      for (var i = 0; i < raw.length; i++)
        raw[i] - (enabled && i < _applied.length ? _applied[i] : 0),
    ];
    final total = levels.fold<double>(
      0,
      (sum, l) => sum + math.pow(10, l / 10),
    );
    final db = 10 * math.log(total + 1e-9) / math.ln10;
    loudness.value = loudness.value == null
        ? db
        : loudness.value! * 0.7 + db * 0.3;

    // Silence or a very quiet moment (a gap, a fade) says nothing about the
    // style: it no longer pulls the average and the beat towards "quiet".
    if (db < _quietFrame) return;

    _frames++;
    // About 4 frames a second: a 5-second average, quicker at the start
    // of a song so Auto settles within a few seconds.
    final keep = _frames < 20 ? 0.8 : 0.95;
    final average = _average;
    _average = average == null
        ? List<double>.from(levels)
        : [
            for (var i = 0; i < levels.length; i++)
              average[i] * keep + levels[i] * (1 - keep),
          ];
    final mean = _loudMean;
    _loudMean = mean == null ? db : mean * 0.95 + db * 0.05;
    if (mean != null) {
      _loudVar = _loudVar * 0.95 + math.pow(db - mean, 2) * 0.05;
    }
    final bassNow = levels.isEmpty ? 0.0 : levels[0];
    if (_lastBass != null) {
      _punch = _punch * 0.9 + (bassNow - _lastBass!).abs() * 0.1;
    }
    _lastBass = bassNow;

    if (soundLayer.value != SoundLayer.auto) return;
    final heard = classifySpectrum(
      _average!,
      dynamics: _frames > 12 ? math.sqrt(_loudVar) : null,
      punch: _frames > 12 ? _punch : null,
      hint: _hint,
    );
    if (heard == _candidate) {
      _candidateTicks++;
    } else {
      _candidate = heard;
      _candidateTicks = 0;
    }
    // A new style must hold before the layer changes: 3 seconds at the
    // start of a song, then 8 seconds, so it does not flicker.
    final hold = _frames < 40 ? 12 : 32;
    if (_candidateTicks == hold && autoLayer.value != heard) {
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
