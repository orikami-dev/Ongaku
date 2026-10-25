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
/// Musify's player and queue stay in charge. Near the end, a second player
/// loads the ending song; a few seconds before the fade it carries on the
/// ending song while Musify moves, muted, to the next one. The next song
/// is thus loaded before the fade: at the fade point it goes back to its
/// start and the two volumes cross, with no gap if the network is slow.

/// Seconds the next song gets to load before the fade (finding its stream
/// can take a few seconds on a slow network).
const _lead = Duration(seconds: 8);

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

  /// Usual loudness of the current song, and since when it has been well
  /// below it (Auto: the song is fading out on its own).
  static double? _typicalLoudness;
  static DateTime? _quietSince;
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
    // Auto: long enough for the two songs to really mix.
    if (seconds < 90) return 4;
    return 8;
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
        _typicalLoudness = null;
        _quietSince = null;
      }
      final typical = _typicalLoudness;
      if (level != null) {
        if (remaining > const Duration(seconds: 25)) {
          // The usual level, not the loudest moment: a single peak made
          // every outro look quiet and the fade start too early.
          _typicalLoudness = typical == null
              ? level
              : typical * 0.98 + level * 0.02;
        } else if (remaining > Duration(milliseconds: (fade * 1000).round()) &&
            typical != null &&
            level < typical - 12 &&
            _preparedFor == current.id) {
          // Quiet for two seconds in a row, not a short break.
          final since = _quietSince ??= DateTime.now();
          if (DateTime.now().difference(since) >= const Duration(seconds: 2)) {
            fade = math.min(10, remaining.inMilliseconds / 1000);
            unawaited(_begin(fade, position));
            return;
          }
        } else {
          _quietSince = null;
        }
      }
    }

    // Load the ending song in the second player a bit before.
    final prepareFrom = crossfadeMode.value == CrossfadeMode.auto
        ? const Duration(seconds: 32)
        : Duration(milliseconds: (fade * 1000).round()) + _lead + _lead;
    if (remaining <= prepareFrom && _preparedFor != current.id) {
      _preparedFor = current.id;
      unawaited(_prepare(fadeAt - _lead));
    }
    // The next song starts loading a few seconds before the fade.
    if (position >= fadeAt - _lead &&
        _ghost != null &&
        _preparedFor == current.id) {
      unawaited(_begin(fade, position, fadeAt: fadeAt));
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

  /// Hands the ending song to the second player and moves Musify to the
  /// next song; the volumes cross from [fadeAt] (now when null), once the
  /// next song is ready.
  static Future<void> _begin(
    double fadeSeconds,
    Duration position, {
    Duration? fadeAt,
  }) async {
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

      // The ending song fades out on its own clock, from the fade point to
      // its last second, so it never stops short even if the next song is
      // late. The next song fades in from the moment it really plays,
      // restarted from its top: the two overlap for the whole fade.
      final total = (fadeSeconds * 1000).round();
      final end = ghost.duration ?? (position + Duration(milliseconds: total));
      final outFrom = fadeAt ?? position;
      final outLength = math.max(1, (end - outFrom).inMilliseconds);
      final started = DateTime.now();
      DateTime? nextPlaying;
      progress.value = 0;
      while (_fading) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final ghostDone = ghost.processingState == ProcessingState.completed;
        final atFade = ghost.position >= outFrom;
        if (nextPlaying == null &&
            (atFade || ghostDone) &&
            _main.playing &&
            _main.processingState == ProcessingState.ready) {
          if (_main.position > const Duration(milliseconds: 300)) {
            await _main.seek(Duration.zero);
          }
          nextPlaying = DateTime.now();
          _switching = false;
        }
        final out = ghostDone
            ? 1.0
            : ((ghost.position - outFrom).inMilliseconds / outLength).clamp(
                0.0,
                1.0,
              );
        final elapsed = nextPlaying == null
            ? 0
            : DateTime.now().difference(nextPlaying).inMilliseconds;
        final into = (elapsed / total).clamp(0.0, 1.0);
        progress.value = into;
        await ghost.setVolume(base * ongakuFadeOut(out));
        await _main.setVolume(base * ongakuFadeIn(into));
        final waited = DateTime.now().difference(started).inMilliseconds;
        if ((into >= 1 && (out >= 1 || ghostDone)) ||
            waited > total + _lead.inMilliseconds + 20000) {
          break;
        }
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

/// Volume of the ending song along its fade (0 to 1): equal power, so the
/// mix keeps the same loudness, with a soft start.
double ongakuFadeOut(double t) {
  final u = t.clamp(0.0, 1.0);
  return math.cos(u * u * (3 - 2 * u) * math.pi / 2);
}

/// Volume of the next song along its fade (0 to 1): rises early, so both
/// songs are clearly heard together in the middle.
double ongakuFadeIn(double t) {
  final u = t.clamp(0.0, 1.0);
  return math.sin(u * math.pi / 2);
}
