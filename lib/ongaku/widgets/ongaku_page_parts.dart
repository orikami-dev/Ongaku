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
import 'package:musify/ongaku/theme/artwork_palette.dart';
import 'package:musify/utilities/artwork_provider.dart';

/// Side margin of Apple Music pages, wider on open screens.
double ongakuPageMargin(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600 ? 32 : 20;

/// Large page title with a hairline under it and an optional round button
/// on its right, like the Apple Music Android tabs.
class OngakuLargeTitle extends StatelessWidget {
  const OngakuLargeTitle({
    super.key,
    required this.title,
    this.trailing,
    this.showBack = false,
    this.includeStatusBar = true,
    this.parentInset = 0,
  });

  final String title;
  final Widget? trailing;

  /// Pushed pages: a back chevron above the title.
  final bool showBack;

  /// False when a parent (an AppBar) already leaves room for the status bar.
  final bool includeStatusBar;

  /// Horizontal padding a parent already applies, subtracted from the page
  /// margin so every title lines up.
  final double parentInset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = (ongakuPageMargin(context) - parentInset).clamp(0.0, 64.0);
    final top = includeStatusBar ? MediaQuery.paddingOf(context).top : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        top + (showBack ? 8 : 28),
        margin,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: OngakuBackButton(),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: colorScheme.onSurface,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.1,
                    height: 1.1,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: colorScheme.onSurface.withValues(alpha: 0.18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Back chevron in the accent colour, left aligned with the page margin.
class OngakuBackButton extends StatelessWidget {
  const OngakuBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: OngakuPressable(
        onTap: () => Navigator.of(context).maybePop(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 22,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Round "You" button: a simple person, one tap opens the listening stats.
class OngakuYouButton extends StatelessWidget {
  const OngakuYouButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OngakuPressable(
      onTap: () => context.push('/home/you'),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.onSurface.withValues(alpha: 0.12),
        ),
        child: Icon(
          Icons.person_rounded,
          size: 26,
          color: colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

/// Bold section title, with a chevron when it opens a full list.
class OngakuSectionTitle extends StatelessWidget {
  const OngakuSectionTitle({
    super.key,
    required this.title,
    this.onTap,
    this.shrinkToFit = false,
  });

  final String title;
  final VoidCallback? onTap;

  /// Long titles next to action buttons shrink a little instead of being
  /// cut ("Playlists personnali…").
  final bool shrinkToFit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final style = TextStyle(
      fontFamily: 'Inter',
      color: colorScheme.onSurface,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 26, margin, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: shrinkToFit
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(title, style: style, maxLines: 1),
                    )
                  : Text(
                      title,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal shelf of items with the page margins, snapping per item.
class OngakuShelf extends StatelessWidget {
  const OngakuShelf({
    super.key,
    required this.height,
    required this.itemWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 14,
  });

  final double height;
  final double itemWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final margin = ongakuPageMargin(context);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: margin),
        physics: const BouncingScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: (context, index) =>
            SizedBox(width: itemWidth, child: itemBuilder(context, index)),
      ),
    );
  }
}

/// Number of shelf items visible at once, Apple Music style.
double ongakuShelfItemWidth(
  BuildContext context, {
  required double phone,
  required double wide,
  double gap = 14,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final margin = ongakuPageMargin(context);
  final visible = width >= 600 ? wide : phone;
  // A slice of the next item peeks in so it reads as scrollable.
  return (width - margin - gap * visible.floor()) / visible;
}

/// Pressable wrapper that shrinks slightly under the finger.
class OngakuPressable extends StatefulWidget {
  const OngakuPressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<OngakuPressable> createState() => _OngakuPressableState();
}

class _OngakuPressableState extends State<OngakuPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Tall "Pour vous" card: full-bleed artwork, its colours fading in at the
/// bottom behind the caption, title and subtitle.
class OngakuTallCard extends StatelessWidget {
  const OngakuTallCard({
    super.key,
    required this.image,
    required this.caption,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final String? image;
  final String caption;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uri = image == null ? null : Uri.tryParse(image!);
    return OngakuPressable(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FutureBuilder<ArtworkPalette?>(
            future: uri == null ? null : paletteForArtwork(uri),
            builder: (context, snapshot) {
              final tone = snapshot.data?.colors[1] ?? const Color(0xFF3A3A3C);
              return ClipRSuperellipse(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: tone),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: constraints.maxHeight * 0.78,
                      child: OngakuCoverImage(image),
                    ),
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              tone.withValues(alpha: 0),
                              tone.withValues(alpha: 0),
                              tone.withValues(alpha: 0.92),
                              tone,
                            ],
                            stops: const [0, 0.45, 0.72, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Square artwork with a title and subtitle underneath.
class OngakuSquareTile extends StatelessWidget {
  const OngakuSquareTile({
    super.key,
    required this.artwork,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final Widget artwork;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OngakuPressable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(10),
              child: artwork,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }
}

/// Artwork filling its box, with a neutral placeholder when missing.
class OngakuCoverImage extends StatelessWidget {
  const OngakuCoverImage(this.url, {super.key});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return const _CoverPlaceholder();
    return Image(
      image: ArtworkProvider.get(url),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.onSurface.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 40,
          color: colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
