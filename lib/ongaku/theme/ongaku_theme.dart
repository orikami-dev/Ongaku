/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/theme/app_themes.dart';

/// Apple Music's signature pink-red, used as the default accent color.
const ongakuAccent = Color(0xFFFA2D48);

/// Font bundled in assets/fonts/inter (SIL OFL), close to Apple's SF Pro.
const ongakuFontFamily = 'Inter';

/// iOS system grays, so surfaces stay neutral instead of tinted by the accent.
class _IosGrays {
  const _IosGrays.light()
    : background = const Color(0xFFFFFFFF),
      grouped = const Color(0xFFF2F2F7),
      elevated = const Color(0xFFFFFFFF),
      fill = const Color(0xFFE5E5EA),
      fillStrong = const Color(0xFFD1D1D6),
      label = const Color(0xFF000000),
      secondaryLabel = const Color(0xFF6C6C70),
      separator = const Color(0xFFC6C6C8);

  const _IosGrays.dark()
    : background = const Color(0xFF000000),
      grouped = const Color(0xFF1C1C1E),
      elevated = const Color(0xFF1C1C1E),
      fill = const Color(0xFF2C2C2E),
      fillStrong = const Color(0xFF3A3A3C),
      label = const Color(0xFFFFFFFF),
      secondaryLabel = const Color(0xFF98989F),
      separator = const Color(0xFF38383A);

  final Color background;
  final Color grouped;
  final Color elevated;
  final Color fill;
  final Color fillStrong;
  final Color label;
  final Color secondaryLabel;
  final Color separator;
}

/// Builds the app color scheme with upstream's logic (system colors, accent
/// setting), then swaps tinted Material surfaces for neutral iOS grays.
ColorScheme getOngakuColorScheme(
  ColorScheme? lightColorScheme,
  ColorScheme? darkColorScheme,
) {
  final scheme = getAppColorScheme(lightColorScheme, darkColorScheme);
  final isDark = scheme.brightness == Brightness.dark;
  final grays = isDark ? const _IosGrays.dark() : const _IosGrays.light();
  // Without system colors, use the accent exactly as picked instead of the
  // darker tone Material derives from it.
  final accent = useSystemColor.value ? scheme.primary : primaryColorSetting;
  final onAccent = accent.computeLuminance() > 0.5
      ? Colors.black
      : Colors.white;
  final accentSoft = Color.alphaBlend(
    accent.withValues(alpha: isDark ? 0.22 : 0.12),
    grays.grouped,
  );

  return scheme.copyWith(
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: accentSoft,
    onPrimaryContainer: accent,
    // Upstream paints song titles with `secondary`; Apple uses the label color.
    secondary: grays.label,
    onSecondary: grays.background,
    secondaryContainer: grays.fill,
    onSecondaryContainer: accent,
    tertiary: accent,
    tertiaryContainer: accentSoft,
    onTertiaryContainer: accent,
    surface: grays.background,
    onSurface: grays.label,
    onSurfaceVariant: grays.secondaryLabel,
    surfaceDim: grays.background,
    surfaceBright: grays.elevated,
    surfaceContainerLowest: grays.background,
    surfaceContainerLow: grays.grouped,
    surfaceContainer: grays.grouped,
    surfaceContainerHigh: grays.fill,
    surfaceContainerHighest: grays.fillStrong,
    outline: grays.secondaryLabel,
    outlineVariant: grays.separator,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
  );
}

/// Upstream theme with Apple Music styling layered on top, so component
/// themes added upstream keep applying.
ThemeData getOngakuTheme(ColorScheme colorScheme) {
  final base = getAppTheme(colorScheme);
  final cs = colorScheme;
  final isDark = cs.brightness == Brightness.dark;

  final textTheme = base.textTheme.apply(
    fontFamily: ongakuFontFamily,
    bodyColor: cs.onSurface,
    displayColor: cs.onSurface,
  );

  const iosRadius = 12.0;

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: ongakuFontFamily),
    scaffoldBackgroundColor: cs.surface,
    canvasColor: cs.surface,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: cs.onSurface.withValues(alpha: 0.06),
    hoverColor: cs.onSurface.withValues(alpha: 0.04),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: cs.primary,
      centerTitle: false,
      titleSpacing: 20,
      toolbarHeight: 60,
      titleTextStyle: TextStyle(
        fontFamily: ongakuFontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
        color: cs.onSurface,
      ),
      iconTheme: IconThemeData(color: cs.primary, size: 24),
      actionsIconTheme: IconThemeData(color: cs.primary, size: 24),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: cs.surfaceContainerLow,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(iosRadius),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      textColor: cs.onSurface,
      iconColor: cs.primary,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 58,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 26,
          color: states.contains(WidgetState.selected)
              ? cs.primary
              : cs.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: ongakuFontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? cs.primary
              : cs.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: cs.surfaceContainerLow,
      indicatorColor: cs.surfaceContainerHigh,
      indicatorShape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      selectedIconTheme: IconThemeData(color: cs.primary, size: 24),
      unselectedIconTheme: IconThemeData(color: cs.primary, size: 24),
      selectedLabelTextStyle: TextStyle(
        fontFamily: ongakuFontFamily,
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: ongakuFontFamily,
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      year2023: true,
      trackHeight: 4,
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.surfaceContainerHighest,
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 8,
        elevation: 2,
        pressedElevation: 3,
      ),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.surfaceContainerHigh,
        foregroundColor: cs.primary,
        disabledBackgroundColor: cs.surfaceContainerHigh,
        elevation: 0,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: ongakuFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(iosRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.primary,
        side: BorderSide(color: cs.outlineVariant),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(iosRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        textStyle: const TextStyle(
          fontFamily: ongakuFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: cs.primary),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 2,
      shape: const CircleBorder(),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.primary,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: ongakuFontFamily,
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: ongakuFontFamily,
        color: cs.onPrimary,
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: cs.onPrimary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF34C759) // iOS system green
            : cs.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbIcon: WidgetStateProperty.all(null),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: const Color(0xFF767680)
          .withValues(alpha: isDark ? 0.24 : 0.12),
      hintStyle: TextStyle(color: cs.onSurfaceVariant),
      prefixIconColor: cs.onSurfaceVariant,
      suffixIconColor: cs.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: cs.surfaceContainerHighest,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: isDark ? const Color(0xFF2C2C2E) : cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: base.dividerTheme.copyWith(
      color: cs.outlineVariant,
      thickness: 0.5,
      space: 0.5,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: cs.onSurfaceVariant,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: isDark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFF1C1C1E),
      contentTextStyle: const TextStyle(
        fontFamily: ongakuFontFamily,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: cs.primary,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// iOS-like scrolling everywhere: rubber-band bounce and no glow.
class OngakuScrollBehavior extends MaterialScrollBehavior {
  const OngakuScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
