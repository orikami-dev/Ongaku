/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:math' as math;
import 'dart:typed_data';

/// Band centres of the calibrated equalizer, in Hz (same as the plugin).
const bandCentres = <double>[
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

const _bands = 10;

/// Sound layers on top of the calibrated profile.
enum SoundLayer {
  none,
  auto,
  rock,
  pop,
  hipHop,
  electro,
  classical,
  jazz,
  vocal,
}

/// Fixed layers, in dB per band (31 Hz ... 16 kHz).
const layerGains = <SoundLayer, List<double>>{
  SoundLayer.none: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  SoundLayer.rock: [3, 3, 2, 0, -1, -1, 1, 2, 3, 3],
  SoundLayer.pop: [1, 2, 1, 0, -1, 0, 1, 2, 2, 1],
  SoundLayer.hipHop: [5, 5, 3, 1, 0, -1, 0, 1, 1, 1],
  SoundLayer.electro: [5, 4, 2, 0, -1, 0, 1, 2, 3, 4],
  SoundLayer.classical: [2, 1, 0, 0, 0, 0, 0, 0, 1, 1],
  SoundLayer.jazz: [2, 2, 1, 1, 0, -1, 0, 1, 2, 2],
  SoundLayer.vocal: [-3, -2, -1, 0, 1, 2, 3, 2, 0, -1],
};

/// Final gains: the output's profile plus the layer, within ±12 dB.
List<double> combineGains(List<double> profile, List<double> layer) => [
  for (var i = 0; i < _bands; i++)
    (_at(profile, i) + _at(layer, i)).clamp(-12.0, 12.0),
];

double _at(List<double> list, int i) => i < list.length ? list[i] : 0;

// --- Microphone measurement -----------------------------------------------

/// Why a measurement can't be used.
enum MeasureError { tooQuiet, tooNoisy }

class MeasureResult {
  const MeasureResult.ok(this.response) : error = null;
  const MeasureResult.failed(MeasureError this.error) : response = const [];

  /// Level per band in dB, relative to the mid bands (250 Hz - 4 kHz).
  final List<double> response;
  final MeasureError? error;
}

/// Frequency response of an output from the microphone recording of an
/// exponential sine sweep (Farina's method): the recording convolved with
/// the inverse sweep gives the impulse response, whose spectrum is read
/// per octave band.
MeasureResult analyseSweep({
  required Float32List recording,
  required int sampleRate,
  required int sweepSamples,
  required double f1,
  required double f2,
}) {
  final n = sweepSamples;
  final duration = n / sampleRate;
  final k = math.log(f2 / f1);

  // Inverse filter: the sweep reversed, with a 6 dB/octave tilt.
  final inverse = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final original = (n - 1 - i) / sampleRate;
    final phase =
        2 *
        math.pi *
        f1 *
        duration /
        k *
        (math.exp(original / duration * k) - 1);
    inverse[i] = math.sin(phase) * math.exp(-t * k / duration);
  }

  final size = _nextPow2(recording.length + n);
  final b = _Complex(size)
    ..setReal(inverse)
    ..fft();
  final a = _Complex(size)
    ..setReal(recording)
    ..fft()
    ..multiply(b)
    ..fft(inverse: true);
  final ir = a.re;

  // The main peak is the direct sound, wherever the output's latency put it.
  var peak = 0;
  var peakValue = 0.0;
  for (var i = 0; i < size; i++) {
    final v = ir[i].abs();
    if (v > peakValue) {
      peakValue = v;
      peak = i;
    }
  }
  // Noise: the part of the response well before the direct sound.
  var noise = 0.0;
  var count = 0;
  for (var i = 0; i < peak - sampleRate ~/ 10; i++) {
    noise += ir[i] * ir[i];
    count++;
  }
  final noiseRms = count == 0 ? 0.0 : math.sqrt(noise / count);
  if (peakValue == 0) return const MeasureResult.failed(MeasureError.tooQuiet);
  if (noiseRms > 0 && 20 * _log10(peakValue / noiseRms) < 25) {
    return const MeasureResult.failed(MeasureError.tooNoisy);
  }

  // 2 ms before the peak to 80 ms after: direct sound and early room.
  final before = sampleRate * 2 ~/ 1000;
  final after = sampleRate * 80 ~/ 1000;
  const fftSize = 1 << 14;
  final window = _Complex(fftSize);
  for (var i = -before; i < after; i++) {
    final index = peak + i;
    if (index < 0 || index >= size) continue;
    final taper = i < 0
        ? 0.5 - 0.5 * math.cos(math.pi * (i + before) / before)
        : (i > after * 0.7
              ? 0.5 +
                    0.5 * math.cos(math.pi * (i - after * 0.7) / (after * 0.3))
              : 1.0);
    window.re[i + before] = ir[index] * taper;
  }
  window.fft();

  final binHz = sampleRate / fftSize;
  final levels = <double>[];
  for (final centre in bandCentres) {
    final lo = (centre / math.sqrt2 / binHz).floor().clamp(1, fftSize ~/ 2);
    final hi = (centre * math.sqrt2 / binHz).ceil().clamp(lo + 1, fftSize ~/ 2);
    var power = 0.0;
    for (var bin = lo; bin < hi; bin++) {
      power +=
          window.re[bin] * window.re[bin] + window.im[bin] * window.im[bin];
    }
    levels.add(10 * _log10(power / (hi - lo) + 1e-20));
  }
  final reference = _mean(levels.sublist(3, 8));
  return MeasureResult.ok([for (final l in levels) l - reference]);
}

