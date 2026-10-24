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

/// The hero of a playlist, album or artist page: the cover with its title
/// fixed under it. Both scroll away together; a small title fades into the
/// toolbar once the hero is gone, instead of a title that moves and grows.
class OngakuPlaylistSpace extends StatelessWidget {
  const OngakuPlaylistSpace({
    super.key,
    required this.title,
    required this.artwork,
  });

  final String title;
  final Widget artwork;

  /// Room left under the cover for two lines of title.
  static const titleHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final topInset = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = settings?.maxExtent ?? constraints.maxHeight;
        final minExtent = settings?.minExtent ?? kToolbarHeight + topInset;
        final current = settings?.currentExtent ?? constraints.maxHeight;
        final range = maxExtent - minExtent;
        final t = range <= 0
            ? 1.0
            : ((current - minExtent) / range).clamp(0.0, 1.0);
        final heroOpacity = (t / 0.45).clamp(0.0, 1.0);
        final barOpacity = ((0.2 - t) / 0.2).clamp(0.0, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            if (heroOpacity > 0)
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: maxExtent,
                  maxHeight: maxExtent,
                  child: Opacity(
                    opacity: heroOpacity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 0),
                      child: Column(
                        children: [
                          Expanded(child: Center(child: artwork)),
                          SizedBox(
                            height: titleHeight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                  letterSpacing: 0,
                                  height: 1.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (barOpacity > 0)
              Positioned(
                top: topInset,
                left: 64,
                right: 64,
                height: kToolbarHeight,
                child: Opacity(
                  opacity: barOpacity,
                  child: Center(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One chip beside the round buttons: its icon, the full label, and a
/// shorter label used when the screen is too narrow for the full one.
typedef OngakuChipInfo = ({IconData icon, String label, String? short});

/// The round buttons of a playlist with the type chip on their left and the
/// count chip on their right. On narrow screens the chips shrink to their
/// icon or their number rather than wrapping under the buttons.
class OngakuChipRow extends StatelessWidget {
  const OngakuChipRow({super.key, required this.actions, this.start, this.end});

  final List<Widget> actions;
  final OngakuChipInfo? start;
  final OngakuChipInfo? end;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget side(OngakuChipInfo? info, Alignment alignment, bool primary) {
      return Expanded(
        child: Align(
          alignment: alignment,
          child: info == null
              ? const SizedBox.shrink()
              : _FittingChip(
                  info: info,
                  color: primary
                      ? colorScheme.primaryContainer
                      : colorScheme.secondaryContainer,
                  onColor: primary
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSecondaryContainer,
                ),
        ),
      );
    }

    return Row(
      children: [
        side(start, Alignment.centerLeft, true),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 5,
              children: actions,
            ),
          ),
        side(end, Alignment.centerRight, false),
      ],
    );
  }
}

class _FittingChip extends StatelessWidget {
  const _FittingChip({
    required this.info,
    required this.color,
    required this.onColor,
  });

  final OngakuChipInfo info;
  final Color color;
  final Color onColor;

  static const _padding = 12.0;
  static const _iconSize = 14.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: onColor,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          return painter.width + _padding * 2 + _iconSize + _gap;
        }

        // Full label, then the short one, then the short one alone (a
        // number), and only the icon when there is no short label.
        String? label = info.label;
        var showIcon = true;
        if (widthOf(info.label) > constraints.maxWidth) {
          label = info.short;
          if (label != null && widthOf(label) > constraints.maxWidth) {
            showIcon = false;
          }
        }

        final iconOnly = label == null;
        final chip = Tooltip(
          message: info.label,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly ? 9 : (showIcon ? _padding : 9),
              vertical: iconOnly ? 9 : 7,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon) Icon(info.icon, size: _iconSize, color: onColor),
                if (showIcon && !iconOnly) const SizedBox(width: _gap),
                if (!iconOnly) Text(label, style: style, maxLines: 1),
              ],
            ),
          ),
        );
        return showIcon && !iconOnly
            ? chip
            : FittedBox(fit: BoxFit.scaleDown, child: chip);
      },
    );
  }
}
