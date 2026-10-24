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

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:ongaku_sound/ongaku_sound.dart';

/// "Mode doux": songs that end on their own fade into the next one.
///
/// Musify's player and queue stay in charge. A few seconds before the end,
/// a second player loads the ending song at the fade point; when the fade
/// starts it carries on the ending song while Musify moves to the next one
/// (already fetched in advance by Musify), and the two volumes cross.
class OngakuCrossfade {
  OngakuCrossfade._();

  static MusifyAudioHandler? _handler;
  static AudioPlayer? _ghost;
  static Duration? _ghostStart;
  static String? _preparedFor;
  static bool _fading = false;

  /// Musify is switching to the next song: its player may stop briefly.
  static bool _switching = false;
  static double _base = 1;
  static double _peakLoudness = -200;
  static String? _loudnessFor;

  /// The fade in progress, 0 to 1, for the player's indicator.
  static final progress = ValueNotifier<double?>(null);

  static void start(MusifyAudioHandler handler) {
    if (_handler != null) return;
    _handler = handler;
    handler.audioPlayer.positionStream.listen(_onPosition);
    handler.audioPlayer.playingStream.listen((playing) {
      if (!playing && _fading && !_switching) _abort();
    });
  }

  static AudioPlayer get _main => _handler!.audioPlayer;

  /// The song after the current one in Musify's queue, if any.
  static MediaItem? _nextItem() {
    final handler = _handler!;
    final current = handler.mediaItem.valueOrNull;
    final queue = handler.queue.valueOrNull ?? const <MediaItem>[];
    if (current == null || queue.isEmpty) return null;
    final index = queue.indexWhere((item) => item.id == current.id);
    if (index < 0) return null;
    if (index + 1 < queue.length) return queue[index + 1];
    return repeatNotifier.value == AudioServiceRepeatMode.all
        ? queue.first
        : null;
  }

  /// Seconds of fade between [current] and [next] (0: no fade).
  static double _fadeLength(
    MediaItem current,
    MediaItem next,
    Duration length,
  ) {
    final seconds = length.inMilliseconds / 1000;
    if (crossfadeMode.value == CrossfadeMode.manual) {
      return math.min(crossfadeSeconds.value, seconds / 4);
    }
    // Auto: an album played in order keeps its own transitions.
    final album = current.album ?? '';
    if (album.isNotEmpty && album == next.album) return 0;
    if (seconds < 90) return 3;
    return 6;
  }

  static bool _eligible() {
    final handler = _handler!;
    if (crossfadeMode.value == CrossfadeMode.off) return false;
    if (handler.sleepTimerEndOfSong) return false;
    if (repeatNotifier.value == AudioServiceRepeatMode.one) return false;
    final item = handler.mediaItem.valueOrNull;
    if (item == null || item.extras?['isLive'] == true) return false;
    // Songs with skipped segments (SponsorBlock) are left as they are.
    return _main.audioSource is UriAudioSource && _main.sequence.length == 1;
  }

  static void _onPosition(Duration position) {
    final handler = _handler;
    if (handler == null || _fading || !_main.playing) return;
    final length = _main.duration;
    if (length == null || length < const Duration(seconds: 30)) return;
    if (!_eligible()) return;
    final current = handler.mediaItem.valueOrNull!;
    final next = _nextItem();
    if (next == null) return;
    var fade = _fadeLength(current, next, length);
    if (fade <= 0) return;

    final remaining = length - position;
    final fadeAt = length - Duration(milliseconds: (fade * 1000).round());

    // Auto: a song that is already fading out starts the transition there.
    if (crossfadeMode.value == CrossfadeMode.auto) {
      final level = OngakuSoundEngine.loudness.value;
      if (_loudnessFor != current.id) {
        _loudnessFor = current.id;
        _peakLoudness = -200;
      }
      if (level != null) {
        if (remaining > const Duration(seconds: 25)) {
          _peakLoudness = math.max(_peakLoudness, level);
        } else if (remaining > Duration(milliseconds: (fade * 1000).round()) &&
            _peakLoudness > -150 &&
            level < _peakLoudness - 14 &&
            _preparedFor == current.id) {
          fade = math.min(10, remaining.inMilliseconds / 1000);
          unawaited(_begin(fade, position));
          return;
        }
      }
    }

    // Load the ending song in the second player a bit before.
    final prepareFrom = crossfadeMode.value == CrossfadeMode.auto
        ? const Duration(seconds: 26)
        : Duration(milliseconds: (fade * 1000).round() + 5000);
    if (remaining <= prepareFrom && _preparedFor != current.id) {
      _preparedFor = current.id;
      unawaited(_prepare(fadeAt));
    }
    if (position >= fadeAt && _ghost != null && _preparedFor == current.id) {
      unawaited(_begin(fade, position));
    }
  }

