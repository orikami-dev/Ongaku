/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:musify/ongaku/sound/sound_math.dart';

/// How a profile was made.
enum ProfileMethod { microphone, hearing }

/// The calibrated profile of one output (phone speaker, car, a model of
/// earbuds...).
class SoundProfile {
  const SoundProfile({
    required this.gains,
    required this.method,
    required this.date,
    required this.label,
  });

  factory SoundProfile.fromMap(Map map) => SoundProfile(
    gains: [
      for (final g in map['gains'] as List? ?? const []) (g as num).toDouble(),
    ],
    method: map['method'] == 'hearing'
        ? ProfileMethod.hearing
        : ProfileMethod.microphone,
    date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
    label: map['label']?.toString() ?? '',
  );

  final List<double> gains;
  final ProfileMethod method;
  final DateTime date;

  /// Output name shown in the list of profiles.
  final String label;

  Map<String, dynamic> toMap() => {
    'gains': gains,
    'method': method.name,
    'date': date.toIso8601String(),
    'label': label,
  };
}

/// Smooth transitions between songs.
enum CrossfadeMode { off, auto, manual }

Box get _box => Hive.box('settings');

T _read<T>(String key, T fallback) {
  try {
    final value = _box.get(key);
    return value is T ? value : fallback;
  } catch (_) {
    return fallback;
  }
}

void _write(String key, Object value) {
  try {
    _box.put(key, value);
  } catch (_) {}
}

/// Calibrated sound on or off.
final ValueNotifier<bool> soundEnabled = ValueNotifier<bool>(
  _read('ongakuSoundEnabled', true),
)..addListener(() => _write('ongakuSoundEnabled', soundEnabled.value));

/// The layer over the profiles.
final ValueNotifier<SoundLayer> soundLayer = ValueNotifier<SoundLayer>(
  SoundLayer.values.firstWhere(
    (l) => l.name == _read('ongakuSoundLayer', 'none'),
    orElse: () => SoundLayer.none,
  ),
)..addListener(() => _write('ongakuSoundLayer', soundLayer.value.name));

/// Stereo widening on headphones, 0 to 1000.
final ValueNotifier<int> soundWidening = ValueNotifier<int>(
  _read('ongakuSoundWidening', 0),
)..addListener(() => _write('ongakuSoundWidening', soundWidening.value));

/// Profiles by output id.
final ValueNotifier<Map<String, SoundProfile>> soundProfiles =
    ValueNotifier<Map<String, SoundProfile>>({
      for (final e in (_read<Map>('ongakuSoundProfiles', const {})).entries)
        if (e.value is Map)
          e.key.toString(): SoundProfile.fromMap(e.value as Map),
    })..addListener(
      () => _write('ongakuSoundProfiles', <String, dynamic>{
        for (final e in soundProfiles.value.entries) e.key: e.value.toMap(),
      }),
    );

void saveSoundProfile(String outputId, SoundProfile profile) {
  soundProfiles.value = {...soundProfiles.value, outputId: profile};
}

void deleteSoundProfile(String outputId) {
  soundProfiles.value = {...soundProfiles.value}..remove(outputId);
}

final ValueNotifier<CrossfadeMode> crossfadeMode = ValueNotifier<CrossfadeMode>(
  CrossfadeMode.values.firstWhere(
    (m) => m.name == _read('ongakuCrossfadeMode', 'off'),
    orElse: () => CrossfadeMode.off,
  ),
)..addListener(() => _write('ongakuCrossfadeMode', crossfadeMode.value.name));

/// Length of a manual crossfade, in seconds.
final ValueNotifier<double> crossfadeSeconds = ValueNotifier<double>(
  _read<num>('ongakuCrossfadeSeconds', 6).toDouble(),
)..addListener(() => _write('ongakuCrossfadeSeconds', crossfadeSeconds.value));