/// Correction for a measured response: flattens it gently, cuts more
/// readily than it boosts, and never pushes bands the output can't play
/// (a phone speaker has no 31 Hz).
List<double> correctionFromResponse(List<double> response) {
  final raw = <double>[];
  for (var i = 0; i < _bands; i++) {
    final deviation = _at(response, i);
    var gain = -deviation * 0.8;
    // Far below the rest: the output can't play it, boosting only distorts.
    if (deviation < -18) gain = 2;
    final maxBoost = (i <= 1 || i == _bands - 1) ? 3.0 : 6.0;
    raw.add(gain.clamp(-10.0, maxBoost));
  }
  return _smooth(raw);
}

// --- Hearing test -------------------------------------------------------

/// Bands played in the hearing test (31 Hz is too low for earbuds).
const hearingBands = [1, 2, 3, 4, 5, 6, 7, 8, 9];

/// Typical hearing threshold of each band relative to 1 kHz, in dB.
const _normalThreshold = <double>[57, 35, 20, 9, 2, 0, -3, -7, 10, 38];

/// Profile from the hearing thresholds (dBFS) per band: where the listener
/// needs more level than usual (ears and earbuds together), the band is
/// raised by half the difference, like hearing-aid fitting.
List<double> profileFromThresholds(Map<int, double> thresholds) {
  final relative = <int, double>{
    for (final e in thresholds.entries)
      e.key: e.value - _normalThreshold[e.key],
  };
  final mids = [
    for (final i in [4, 5, 6]) ?relative[i],
  ];
  final reference = mids.isEmpty ? 0.0 : _mean(mids);
  final gains = <double>[];
  for (var i = 0; i < _bands; i++) {
    final value = relative[i] ?? relative[i + 1];
    if (value == null) {
      gains.add(0);
      continue;
    }
    final maxBoost = i == _bands - 1 ? 6.0 : 8.0;
    gains.add(((value - reference) * 0.5).clamp(-4.0, maxBoost));
  }
  return _smooth(gains);
}

/// One band of the hearing test: the level rises until the listener hears
/// the tone, drops, then rises in finer steps; the threshold is the mean of
/// the two answers.
class ToneStaircase {
  ToneStaircase({this.start = -70, this.ceiling = -6});

