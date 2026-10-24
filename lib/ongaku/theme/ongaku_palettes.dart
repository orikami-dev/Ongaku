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
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';

/// Page, card and text colours of a palette, for day or night.
class OngakuNeutrals {
  const OngakuNeutrals({
    required this.background,
    required this.grouped,
    required this.elevated,
    required this.fill,
    required this.fillStrong,
    required this.label,
    required this.secondaryLabel,
    required this.separator,
  });

  final Color background;
  final Color grouped;
  final Color elevated;
  final Color fill;
  final Color fillStrong;
  final Color label;
  final Color secondaryLabel;
  final Color separator;
}

/// iOS system grays: Ongaku's own look.
const _iosDay = OngakuNeutrals(
  background: Color(0xFFFFFFFF),
  grouped: Color(0xFFF2F2F7),
  elevated: Color(0xFFFFFFFF),
  fill: Color(0xFFE5E5EA),
  fillStrong: Color(0xFFD1D1D6),
  label: Color(0xFF000000),
  secondaryLabel: Color(0xFF6C6C70),
  separator: Color(0xFFC6C6C8),
);
const _iosNight = OngakuNeutrals(
  background: Color(0xFF000000),
  grouped: Color(0xFF1C1C1E),
  elevated: Color(0xFF1C1C1E),
  fill: Color(0xFF2C2C2E),
  fillStrong: Color(0xFF3A3A3C),
  label: Color(0xFFFFFFFF),
  secondaryLabel: Color(0xFF98989F),
  separator: Color(0xFF38383A),
);

/// Washi paper by day, tinted ink by night (shared with Kamishibai).
const _washiDay = OngakuNeutrals(
  background: Color(0xFFFAF7F2),
  grouped: Color(0xFFEFEAE2),
  elevated: Color(0xFFFFFFFF),
  fill: Color(0xFFE4DED4),
  fillStrong: Color(0xFFDDD6CB),
  label: Color(0xFF1B1A19),
  secondaryLabel: Color(0xFF6E6A64),
  separator: Color(0xFFDDD6CB),
);
const _washiNight = OngakuNeutrals(
  background: Color(0xFF0F0F13),
  grouped: Color(0xFF18181E),
  elevated: Color(0xFF18181E),
  fill: Color(0xFF24242C),
  fillStrong: Color(0xFF34343E),
  label: Color(0xFFF4F1EA),
  secondaryLabel: Color(0xFFA9A6A0),
  separator: Color(0xFF34343E),
);

/// Neutral grays by day, true black (OLED) by night.
const _sumiDay = OngakuNeutrals(
  background: Color(0xFFF4F4F5),
  grouped: Color(0xFFFFFFFF),
  elevated: Color(0xFFFFFFFF),
  fill: Color(0xFFE9E9EC),
  fillStrong: Color(0xFFDCDCE0),
  label: Color(0xFF111113),
  secondaryLabel: Color(0xFF66666C),
  separator: Color(0xFFD4D4D8),
);
const _sumiNight = OngakuNeutrals(
  background: Color(0xFF000000),
  grouped: Color(0xFF0E0E0E),
  elevated: Color(0xFF0E0E0E),
  fill: Color(0xFF1A1A1A),
  fillStrong: Color(0xFF262626),
  label: Color(0xFFF4F1EA),
  secondaryLabel: Color(0xFFA9A6A0),
  separator: Color(0xFF262626),
);

/// Ongaku's themes: its own (iOS grays, accent of your choice) and the
/// ORIKAMI palettes shared with Kamishibai, each with a day and a night
/// version and its own app icon.
enum OngakuPalette {
  ongaku('Ongaku', _iosDay, _iosNight, null, null),
  washi('Washi', _washiDay, _washiNight, Color(0xFFE23B22), Color(0xFFFF5A40)),
  sumi('Sumi', _sumiDay, _sumiNight, Color(0xFF6A4BC4), Color(0xFFA993F5)),
  ai('Ai', _washiDay, _washiNight, Color(0xFF2B57A6), Color(0xFF7A9DE8)),
  matcha(
    'Matcha',
    _washiDay,
    _washiNight,
    Color(0xFF4E7F2E),
    Color(0xFF8DC26A),
  ),
  sakura(
    'Sakura',
    _washiDay,
    _washiNight,
    Color(0xFFC8486F),
    Color(0xFFF28DAB),
  ),
  kin('Kin', _washiDay, _washiNight, Color(0xFFA87C00), Color(0xFFE8B931));

  const OngakuPalette(
    this.label,
    this.day,
    this.night,
    this.dayAccent,
    this.nightAccent,
  );

  final String label;
  final OngakuNeutrals day;
  final OngakuNeutrals night;

  /// Null for Ongaku: the accent picked in Couleur (or the system's).
  final Color? dayAccent;
  final Color? nightAccent;

  OngakuNeutrals neutrals(bool dark) => dark ? night : day;
  Color? accent(bool dark) => dark ? nightAccent : dayAccent;

  /// Launcher icon preview (made by scripts/make_ongaku_icon.py).
  String get iconAsset => 'assets/icons/palettes/$name.png';
}

/// The theme in use.
final ValueNotifier<OngakuPalette> ongakuPalette = ValueNotifier(
  OngakuPalette.values.firstWhere(
    (p) => p.name == _readPalette(),
    orElse: () => OngakuPalette.ongaku,
  ),
);

String? _readPalette() {
  try {
    return Hive.box('settings').get('ongakuPalette') as String?;
  } catch (_) {
    return null;
  }
}

const _channel = MethodChannel('ongaku_sound');

/// Chooses a theme. The app icon follows when the app goes to the
/// background (changing it in the foreground could close the app).
void setOngakuPalette(OngakuPalette palette) {
  ongakuPalette.value = palette;
  try {
    Hive.box('settings').put('ongakuPalette', palette.name);
  } catch (_) {}
}

AppLifecycleListener? _iconListener;

/// Keeps the launcher icon on the theme's (Android).
void ongakuWatchPaletteIcon() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  _iconListener ??= AppLifecycleListener(
    onHide: () => _channel
        .invokeMethod('setLauncherIcon', {'palette': ongakuPalette.value.name})
        .catchError((Object _) => null),
  );
}
