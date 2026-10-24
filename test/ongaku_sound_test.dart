import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/sound/sound_math.dart';

/// The sweep the plugin plays (same formula as OngakuSoundPlugin.measure).
Float64List sweep(int rate, int samples, double f1, double f2) {
  final duration = samples / rate;
  final k = math.log(f2 / f1);
  final fade = rate ~/ 50;
  return Float64List.fromList([
    for (var i = 0; i < samples; i++)
      math.sin(
            2 *
                math.pi *
                f1 *
                duration /
                k *
                (math.exp(i / rate / duration * k) - 1),
          ) *
          0.5 *
          (i < fade ? i / fade : 1) *
          (i > samples - fade ? (samples - i) / fade : 1),
  ]);
}

Float32List record(
  Float64List signal, {
  required int delay,
  double noise = 0.001,
  double Function(double)? filter,
}) {
  final random = math.Random(1);
  final out = Float32List(signal.length + delay + 24000);
  for (var i = 0; i < out.length; i++) {
    final j = i - delay;
    final v = j >= 0 && j < signal.length ? signal[j] : 0.0;
    out[i] =
        (filter == null ? v : filter(v)) + (random.nextDouble() - 0.5) * noise;
  }
  return out;
}

void main() {
  const rate = 48000;
  const samples = rate * 3;
  final s = sweep(rate, samples, 20, 20000);

  test('a flat output measures flat, whatever the latency', () {
    final result = analyseSweep(
      recording: record(s, delay: 24000 + 3217),
      sampleRate: rate,
      sweepSamples: samples,
      f1: 20,
      f2: 20000,
    );
    expect(result.error, isNull);
    for (final level in result.response.sublist(1, 9)) {
      expect(level.abs(), lessThan(1.5));
    }
  });

  test('a dull output (low-pass) gets its highs back', () {
    var state = 0.0;
    // One-pole low-pass around 2 kHz.
    final alpha = 1 - math.exp(-2 * math.pi * 2000 / rate);
    final result = analyseSweep(
      recording: record(
        s,
        delay: 30000,
        filter: (v) => state += alpha * (v - state),
      ),
      sampleRate: rate,
      sweepSamples: samples,
      f1: 20,
      f2: 20000,
    );
    expect(result.error, isNull);
    expect(result.response[8], lessThan(-8));
    final correction = correctionFromResponse(result.response);
    expect(correction[8], greaterThan(3));
    expect(correction[2].abs(), lessThan(3));
  });

  test('noise instead of the sweep is refused', () {
    final random = math.Random(2);
    final noise = Float32List.fromList([
      for (var i = 0; i < samples + 48000; i++)
        (random.nextDouble() - 0.5) * 0.5,
    ]);
    final result = analyseSweep(
      recording: noise,
      sampleRate: rate,
      sweepSamples: samples,
      f1: 20,
      f2: 20000,
    );
    expect(result.error, isNotNull);
  });

  test('hearing thresholds raise the bands heard worse', () {
    // Normal hearing, except 4 kHz needs 20 dB more.
    const normal = [57.0, 35, 20, 9, 2, 0, -3, -7, 10, 38];
    final thresholds = {
      for (final band in hearingBands)
        band: -60.0 + normal[band] + (band == 7 ? 20 : 0),
    };
    final gains = profileFromThresholds(thresholds);
    expect(gains[7], greaterThan(4));
    expect(gains[4].abs(), lessThan(1.5));
  });

  test('staircase finds the threshold', () {
    final stair = ToneStaircase();
    const threshold = -42.0;
    while (!stair.done) {
      final level = stair.next();
      if (level >= threshold) stair.heard();
    }
    expect((stair.threshold - threshold).abs(), lessThanOrEqualTo(5));
  });

  test('layers add up and stay within limits', () {
    final gains = combineGains(
      List.filled(10, 10),
      layerGains[SoundLayer.hipHop]!,
    );
    expect(gains.every((g) => g <= 12), isTrue);
  });

  test('bass-heavy music picks a bass layer', () {
    final layer = classifySpectrum([30, 30, 28, 18, 15, 14, 13, 10, 5, 0]);
    expect([SoundLayer.hipHop, SoundLayer.electro], contains(layer));
  });
}
