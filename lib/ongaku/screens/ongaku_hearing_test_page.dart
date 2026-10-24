/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler, logger;
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/screens/ongaku_acoustic_test_page.dart';
import 'package:musify/ongaku/screens/ongaku_sound_page.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/ongaku/sound/sound_math.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/ongaku/widgets/correction_compare.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/ongaku/widgets/sound_curve.dart';
import 'package:ongaku_sound/ongaku_sound.dart';

enum _Step { intro, testing, result }

/// Hearing test for earbuds and headphones: soft beeps get louder until the
/// listener taps, band by band; the thresholds give the profile of these
/// earbuds for this listener.
class OngakuHearingTestPage extends StatefulWidget {
  const OngakuHearingTestPage({super.key});

  @override
  State<OngakuHearingTestPage> createState() => _OngakuHearingTestPageState();
}

class _OngakuHearingTestPageState extends State<OngakuHearingTestPage> {
  _Step _step = _Step.intro;
  int _band = 0;
  bool _heard = false;
  bool _running = false;
  List<double> _gains = const [];
  late final OutputRoute _route = OngakuSoundEngine.route.value;

  @override
  void dispose() {
    _running = false;
    OngakuSound.stopTone().ignore();
    super.dispose();
  }

  bool get _stillOnHeadphones =>
      OngakuSoundEngine.route.value.id == _route.id;

  Future<void> _run() async {
    if (audioHandler.audioPlayer.playing) await audioHandler.pause();
    setState(() {
      _step = _Step.testing;
      _band = 0;
    });
    _running = true;
    final thresholds = <int, double>{};
    try {
      for (var i = 0; i < hearingBands.length; i++) {
        final band = hearingBands[i];
        if (!mounted || !_running) return;
        setState(() => _band = i);
        final stair = ToneStaircase();
        while (!stair.done) {
          if (!mounted || !_running || !_stillOnHeadphones) {
            if (mounted) setState(() => _step = _Step.intro);
            return;
          }
          _heard = false;
          await OngakuSound.playTone(
            bandCentres[band],
            level: stair.next(),
            ms: 600,
          );
          // The tone plus a moment to answer.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          if (_heard) stair.heard();
        }
        thresholds[band] = stair.threshold;
        // A short pause between two frequencies.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    } catch (e, stackTrace) {
      logger.log('Ongaku hearing test', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _step = _Step.intro);
      return;
    } finally {
      _running = false;
    }
    if (!mounted) return;
    setState(() {
      _gains = profileFromThresholds(thresholds);
      _step = _Step.result;
    });
  }

  void _save(OngakuStrings strings) {
    saveSoundProfile(
      _route.id,
      SoundProfile(
        gains: _gains,
        method: ProfileMethod.hearing,
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
    final onHeadphones = _route.isHeadphones;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          OngakuLargeTitle(title: strings.htTitle, showBack: true),
          Padding(
            padding: EdgeInsets.fromLTRB(margin, 20, margin, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TestHero(
                  icon: outputIcon(_route.type),
                  label: outputLabel(strings, _route),
                ),
                const SizedBox(height: 24),
                if (_step == _Step.intro)
                  Text(
                    onHeadphones ? strings.htIntro : strings.htNeedsHeadphones,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                if (_step == _Step.testing) ...[
                  Center(
                    child: Text(
                      strings.htBand(_band + 1, hearingBands.length),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _band / hearingBands.length,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                        ),
                        onPressed: () => _heard = true,
                        child: Text(
                          strings.htHeard,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_step == _Step.result) ...[
                  Text(
                    strings.htDone(outputLabel(strings, _route)),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SoundCurve(
                    series: [
                      CurveSeries(_gains, colorScheme.primary, fill: true),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CorrectionCompare(gains: _gains),
                ],
                const SizedBox(height: 28),
                if (_step != _Step.testing && onHeadphones)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _step == _Step.result
                          ? () => _save(strings)
                          : _run,
                      child: Text(
                        _step == _Step.result ? strings.save : strings.start,
                      ),
                    ),
                  ),
                if (_step == _Step.result)
                  Center(
                    child: TextButton(
                      onPressed: _run,
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
