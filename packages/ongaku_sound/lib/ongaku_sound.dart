/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Band centres of the calibrated equalizer, in Hz.
const ongakuBandCentres = <double>[
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Kind of audio output the music currently plays on.
enum OutputType { speaker, bluetooth, wired, car }

/// The audio output in use. [id] keys the calibrated profile.
class OutputRoute {
  const OutputRoute(this.type, this.name, this.id);

  factory OutputRoute.fromMap(Map map) => OutputRoute(
    OutputType.values.firstWhere(
      (t) => t.name == map['type'],
      orElse: () => OutputType.speaker,
    ),
    map['name']?.toString() ?? '',
    map['id']?.toString() ?? 'speaker',
  );

  static const speaker = OutputRoute(OutputType.speaker, '', 'speaker');

  final OutputType type;
  final String name;
  final String id;

  /// Headphones are calibrated with the hearing test, the rest with the
  /// microphone.
  bool get isHeadphones =>
      type == OutputType.bluetooth || type == OutputType.wired;

  @override
  bool operator ==(Object other) => other is OutputRoute && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A microphone recording of the sweep played on the output.
class SweepRecording {
  const SweepRecording({
    required this.sampleRate,
    required this.samples,
    required this.sweepStart,
    required this.sweepSamples,
    required this.f1,
    required this.f2,
  });

  final int sampleRate;
  final Float32List samples;
  final int sweepStart;
  final int sweepSamples;
  final double f1;
  final double f2;
}

/// Native side of Ongaku's calibrated sound (Android only).
class OngakuSound {
  const OngakuSound._();

  static const _methods = MethodChannel('ongaku_sound');
  static const _routes = EventChannel('ongaku_sound/route');
  static const _spectrum = EventChannel('ongaku_sound/spectrum');

  /// Android 9 or later: the 10-band equalizer is available.
  static Future<bool> isSupported() async =>
      await _methods.invokeMethod<bool>('isSupported') ?? false;

  /// Applies the effects to the player's audio session.
  static Future<bool> attach(int sessionId) async =>
      await _methods.invokeMethod<bool>('attach', {'sessionId': sessionId}) ??
      false;

  /// Also applies the effects to another session (the crossfade player).
  static Future<bool> attachExtra(int sessionId) async =>
      await _methods.invokeMethod<bool>('attachExtra', {
        'sessionId': sessionId,
      }) ??
      false;

  static Future<void> detachExtra(int sessionId) =>
      _methods.invokeMethod('detachExtra', {'sessionId': sessionId});

  /// Gains in dB, one per band of [ongakuBandCentres].
  static Future<bool> setGains(
    List<double> gains, {
    required bool enabled,
  }) async =>
      await _methods.invokeMethod<bool>('setGains', {
        'gains': gains,
        'enabled': enabled,
      }) ??
      false;

  /// Stereo widening, 0 (off) to 1000.
  static Future<bool> setWidening(int strength) async =>
      await _methods.invokeMethod<bool>('setWidening', {
        'strength': strength,
      }) ??
      false;

  static Future<OutputRoute> route() async => OutputRoute.fromMap(
    await _methods.invokeMapMethod<String, dynamic>('route') ?? const {},
  );

  /// Output changes (headphones connected, Android Auto started...).
  static Stream<OutputRoute> routes() => _routes.receiveBroadcastStream().map(
    (event) => OutputRoute.fromMap(event as Map),
  );

  /// Band levels (dB) of the music playing, about 4 times a second.
  static Stream<List<double>> spectrum() => _spectrum
      .receiveBroadcastStream()
      .map((event) => List<double>.from(event as List));

  /// Ambient noise in dBFS measured by the microphone.
  static Future<double> noiseLevel({int ms = 1500}) async =>
      await _methods.invokeMethod<double>('noiseLevel', {'ms': ms}) ?? 0;

  /// Plays a sine sweep on the output and records it with the microphone.
  static Future<SweepRecording> measure({
    double f1 = 20,
    double f2 = 20000,
    int sweepMs = 6000,
    double level = -6,
  }) async {
    final map = await _methods.invokeMapMethod<String, dynamic>('measure', {
      'f1': f1,
      'f2': f2,
      'sweepMs': sweepMs,
      'level': level,
    });
    return SweepRecording(
      sampleRate: map!['sampleRate'] as int,
      samples: map['samples'] as Float32List,
      sweepStart: map['sweepStart'] as int,
      sweepSamples: map['sweepSamples'] as int,
      f1: (map['f1'] as num).toDouble(),
      f2: (map['f2'] as num).toDouble(),
    );
  }

  /// A test tone; [pan] -1 is left only, 1 right only.
  static Future<void> playTone(
    double frequency, {
    required double level,
    int ms = 800,
    double pan = 0,
  }) => _methods.invokeMethod('playTone', {
    'frequency': frequency,
    'level': level,
    'ms': ms,
    'pan': pan,
  });

  static Future<void> stopTone() => _methods.invokeMethod('stopTone');
}
