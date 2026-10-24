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
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler, logger;
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/screens/ongaku_sound_page.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/ongaku/sound/sound_math.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/ongaku/widgets/correction_compare.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/ongaku/widgets/sound_curve.dart';
import 'package:ongaku_sound/ongaku_sound.dart';

enum _Step { intro, checking, measuring, analysing, result, failed }

/// Above this ambient level (dBFS) the room is too noisy to measure.
const _noiseLimit = -45.0;

MeasureResult _analyse(SweepRecording r) => analyseSweep(
  // The lead before the sweep is kept: it tells the noise level.
  recording: r.samples,
  sampleRate: r.sampleRate,
  sweepSamples: r.sweepSamples,
  f1: r.f1,
  f2: r.f2,
);

/// Microphone measurement of the phone speaker or of the car speakers
/// (Android Auto): a sweep is played and recorded, and its response gives
/// the correction of this output.
class OngakuAcousticTestPage extends StatefulWidget {
  const OngakuAcousticTestPage({super.key});

  @override
  State<OngakuAcousticTestPage> createState() => _OngakuAcousticTestPageState();
}

class _OngakuAcousticTestPageState extends State<OngakuAcousticTestPage> {
  _Step _step = _Step.intro;
  String? _error;
  List<double> _response = const [];
  List<double> _correction = const [];
  late final OutputRoute _route = OngakuSoundEngine.route.value;

  Future<void> _run(OngakuStrings strings) async {
    // The before/after sample must not play over the test.
    stopCorrectionCompare();
    if (!await OngakuSoundEngine.requestMicrophone()) {
      setState(() {
        _step = _Step.failed;
        _error = strings.micDenied;
      });
      return;
    }
    if (audioHandler.audioPlayer.playing) await audioHandler.pause();
    setState(() => _step = _Step.checking);
    try {
      final noise = await OngakuSound.noiseLevel();
      if (noise > _noiseLimit) {
        setState(() {
          _step = _Step.failed;
          _error = strings.acNoisy;
        });
        return;
      }
      setState(() => _step = _Step.measuring);
      final recording = await OngakuSound.measure();
      setState(() => _step = _Step.analysing);
      final result = await compute(_analyse, recording);
      if (!mounted) return;
      if (result.error != null) {
        setState(() {
          _step = _Step.failed;
          _error = result.error == MeasureError.tooQuiet
              ? strings.acTooQuiet
              : strings.acTooNoisy;
        });
        return;
      }
      setState(() {
        _response = result.response;
        _correction = correctionFromResponse(result.response);
        _step = _Step.result;
      });
    } catch (e, stackTrace) {
      logger.log('Ongaku acoustic test', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = strings.acTooNoisy;
      });
    }
  }

  void _save(OngakuStrings strings) {
    saveSoundProfile(
      _route.id,
      SoundProfile(
        gains: _correction,
        method: ProfileMethod.microphone,
        date: DateTime.now(),
        label: outputLabel(strings, _route),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final busy =
        _step == _Step.checking ||
        _step == _Step.measuring ||
        _step == _Step.analysing;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          OngakuLargeTitle(title: strings.acTitle, showBack: true),
          Padding(
            padding: EdgeInsets.fromLTRB(margin, 20, margin, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TestHero(
                  icon: outputIcon(_route.type),
                  label: outputLabel(strings, _route),
                  busy: busy,
                ),
                const SizedBox(height: 24),
                if (_step == _Step.intro) ...[
                  Text(
                    _route.type == OutputType.car
                        ? strings.acIntroCar
                        : strings.acIntroSpeaker,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.acVolume,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                if (busy)
                  Center(
                    child: Text(
                      switch (_step) {
                        _Step.checking => strings.acChecking,
                        _Step.measuring => strings.acMeasuring,
                        _ => strings.acAnalysing,
                      },
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_step == _Step.failed)
                  Text(
                    _error ?? '',
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                if (_step == _Step.result) ...[
                  Text(
                    strings.acDone(outputLabel(strings, _route)),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SoundCurve(
                    series: [
                      CurveSeries(
                        _response,
                        colorScheme.onSurface.withValues(alpha: 0.35),
                      ),
                      CurveSeries(_correction, colorScheme.primary, fill: true),
                    ],
                    range: 18,
                    height: 160,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Legend(
                        color: colorScheme.onSurface.withValues(alpha: 0.35),
                        label: strings.acLegendMeasured,
                      ),
                      const SizedBox(width: 18),
                      _Legend(
                        color: colorScheme.primary,
                        label: strings.acLegendCorrection,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CorrectionCompare(gains: _correction),
                ],
                const SizedBox(height: 28),
                if (!busy)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _step == _Step.result
                          ? () => _save(strings)
                          : () => _run(strings),
                      child: Text(switch (_step) {
                        _Step.result => strings.save,
                        _Step.failed => strings.retry,
                        _ => strings.start,
                      }),
                    ),
                  ),
                if (_step == _Step.result)
                  Center(
                    child: TextButton(
                      onPressed: () => _run(strings),
                      child: Text(strings.retry),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big round output icon of the tests, pulsing while they run.
class TestHero extends StatelessWidget {
  const TestHero({
    super.key,
    required this.icon,
    required this.label,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (busy)
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: colorScheme.primary,
                    ),
                  ),
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, size: 52, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
