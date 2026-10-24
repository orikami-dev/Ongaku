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

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler, logger;
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:ongaku_sound/ongaku_sound.dart';

/// Demo loop made by `scripts/make_demo_sample.py`.
const _demoAsset = 'assets/sounds/ongaku_demo.ogg';

enum _Source { demo, song }

/// Plays a sample with and without [gains], to hear what a correction does.
class CorrectionCompare extends StatefulWidget {
  const CorrectionCompare({super.key, required this.gains});

  final List<double> gains;

  @override
  State<CorrectionCompare> createState() => _CorrectionCompareState();
}

class _CorrectionCompareState extends State<CorrectionCompare> {
  bool _after = true;
  bool _playing = false;
  _Source _source = _Source.demo;
  AudioPlayer? _demo;
  int? _demoSession;

  bool get _hasSong => audioHandler.mediaItem.valueOrNull != null;

  @override
  void didUpdateWidget(CorrectionCompare old) {
    super.didUpdateWidget(old);
    if (_playing && !listEquals(old.gains, widget.gains)) _applyPreview();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stop());
    super.dispose();
  }

  void _applyPreview() {
    OngakuSoundEngine.preview.value = _after
        ? List<double>.from(widget.gains)
        : List<double>.filled(widget.gains.length, 0);
  }

  Future<void> _play() async {
    _applyPreview();
    setState(() => _playing = true);
    try {
      if (_source == _Source.song) {
        await audioHandler.play();
        return;
      }
      if (audioHandler.audioPlayer.playing) await audioHandler.pause();
      final demo = _demo ?? AudioPlayer(handleInterruptions: false);
      if (_demo == null) {
        _demo = demo;
        demo.androidAudioSessionIdStream
            .where((id) => id != null)
            .first
            .then((id) {
              _demoSession = id;
              return OngakuSound.attachExtra(id!);
            })
            .ignore();
        await demo.setAsset(_demoAsset);
        await demo.setLoopMode(LoopMode.one);
      }
      unawaited(demo.play());
    } catch (e) {
      logger.log('Ongaku compare: play failed', error: e);
      await _stop();
    }
  }

  Future<void> _stop() async {
    OngakuSoundEngine.preview.value = null;
    final demo = _demo;
    _demo = null;
    final session = _demoSession;
    _demoSession = null;
    if (!_disposed) setState(() => _playing = false);
    try {
      if (_source == _Source.song) await audioHandler.pause();
      if (demo != null) {
        await demo.stop();
        await demo.dispose();
      }
      if (session != null) await OngakuSound.detachExtra(session);
    } catch (_) {}
  }

  Future<void> _setSource(_Source source) async {
    if (source == _source) return;
    final wasPlaying = _playing;
    await _stop();
    setState(() => _source = source);
    if (wasPlaying) await _play();
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.compareTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (_hasSong) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final (source, label) in [
                  (_Source.demo, strings.compareDemo),
                  (_Source.song, strings.compareSong),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _source == source,
                    showCheckmark: false,
                    onSelected: (_) => _setSource(source),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.filled(
                iconSize: 30,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                onPressed: _playing ? _stop : _play,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(strings.compareBefore),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(strings.compareAfter),
                    ),
                  ],
                  selected: {_after},
                  onSelectionChanged: (s) {
                    setState(() => _after = s.first);
                    if (_playing) _applyPreview();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