  static Future<void> _prepare(Duration at) async {
    await _disposeGhost();
    final source = _main.audioSource;
    if (source is! UriAudioSource) return;
    try {
      final ghost = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );
      _ghost = ghost;
      _ghostStart = at;
      await ghost.setAudioSource(
        AudioSource.uri(source.uri, headers: source.headers),
        initialPosition: at,
      );
      // The calibrated sound applies to the ending song too.
      ghost.androidAudioSessionIdStream
          .where((id) => id != null)
          .first
          .then((id) => OngakuSound.attachExtra(id!))
          .ignore();
    } catch (e) {
      logger.log('Ongaku crossfade: prepare failed', error: e);
      await _disposeGhost();
    }
  }

  static Future<void> _begin(double fadeSeconds, Duration position) async {
    final ghost = _ghost;
    if (ghost == null || _fading) return;
    _fading = true;
    _switching = true;
    final base = _main.volume;
    _base = base;
    try {
      // Keep the ending song exactly where Musify's player is.
      final drift = position - (_ghostStart ?? position);
      if (drift.abs() > const Duration(milliseconds: 250)) {
        await ghost.seek(position);
      }
      await ghost.setVolume(base);
      unawaited(ghost.play());
      await _main.setVolume(0);
      await _handler!.skipToNext();

      // Equal-power crossfade, starting when the next song really plays.
      final total = (fadeSeconds * 1000).round();
      final started = DateTime.now();
      DateTime? nextPlaying;
      progress.value = 0;
      while (_fading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (nextPlaying == null &&
            _main.playing &&
            _main.processingState == ProcessingState.ready) {
          nextPlaying = DateTime.now();
          _switching = false;
        }
        // If the next song is slow to start, the ending one keeps playing.
        final elapsed = nextPlaying == null
            ? 0
            : DateTime.now().difference(nextPlaying).inMilliseconds;
        final t = (elapsed / total).clamp(0.0, 1.0);
        progress.value = t;
        await ghost.setVolume(base * math.cos(t * math.pi / 2));
        await _main.setVolume(base * math.sin(t * math.pi / 2));
        final waited = DateTime.now().difference(started).inMilliseconds;
        if (t >= 1 || waited > total + 15000) break;
      }
      await _main.setVolume(base);
    } catch (e) {
      logger.log('Ongaku crossfade failed', error: e);
      await _main.setVolume(base);
    } finally {
      _fading = false;
      _switching = false;
      progress.value = null;
      await _disposeGhost();
    }
  }

  /// Paused or skipped during a fade: stop the ending song, full volume.
  static void _abort() {
    _fading = false;
    unawaited(_main.setVolume(_base));
    unawaited(_disposeGhost());
  }

  static Future<void> _disposeGhost() async {
    final ghost = _ghost;
    _ghost = null;
    if (ghost == null) return;
    final session = ghost.androidAudioSessionId;
    try {
      await ghost.stop();
      await ghost.dispose();
      if (session != null) await OngakuSound.detachExtra(session);
    } catch (_) {}
  }
}
