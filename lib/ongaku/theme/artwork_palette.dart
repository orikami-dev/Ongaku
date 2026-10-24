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
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';

/// Colours taken from the artwork of the song that is playing, used for the
/// player and lyrics backgrounds like Apple Music does.
@immutable
class ArtworkPalette {
  const ArtworkPalette(this.colors);

  /// Four colours, darkest first, all dark enough for white text.
  final List<Color> colors;

  static const fallback = ArtworkPalette([
    Color(0xFF2A1218),
    Color(0xFF5A1A2C),
    Color(0xFF3A1F4F),
    Color(0xFF7A2236),
  ]);

  Color get base => colors.first;

  static ArtworkPalette lerp(ArtworkPalette a, ArtworkPalette b, double t) =>
      ArtworkPalette([
        for (var i = 0; i < 4; i++) Color.lerp(a.colors[i], b.colors[i], t)!,
      ]);

  @override
  bool operator ==(Object other) =>
      other is ArtworkPalette && listEquals(other.colors, colors);

  @override
  int get hashCode => Object.hashAll(colors);
}

/// Palette of the current song, updated whenever the song changes.
final ValueNotifier<ArtworkPalette> currentArtworkPalette =
    _CurrentPaletteNotifier();

class _CurrentPaletteNotifier extends ValueNotifier<ArtworkPalette> {
  _CurrentPaletteNotifier() : super(ArtworkPalette.fallback) {
    // Lives as long as the app.
    // ignore: cancel_subscriptions
    _subscription = audioHandler.mediaItem.listen(_onMediaItem);
  }

  // Lives as long as the app.
  // ignore: unused_field, cancel_subscriptions
  late final StreamSubscription<MediaItem?> _subscription;
  String? _currentKey;

  Future<void> _onMediaItem(MediaItem? item) async {
    final uri = item?.artUri;
    final key = uri?.toString() ?? '';
    if (key == _currentKey) return;
    _currentKey = key;
    // No artwork, or one that cannot be read: back to the default colours
    // instead of keeping the previous song's.
    final palette = key.isEmpty ? null : await paletteForArtwork(uri!);
    if (_currentKey == key) value = palette ?? ArtworkPalette.fallback;
  }
}

final _cache = <String, ArtworkPalette>{};

/// Extracts a palette from [artUri] (a file or network image).
Future<ArtworkPalette?> paletteForArtwork(Uri artUri) async {
  final key = artUri.toString();
  final cached = _cache[key];
  if (cached != null) return cached;

  try {
    // ignore: omit_local_variable_types
    final ImageProvider provider = artUri.scheme == 'file'
        ? FileImage(File(artUri.toFilePath()))
        : CachedNetworkImageProvider(key);
    final image = await _resolve(ResizeImage(provider, width: 32, height: 32));
    final data = await image.toByteData();
    image.dispose();
    if (data == null) return null;
    final palette = _extract(data.buffer.asUint8List());
    _cache[key] = palette;
    return palette;
  } catch (_) {
    return null;
  }
}

Future<ui.Image> _resolve(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 8));
}

/// Groups pixels into coarse buckets and keeps the four most present colours,
/// favouring vivid ones, then darkens them so white text stays readable.
ArtworkPalette _extract(List<int> rgba) {
  final buckets = <int, _Bucket>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5);
    (buckets[key] ??= _Bucket()).add(r, g, b);
  }
  if (buckets.isEmpty) return ArtworkPalette.fallback;

  final ranked = buckets.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  final picked = <HSLColor>[];
  for (final bucket in ranked) {
    final hsl = HSLColor.fromColor(bucket.color);
    final distinct = picked.every((p) => _distance(p, hsl) > 0.12);
    if (distinct) picked.add(hsl);
    if (picked.length == 4) break;
  }
  while (picked.length < 4) {
    final seed = picked.isEmpty
        ? HSLColor.fromColor(ArtworkPalette.fallback.colors[1])
        : picked[picked.length % picked.length];
    picked.add(seed.withHue((seed.hue + 24 * picked.length) % 360));
  }

  final colors = [
    for (final hsl in picked)
      hsl
          .withLightness(hsl.lightness.clamp(0.16, 0.42))
          .withSaturation(math.min(hsl.saturation, 0.75))
          .toColor(),
  ]..sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));

  // The darkest one fills the background: keep it really dark.
  final base = HSLColor.fromColor(colors.first);
  colors[0] = base.withLightness(math.min(base.lightness, 0.16)).toColor();
  return ArtworkPalette(colors);
}

double _distance(HSLColor a, HSLColor b) {
  final dh = ((a.hue - b.hue).abs() % 360) / 180;
  final hue = math.min(dh, 2 - dh) * math.min(a.saturation, b.saturation);
  return hue + (a.lightness - b.lightness).abs() * 0.8;
}

class _Bucket {
  int count = 0;
  int r = 0, g = 0, b = 0;

  void add(int red, int green, int blue) {
    count++;
    r += red;
    g += green;
    b += blue;
  }

  Color get color => Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);

  double get score {
    final hsl = HSLColor.fromColor(color);
    // Near-black and near-white areas say little about the artwork.
    final light = hsl.lightness;
    final usable = light < 0.06 || light > 0.94 ? 0.25 : 1.0;
    return count * (0.35 + hsl.saturation) * usable;
  }
}
