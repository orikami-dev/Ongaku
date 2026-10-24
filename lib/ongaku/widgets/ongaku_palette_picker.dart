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
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/theme/ongaku_palettes.dart';
import 'package:musify/ongaku/widgets/ongaku_settings_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/theme/app_themes.dart' show themeMode;

/// Settings > Apparence: the Thème row. A tap unfolds the themes below it as
/// cards, each showing its day and night colours and its app icon, and the
/// arrow turns; a second tap folds them. A card applies its theme at once.
class OngakuPalettePicker extends StatefulWidget {
  const OngakuPalettePicker({super.key, this.borderRadius = BorderRadius.zero});

  final BorderRadius borderRadius;

  @override
  State<OngakuPalettePicker> createState() => _OngakuPalettePickerState();
}

class _OngakuPalettePickerState extends State<OngakuPalettePicker> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<OngakuPalette>(
      valueListenable: ongakuPalette,
      builder: (context, current, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OngakuSettingsRow(
              title: strings.paletteTitle,
              icon: Icons.palette_rounded,
              borderRadius: _open ? BorderRadius.zero : widget.borderRadius,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _open = !_open);
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current.label,
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open
                  ? ColoredBox(
                      color: colorScheme.surfaceContainerLow,
                      child: _cards(context, strings, colorScheme, current),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }

  Widget _cards(
    BuildContext context,
    OngakuStrings strings,
    ColorScheme colorScheme,
    OngakuPalette current,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            child: ListView.separated(
              // Opens on the theme in use.
              controller: ScrollController(
                initialScrollOffset: current.index > 1
                    ? (current.index - 1) * (_cardWidth + 10)
                    : 0,
              ),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              itemCount: OngakuPalette.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final palette = OngakuPalette.values[i];
                return _PaletteCard(
                  palette: palette,
                  selected: palette == current,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setOngakuPalette(palette);
                    Musify.updateAppState(context, newThemeMode: themeMode);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              strings.paletteHint,
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _cardWidth = 116;

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final OngakuPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final own = primaryColorSetting;
    final dayAccent = palette.dayAccent ?? own;
    final nightAccent = palette.nightAccent ?? own;
    return Semantics(
      button: true,
      selected: selected,
      label: palette.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _cardWidth,
          padding: const EdgeInsets.all(3),
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: selected ? colorScheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _Half(neutrals: palette.day, accent: dayAccent),
                      _Half(neutrals: palette.night, accent: nightAccent),
                    ],
                  ),
                ),
                Container(
                  height: 50,
                  width: double.infinity,
                  color: palette.night.grouped,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Row(
                    children: [
                      ClipRSuperellipse(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          palette.iconAsset,
                          width: 28,
                          height: 28,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          palette.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.night.label,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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

/// Day or night half of a card: page colour, a card line and the accent.
class _Half extends StatelessWidget {
  const _Half({required this.neutrals, required this.accent});

  final OngakuNeutrals neutrals;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ColoredBox(
        color: neutrals.background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 9, 7, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const Spacer(),
              for (final w in [1.0, 0.7])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FractionallySizedBox(
                    widthFactor: w,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: neutrals.fill,
                        borderRadius: BorderRadius.circular(3),
                      ),
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
