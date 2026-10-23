/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:material_ui/material_ui.dart';

/// Colours of the rounded icon tiles, as in the iOS Settings app.
const _palette = [
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFF34C759),
  Color(0xFF007AFF),
  Color(0xFF5856D6),
  Color(0xFFAF52DE),
  Color(0xFFFF2D55),
  Color(0xFF8E8E93),
];

/// Tile colour shared by the rows of one [OngakuSettingsGroup].
class OngakuTint extends InheritedWidget {
  const OngakuTint({super.key, required this.color, required super.child});

  final Color color;

  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OngakuTint>()?.color;

  @override
  bool updateShouldNotify(OngakuTint oldWidget) => color != oldWidget.color;
}

/// A grouped block: caption above, rounded card with hairline separators.
class OngakuSettingsGroup extends StatelessWidget {
  const OngakuSettingsGroup({
    super.key,
    required this.title,
    required this.tint,
    required this.children,
  });

  final String title;
  final Color tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 58,
            color: colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        children[i],
      ],
    ];

    return OngakuTint(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ClipRSuperellipse(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: colorScheme.surfaceContainerLow,
                child: Column(children: rows),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS style list row: coloured icon tile, title, optional caption, then a
/// switch or a chevron. Used by upstream's CustomBar everywhere.
class OngakuSettingsRow extends StatelessWidget {
  const OngakuSettingsRow({
    super.key,
    required this.title,
    required this.icon,
    this.description,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.backgroundColor,
    this.iconColor,
    this.textColor,
    this.borderRadius = BorderRadius.zero,
  });

  final String title;
  final IconData icon;
  final String? description;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? textColor;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tile =
        OngakuTint.maybeOf(context) ??
        iconColor ??
        _palette[icon.codePoint % _palette.length];

    return Material(
      color: backgroundColor ?? colorScheme.surfaceContainerLow,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: ShapeDecoration(
                    color: tile,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          color: textColor ?? colorScheme.onSurface,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.25,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ] else if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