  final double start;
  final double ceiling;

  double _level = double.nan;
  double? _first;
  double? _second;

  double get level => _level.isNaN ? start : _level;
  bool get done => _second != null || _level >= ceiling;

  /// Threshold in dBFS once [done]; the ceiling when never heard.
  double get threshold =>
      _second == null ? (_first ?? ceiling) : (_first! + _second!) / 2;

  /// Level of the next tone.
  double next() {
    if (_level.isNaN) {
      _level = start;
    } else {
      _level = math.min(ceiling, _level + (_first == null ? 5 : 2.5));
    }
    return _level;
  }

  /// The listener heard the last tone.
  void heard() {
    if (_first == null) {
      _first = _level;
      _level -= 12.5;
    } else {
      _second = _level;
    }
  }
}

// --- Automatic layer ----------------------------------------------------

/// Picks the layer that suits the music from its live band levels
/// (averaged over a few seconds).
///
/// [dynamics] is how much the loudness moves (dB, standard deviation over
/// a few seconds): orchestras and jazz breathe, electronic music is flat.
/// [punch] is how much the bass jumps from frame to frame (dB): a strong
/// beat. [hint] is a style guessed from the song's title, artist or album,
/// which wins when the sound itself is not clear-cut.
SoundLayer classifySpectrum(
  List<double> levels, {
  double? dynamics,
  double? punch,
  SoundLayer? hint,
}) {
  if (levels.length < _bands) return hint ?? SoundLayer.pop;
  final mids = _mean(levels.sublist(4, 7));
  final bass = _mean(levels.sublist(0, 3)) - mids;
  final highs = _mean(levels.sublist(7, 10)) - mids;
  final voice = _mean(levels.sublist(5, 7)) - _mean(levels.sublist(3, 5));
  final sub = levels[0] - levels[2];

  // Each style scores how well the sound fits it; the best one wins.
  final scores = <SoundLayer, double>{
    SoundLayer.electro:
        _near(bass, 11, 6) + _near(highs, -3, 5) + _near(sub, 2, 4),
    SoundLayer.hipHop:
        _near(bass, 12, 6) + _near(highs, -9, 5) + _near(voice, 2, 4),
    SoundLayer.rock:
        _near(bass, 3, 5) + _near(highs, -2, 4) + _near(voice, 0, 4),
    SoundLayer.pop:
        _near(bass, 5, 6) + _near(highs, -5, 5) + _near(voice, 2, 4),
    SoundLayer.vocal:
        _near(bass, 0, 4) + _near(highs, -7, 5) + _near(voice, 5, 3),
    SoundLayer.classical:
        _near(bass, -3, 5) + _near(highs, -10, 5) + _near(voice, -1, 4),
    SoundLayer.jazz:
        _near(bass, 1, 5) + _near(highs, -7, 4) + _near(voice, 0, 4),
  };
  if (dynamics != null) {
    // Lively dynamics for acoustic styles, flat ones for produced music.
    final lively = ((dynamics - 3) / 4).clamp(-1.0, 1.0);
    scores[SoundLayer.classical] = scores[SoundLayer.classical]! + lively;
    scores[SoundLayer.jazz] = scores[SoundLayer.jazz]! + lively * 0.6;
    scores[SoundLayer.electro] = scores[SoundLayer.electro]! - lively * 0.8;
  }
  if (punch != null) {
    final beat = ((punch - 2) / 3).clamp(-1.0, 1.0);
    scores[SoundLayer.hipHop] = scores[SoundLayer.hipHop]! + beat * 0.8;
    scores[SoundLayer.electro] = scores[SoundLayer.electro]! + beat * 0.6;
    scores[SoundLayer.classical] = scores[SoundLayer.classical]! - beat;
  }
  if (hint != null && scores.containsKey(hint)) {
    scores[hint] = scores[hint]! + 1.2;
  }
  return scores.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// 1 when [value] is at [centre], falling to 0 at [width] away.
double _near(double value, double centre, double width) =>
    math.max(0, 1 - ((value - centre) / width).abs());

/// A style guessed from words in the title, artist or album, if any.
SoundLayer? layerHintFromText(String text) {
  final t = text.toLowerCase();
  // Whole words only: "rap" must not match "trapeze".
  // A word ending in "~" is a stem ("symphon~": symphony, symphonic...).
  bool any(List<String> words) => words.any((w) {
    final stem = w.endsWith('~');
    final word = RegExp.escape(stem ? w.substring(0, w.length - 1) : w);
    return RegExp('(^|[^a-z])$word${stem ? '' : r'($|[^a-z])'}').hasMatch(t);
  });
  if (any([
    'symphon~',
    'concerto',
    'sonata',
    'orchestr~',
    'quartet',
    'opus',
    'mozart',
    'beethoven',
    'bach',
    'chopin',
    'vivaldi',
    'debussy',
    'requiem',
    'piano solo',
    'classical',
    'classique',
  ])) {
    return SoundLayer.classical;
  }
  if (any(['jazz', 'swing', 'bossa', 'blues', 'lofi', 'lo-fi'])) {
    return SoundLayer.jazz;
  }
  if (any([
    'remix',
    'edm',
    'techno',
    'house',
    'trance',
    'dubstep',
    'drum and bass',
    'dnb',
    'synthwave',
    'electro~',
    'club mix',
    'extended mix',
  ])) {
    return SoundLayer.electro;
  }
  if (any(['rap', 'hip hop', 'hip-hop', 'trap', 'drill'])) {
    return SoundLayer.hipHop;
  }
  if (any(['rock', 'metal', 'punk', 'grunge', 'live at'])) {
    return SoundLayer.rock;
  }
  if (any(['acoustic', 'acapella', 'a cappella', 'unplugged', 'ballad'])) {
    return SoundLayer.vocal;
  }
  return null;
}

// --- Helpers ------------------------------------------------------------

List<double> _smooth(List<double> gains) => [
  for (var i = 0; i < gains.length; i++)
    (0.15 * gains[math.max(0, i - 1)] +
        0.7 * gains[i] +
        0.15 * gains[math.min(gains.length - 1, i + 1)]),
];

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _log10(double x) => math.log(x) / math.ln10;

int _nextPow2(int n) {
  var p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

/// In-place radix-2 FFT on separate real and imaginary arrays.
class _Complex {
  _Complex(this.size) : re = Float64List(size), im = Float64List(size);

  final int size;
  final Float64List re;
  final Float64List im;

  void setReal(List<double> values) {
    for (var i = 0; i < values.length && i < size; i++) {
      re[i] = values[i];
    }
  }

  void multiply(_Complex other) {
    for (var i = 0; i < size; i++) {
      final r = re[i] * other.re[i] - im[i] * other.im[i];
      final m = re[i] * other.im[i] + im[i] * other.re[i];
      re[i] = r;
      im[i] = m;
    }
  }

  void fft({bool inverse = false}) {
    final n = size;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = 2 * math.pi / len * (inverse ? 1 : -1);
      final wr = math.cos(angle);
      final wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0;
        var ci = 0.0;
        for (var j = 0; j < len ~/ 2; j++) {
          final ar = re[i + j];
          final ai = im[i + j];
          final br = re[i + j + len ~/ 2] * cr - im[i + j + len ~/ 2] * ci;
          final bi = re[i + j + len ~/ 2] * ci + im[i + j + len ~/ 2] * cr;
          re[i + j] = ar + br;
          im[i + j] = ai + bi;
          re[i + j + len ~/ 2] = ar - br;
          im[i + j + len ~/ 2] = ai - bi;
          final nr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = nr;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }
}
