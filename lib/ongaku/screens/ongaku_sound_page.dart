/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/ongaku/sound/sound_math.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/ongaku/widgets/correction_compare.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/ongaku/widgets/ongaku_settings_ui.dart';
import 'package:musify/ongaku/widgets/sound_curve.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:ongaku_sound/ongaku_sound.dart';
import 'package:permission_handler/permission_handler.dart';

/// Name of an output for the user.
String outputLabel(OngakuStrings strings, OutputRoute route) =>
    switch (route.type) {
      OutputType.speaker => strings.outputSpeaker,
      OutputType.car => strings.outputCar,
      OutputType.wired => route.name.isEmpty ? strings.outputWired : route.name,
      OutputType.bluetooth =>
        route.name.isEmpty ? strings.outputBluetooth : route.name,
    };

IconData outputIcon(OutputType type) => switch (type) {
  OutputType.speaker => Icons.smartphone_rounded,
  OutputType.car => Icons.directions_car_rounded,
  OutputType.wired => Icons.headphones_rounded,
  OutputType.bluetooth => Icons.headphones_rounded,
};

/// Settings > Son calibré: the profile of the output in use, the sound
/// layer, stereo widening, smooth transitions and the saved profiles.
class OngakuSoundPage extends StatelessWidget {
  const OngakuSoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([
          OngakuSoundEngine.supported,
          OngakuSoundEngine.route,
          OngakuSoundEngine.autoLayer,
          soundEnabled,
          soundLayer,
          soundWidening,
          soundProfiles,
          crossfadeMode,
          crossfadeSeconds,
        ]),
        builder: (context, _) {
          final route = OngakuSoundEngine.route.value;
          return CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: OngakuLargeTitle(
                  title: strings.soundTitle,
                  showBack: true,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
                sliver: SliverList.list(
                  children: [
                    if (!OngakuSoundEngine.supported.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(strings.soundUnsupported),
                      ),
                    _OutputCard(route: route),
                    const SizedBox(height: 22),
                    OngakuSettingsGroup(
                      title: '',
                      tint: const Color(0xFFFF2D55),
                      children: [
                        OngakuSettingsRow(
                          title: strings.soundTitle,
                          icon: Icons.graphic_eq_rounded,
                          trailing: Switch(
                            value: soundEnabled.value,
                            onChanged: (v) => soundEnabled.value = v,
                          ),
                        ),
                        if (route.isHeadphones)
                          OngakuSettingsRow(
                            title: strings.widening,
                            icon: Icons.surround_sound_rounded,
                            description: strings.wideningDesc,
                            trailing: SizedBox(
                              width: 130,
                              child: Slider(
                                value: soundWidening.value / 1000,
                                onChanged: (v) =>
                                    soundWidening.value = (v * 1000).round(),
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Not const: they read the settings above, so they
                    // rebuild with them (the layer chosen showed only after
                    // leaving the page).
                    _Layers(key: ValueKey(soundLayer.value)),
                    _Transitions(
                      key: ValueKey(
                        '${crossfadeMode.value}${crossfadeSeconds.value}',
                      ),
                    ),
                    _SavedProfiles(key: ValueKey(soundProfiles.value)),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }
}

/// The output in use, its profile and the test that calibrates it.
class _OutputCard extends StatelessWidget {
  const _OutputCard({required this.route});

  final OutputRoute route;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final profile = soundProfiles.value[route.id];
    final date = profile == null
        ? ''
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
              .format(profile.date);
    final status = profile == null
        ? strings.profileNone
        : profile.method == ProfileMethod.hearing
        ? strings.profileHearing(date)
        : strings.profileMic(date);
    final testPath = route.isHeadphones
        ? '/settings/sound/hearing'
        : '/settings/sound/acoustic';

    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: ShapeDecoration(
                      color: colorScheme.primary,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Icon(
                      outputIcon(route.type),
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.currentOutput,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                        Text(
                          outputLabel(strings, route),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (profile != null) ...[
                const SizedBox(height: 16),
                SoundCurve(
                  series: [
                    CurveSeries(profile.gains, colorScheme.primary, fill: true),
                  ],
                  height: 110,
                ),
                const SizedBox(height: 14),
                CorrectionCompare(gains: profile.gains),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: OngakuSoundEngine.supported.value
                      ? () {
                          stopCorrectionCompare();
                          context.push(testPath);
                        }
                      : null,
                  icon: Icon(
                    route.isHeadphones
                        ? Icons.hearing_rounded
                        : Icons.mic_rounded,
                  ),
                  label: Text(
                    profile != null
                        ? strings.redoTest
                        : route.isHeadphones
                        ? strings.startHearing
                        : strings.startAcoustic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sound layers as chips; Auto shows what it hears.
class _Layers extends StatelessWidget {
  const _Layers({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final layer = soundLayer.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupTitle(strings.soundLayer),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in SoundLayer.values)
                _LayerPill(
                  label: strings.layerName(l),
                  icon: l == SoundLayer.auto
                      ? Icons.auto_awesome_rounded
                      : null,
                  selected: l == layer,
                  onTap: () => soundLayer.value = l,
                ),
            ],
          ),
          if (layer == SoundLayer.auto) ...[
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: Permission.microphone.isGranted,
              builder: (context, snapshot) {
                if (snapshot.data == false) {
                  return _Notice(
                    text: strings.autoNeedsPermission,
                    action: strings.allow,
                    onAction: OngakuSoundEngine.requestMicrophone,
                  );
                }
                final heard = OngakuSoundEngine.autoLayer.value;
                if (heard == null) return const SizedBox.shrink();
                return Text(
                  strings.autoHeard(heard),
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ],
          if (layer != SoundLayer.none && layer != SoundLayer.auto) ...[
            const SizedBox(height: 14),
            SoundCurve(
              series: [
                CurveSeries(
                  layerGains[layer]!,
                  colorScheme.primary,
                  fill: true,
                ),
              ],
              height: 80,
              range: 8,
            ),
          ],
        ],
      ),
    );
  }
}

/// Mode doux: off, automatic, or a fixed length.
class _Transitions extends StatelessWidget {
  const _Transitions({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_GroupTitle(strings.transitions), const CrossfadeControls()],
      ),
    );
  }
}

/// The crossfade choice, shared by this page and the player's sheet.
class CrossfadeControls extends StatelessWidget {
  const CrossfadeControls({super.key, this.dark = false});

  /// On the player's dark sheet.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final muted = dark
        ? Colors.white.withValues(alpha: 0.6)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return ListenableBuilder(
      listenable: Listenable.merge([crossfadeMode, crossfadeSeconds]),
      builder: (context, _) {
        final mode = crossfadeMode.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<CrossfadeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: CrossfadeMode.off,
                    label: Text(strings.crossfadeOff),
                  ),
                  ButtonSegment(
                    value: CrossfadeMode.auto,
                    label: Text(strings.crossfadeAuto),
                  ),
                  ButtonSegment(
                    value: CrossfadeMode.manual,
                    label: Text(strings.crossfadeManual),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => crossfadeMode.value = s.first,
              ),
            ),
            const SizedBox(height: 10),
            if (mode == CrossfadeMode.manual)
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: crossfadeSeconds.value.clamp(1, 12),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: strings.seconds(crossfadeSeconds.value.round()),
                      onChanged: (v) => crossfadeSeconds.value = v,
                    ),
                  ),
                  Text(
                    strings.seconds(crossfadeSeconds.value.round()),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : null,
                    ),
                  ),
                ],
              )
            else
              Text(
                mode == CrossfadeMode.auto
                    ? strings.crossfadeAutoHelp
                    : strings.crossfadeDesc,
                style: TextStyle(fontSize: 13, color: muted),
              ),
          ],
        );
      },
    );
  }
}

/// Profiles of the other outputs, to delete one.
class _SavedProfiles extends StatelessWidget {
  const _SavedProfiles({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final profiles = soundProfiles.value.entries.toList();
    if (profiles.isEmpty) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    return OngakuSettingsGroup(
      title: strings.savedProfiles,
      tint: const Color(0xFF5856D6),
      children: [
        for (final entry in profiles)
          OngakuSettingsRow(
            title: entry.value.label,
            icon: entry.value.method == ProfileMethod.hearing
                ? Icons.hearing_rounded
                : Icons.mic_rounded,
            description: DateFormat.yMMMd(locale).format(entry.value.date),
            trailing: IconButton(
              tooltip: strings.deleteProfile,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => deleteSoundProfile(entry.key),
            ),
          ),
      ],
    );
  }
}

/// One sound layer: a pill that fills with the accent colour when chosen.
class _LayerPill extends StatelessWidget {
  const _LayerPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.onPrimary : colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.action, this.onAction});

  final String text;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 13.5, height: 1.3)),
          const SizedBox(height: 8),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
