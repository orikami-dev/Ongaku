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
import 'package:musify/ongaku/screens/ongaku_shell.dart';
import 'package:musify/ongaku/widgets/ongaku_ui_scale.dart';

/// Status and navigation bars that follow the app's theme, not the system's,
/// the app's soft fade-in when it opens, and its size fitted to the screen.
///
/// The Android window takes its background from the system day/night theme,
/// so a dark Ongaku on a phone in day mode showed a white navigation bar.
/// The bar gets the colour of the tab bar, and its icons the app's contrast.
class OngakuSystemBars extends StatelessWidget {
  const OngakuSystemBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: icons,
        systemNavigationBarColor: OngakuShell.barColor(colorScheme),
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: icons,
      ),
      // The app fades in over the plain opening screen, once.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: OngakuUiScale(child: child),
      ),
    );
  }
}
