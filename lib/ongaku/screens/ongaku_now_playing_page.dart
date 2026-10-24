/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/models/position_data.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/layout/adaptive.dart' show foldSplitFrom;
import 'package:musify/ongaku/lyrics/synced_lyrics.dart' show fetchTimedLyrics;
import 'package:musify/ongaku/screens/ongaku_sound_page.dart'
    show CrossfadeControls;
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';
import 'package:musify/ongaku/widgets/artwork_background.dart';
import 'package:musify/ongaku/widgets/ongaku_mini_player.dart'
    show MiniPlayPauseButton;
import 'package:musify/ongaku/widgets/ongaku_popover.dart';
import 'package:musify/ongaku/widgets/synced_lyrics_view.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Opens the player: full screen on phones, a panel on the right of open
/// foldables and tablets (Apple Music on Android).
Future<void> openOngakuNowPlaying(BuildContext context) {
  final panel = usesPlayerPanel(MediaQuery.sizeOf(context));
  HapticFeedback.lightImpact();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration(milliseconds: panel ? 420 : 480),
      pageBuilder: (context, animation, _) => const OngakuNowPlayingPage(),
    ),
  );
}

/// Open foldables, tablets and desktops show the player as a side panel.
bool usesPlayerPanel(Size size) => size.width >= 600 && size.height >= 480;

/// The fold of a foldable half opened like a laptop or standing on a table
/// (flex or tabletop posture), or a physical hinge: a horizontal line across
/// the screen. Null when the screen is flat or the fold is vertical.
Rect? tabletopHinge(MediaQueryData media) {
  final split = foldSplitFrom(media.displayFeatures, media.size);
  return split == null || split.isSideBySide ? null : split.bounds;
}

const _white = Colors.white;
Color _whiteA(double a) => Colors.white.withValues(alpha: a);

enum _View { artwork, lyrics, queue }

class OngakuNowPlayingPage extends StatefulWidget {
  const OngakuNowPlayingPage({super.key});

  @override
  State<OngakuNowPlayingPage> createState() => _OngakuNowPlayingPageState();
}

class _OngakuNowPlayingPageState extends State<OngakuNowPlayingPage>
    with SingleTickerProviderStateMixin {
  _View _phoneView = _View.artwork;
  bool _panelLyrics = false;
  bool _panelQueue = true;

  // Drag down to close on phones.
  late final _drag = AnimationController(vsync: this, upperBound: 2000);

  // The lyrics card stays built once opened, so it reopens at once.
  bool _lyricsBuilt = false;
  StreamSubscription<MediaItem?>? _prefetch;

  @override
  void initState() {
    super.initState();
    // Lyrics are looked up as soon as a song plays, before they are asked.
    _prefetch = audioHandler.mediaItem.listen((item) {
      if (item != null) fetchTimedLyrics(item).ignore();
    });
  }

  @override
  void dispose() {
    _prefetch?.cancel();
    _drag.dispose();
    super.dispose();
  }

  void _toggleLyrics(bool panel) => setState(() {
    if (panel) {
      _panelLyrics = !_panelLyrics;
      _lyricsBuilt = true;
    } else {
      _phoneView = _phoneView == _View.lyrics ? _View.artwork : _View.lyrics;
    }
  });

  void _toggleQueue(bool panel) => setState(() {
    if (panel) {
      _panelQueue = !_panelQueue;
    } else {
      _phoneView = _phoneView == _View.queue ? _View.artwork : _View.queue;
    }
  });

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)!;
    final animation = CurvedAnimation(
      parent: route.animation!,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      initialData: audioHandler.mediaItem.valueOrNull,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        if (metadata == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && route.isCurrent) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        // Half folded: artwork or lyrics above the hinge, controls and
        // queue below it.
        final hinge = tabletopHinge(MediaQuery.of(context));
        if (hinge != null) {
          return _buildTabletop(context, metadata, animation, hinge);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final panel = usesPlayerPanel(constraints.biggest);
            return panel
                ? _buildPanel(context, metadata, animation, constraints)
                : _buildPhone(context, metadata, animation);
          },
        );
      },
    );
  }

  // ------------------------------------------------------------ phone

  Widget _buildPhone(
    BuildContext context,
    MediaItem metadata,
    Animation<double> animation,
  ) {
    final padding = MediaQuery.paddingOf(context);

    final content = Column(
      children: [
        SizedBox(height: padding.top + 8),
        const _Grabber(),
        Expanded(
          child: AnimatedSwitcher(
            duration: OngakuMotion.slow,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            // Lyrics and queue rise out of the controls, inside the
            // player; the artwork settles back in.
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: child.key == const ValueKey('art')
                      ? Offset.zero
                      : const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(a),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1).animate(a),
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            ),
            child: switch (_phoneView) {
              _View.artwork => _PhoneArtworkView(
                key: const ValueKey('art'),
                metadata: metadata,
              ),
              _View.lyrics => Column(
                key: const ValueKey('lyrics'),
                children: [
                  _CompactHeader(metadata: metadata),
                  const Expanded(
                    child: SyncedLyricsView(
                      fontSize: 28,
                      padding: EdgeInsets.fromLTRB(28, 0, 28, 0),
                    ),
                  ),
                ],
              ),
              _View.queue => Column(
                key: const ValueKey('queue'),
                children: [
                  _CompactHeader(metadata: metadata),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: _ModeChips(),
                  ),
                  const Expanded(child: _UpNext()),
                ],
              ),
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: _ProgressBar(),
        ),
        const SizedBox(height: 6),
        const _TransportControls(size: 46),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: _VolumeBar(),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: _BottomButtons(
            metadata: metadata,
            lyricsOn: _phoneView == _View.lyrics,
            queueOn: _phoneView == _View.queue,
            onLyrics: () => _toggleLyrics(false),
            onQueue: () => _toggleQueue(false),
          ),
        ),
        SizedBox(height: padding.bottom + 14),
      ],
    );

    return _pulledSheet(context, animation, content);
  }

  /// The full screen player sheet: pulled up from the bottom when it opens,
  /// and down again with the finger to close it.
  Widget _pulledSheet(
    BuildContext context,
    Animation<double> animation,
    Widget content,
  ) {
    final height = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, _drag]),
      builder: (context, child) {
        final offset = (1 - animation.value) * height + _drag.value;
        return Transform.translate(
          offset: Offset(0, offset),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(
                _drag.value > 0 || animation.value < 1 ? 28 : 0,
              ),
            ),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onVerticalDragUpdate: (d) =>
            _drag.value = (_drag.value + d.delta.dy).clamp(0, 2000),
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (_drag.value > 140 || v > 800) {
            Navigator.of(context).pop();
          } else {
            _drag.animateTo(
              0,
              duration: OngakuMotion.medium,
              curve: Curves.easeOutCubic,
            );
          }
        },
        child: Material(
          type: MaterialType.transparency,
          child: ArtworkBackground(
            translucent: true,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: _white),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ tabletop

  Widget _buildTabletop(
    BuildContext context,
    MediaItem metadata,
    Animation<double> animation,
    Rect hinge,
  ) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final wide = size.width >= 600;

    final top = AnimatedSwitcher(
      duration: OngakuMotion.slow,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _panelLyrics
          ? SyncedLyricsView(
              key: const ValueKey('lyrics'),
              fontSize: wide ? 30 : 26,
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            )
          : Padding(
              key: const ValueKey('art'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(child: _BigArtwork(metadata: metadata)),
            ),
    );

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: _TitleArtist(metadata: metadata)),
            const SizedBox(width: 8),
            _StarButton(metadata: metadata),
          ],
        ),
        const SizedBox(height: 8),
        const _ProgressBar(),
        const SizedBox(height: 2),
        const _TransportControls(size: 40),
        const SizedBox(height: 10),
        _BottomButtons(
          metadata: metadata,
          lyricsOn: _panelLyrics,
          queueOn: _panelQueue,
          onLyrics: () => _toggleLyrics(true),
          onQueue: () => _toggleQueue(true),
        ),
      ],
    );

    final queue = AnimatedSwitcher(
      duration: OngakuMotion.medium,
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
      child: _panelQueue
          ? const _UpNext(key: ValueKey('queue'), dense: true)
          : const SizedBox.shrink(),
    );

    final bottom = wide
        ? Row(
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: controls,
                  ),
                ),
              ),
              if (_panelQueue) ...[
                const SizedBox(width: 24),
                Expanded(flex: 4, child: queue),
              ],
            ],
          )
        : Column(
            children: [
              Expanded(child: queue),
              const SizedBox(height: 8),
              controls,
            ],
          );

    final content = Column(
      children: [
        SizedBox(
          height: hinge.top,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24 + padding.left,
              padding.top + 8,
              24 + padding.right,
              8,
            ),
            child: Column(
              children: [
                const _Grabber(),
                Expanded(child: top),
              ],
            ),
          ),
        ),
        SizedBox(height: hinge.height),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22 + padding.left,
              14,
              22 + padding.right,
              padding.bottom + 12,
            ),
            child: bottom,
          ),
        ),
      ],
    );

    return _pulledSheet(context, animation, content);
  }

  // ------------------------------------------------------------ panel

  Widget _buildPanel(
    BuildContext context,
    MediaItem metadata,
    Animation<double> animation,
    BoxConstraints constraints,
  ) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final landscape = w > h;
    final panelWidth = (w * (landscape ? 0.4 : 0.5)).clamp(340.0, 500.0);
    final panelHeight = landscape ? h : (h * 0.68).clamp(520.0, h);
    final padding = MediaQuery.paddingOf(context);

    final panel = ClipRRect(
      borderRadius: landscape
          ? BorderRadius.zero
          : const BorderRadius.only(topLeft: Radius.circular(26)),
      child: ArtworkBackground(
        dim: 0.35,
        translucent: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            (landscape ? padding.top : 0) + 22,
            22 + padding.right,
            padding.bottom + 14,
          ),
          child: Column(
            children: [
              // Header and modes come with the queue; with the big artwork
              // the title goes under it, so the artwork shows once.
              AnimatedSize(
                duration: OngakuMotion.medium,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _panelQueue
                    ? Column(
                        children: [
                          _PanelHeader(metadata: metadata),
                          const SizedBox(height: 16),
                          const _ModeChips(),
                          const SizedBox(height: 10),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: OngakuMotion.medium,
                  transitionBuilder: (child, a) =>
                      FadeTransition(opacity: a, child: child),
                  child: _panelQueue
                      ? const _UpNext(key: ValueKey('queue'), dense: true)
                      : Column(
                          key: const ValueKey('art'),
                          children: [
                            Expanded(
                              child: Center(
                                child: _BigArtwork(metadata: metadata),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _TitleArtist(
                                    metadata: metadata,
                                    large: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StarButton(metadata: metadata),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 10),
              const _ProgressBar(),
              const SizedBox(height: 4),
              const _TransportControls(size: 44),
              const SizedBox(height: 12),
              _BottomButtons(
                metadata: metadata,
                lyricsOn: _panelLyrics,
                queueOn: _panelQueue,
                onLyrics: () => _toggleLyrics(true),
                onQueue: () => _toggleQueue(true),
              ),
            ],
          ),
        ),
      ),
    );

    // The panel and its lyrics move together: pulled up from the bottom
    // when it opens, and down again with the finger to close it.
    Widget pulled(Widget child) => AnimatedBuilder(
      animation: Listenable.merge([animation, _drag]),
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (1 - animation.value) * h + _drag.value),
        child: child,
      ),
      child: child,
    );

    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _white),
        child: Stack(
          children: [
            // The app dims behind the panel; tap it to close.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: FadeTransition(
                  opacity: animation,
                  child: const ColoredBox(color: Color(0x8C000000)),
                ),
              ),
            ),
            // Lyrics slide out of the player into their own card beside
            // it, the same height; the page behind stays visible.
            Positioned(
              right: panelWidth + 12,
              bottom: landscape ? padding.bottom + 12 : 0,
              height: landscape
                  ? panelHeight - padding.top - padding.bottom - 24
                  : panelHeight,
              width: (w - panelWidth - 12 - padding.left - 12).clamp(
                0.0,
                panelWidth * 1.15,
              ),
              child: pulled(
                IgnorePointer(
                  ignoring: !_panelLyrics,
                  child: AnimatedSlide(
                    offset: _panelLyrics ? Offset.zero : const Offset(0.6, 0),
                    duration: OngakuMotion.slow,
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _panelLyrics ? 1 : 0,
                      duration: OngakuMotion.medium,
                      child: AnimatedScale(
                        scale: _panelLyrics ? 1 : 0.9,
                        alignment: Alignment.centerRight,
                        duration: OngakuMotion.slow,
                        curve: Curves.easeOutCubic,
                        child: ClipRSuperellipse(
                          borderRadius: BorderRadius.circular(26),
                          child: ArtworkBackground(
                            translucent: true,
                            child: _lyricsBuilt
                                ? SyncedLyricsView(
                                    fontSize: w - panelWidth > 600 ? 30 : 25,
                                    padding: const EdgeInsets.fromLTRB(
                                      28,
                                      20,
                                      24,
                                      0,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              width: panelWidth,
              height: panelHeight,
              child: pulled(
                GestureDetector(
                  onVerticalDragUpdate: (d) =>
                      _drag.value = (_drag.value + d.delta.dy).clamp(0, 2000),
                  onVerticalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (_drag.value > 140 || v > 800) {
                      Navigator.of(context).maybePop();
                    } else {
                      _drag.animateTo(
                        0,
                        duration: OngakuMotion.medium,
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  child: panel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================ pieces

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 5,
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: _whiteA(0.45),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

/// Big artwork that eases smaller while paused, like Apple Music.
class _BigArtwork extends StatelessWidget {
  const _BigArtwork({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest.shortestSide;
        return StreamBuilder<bool>(
          stream: audioHandler.playbackState.map((s) => s.playing).distinct(),
          initialData: audioHandler.playbackState.valueOrNull?.playing,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? false;
            return AnimatedScale(
              scale: playing ? 1 : 0.82,
              duration: OngakuMotion.slow,
              curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: OngakuMotion.slow,
                child: DecoratedBox(
                  key: ValueKey(metadata.id),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: playing ? 0.4 : 0.2,
                        ),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: SongArtworkWidget(
                    metadata: metadata,
                    size: size,
                    borderRadius: 12,
                    errorWidgetIconSize: size * 0.3,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PhoneArtworkView extends StatelessWidget {
  const _PhoneArtworkView({super.key, required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: _BigArtwork(metadata: metadata)),
            ),
          ),
          Row(
            children: [
              Expanded(child: _TitleArtist(metadata: metadata, large: true)),
              const SizedBox(width: 8),
              _StarButton(metadata: metadata),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _TitleArtist extends StatelessWidget {
  const _TitleArtist({required this.metadata, this.large = false});

  final MediaItem metadata;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: OngakuMotion.medium,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey(metadata.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MarqueeWidget(
            manualScrollEnabled: false,
            animationDuration: const Duration(seconds: 8),
            backDuration: const Duration(seconds: 2),
            pauseDuration: const Duration(seconds: 2),
            child: Text(
              metadata.title,
              maxLines: 1,
              style: TextStyle(
                color: _white,
                fontSize: large ? 21 : 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if ((metadata.artist ?? '').isNotEmpty)
            Text(
              metadata.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _whiteA(0.62), fontSize: large ? 19 : 16),
            ),
        ],
      ),
    );
  }
}

/// Small artwork, title and buttons above the lyrics or queue (phone).
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: _PanelHeader(metadata: metadata),
    );
  }
}

/// Artwork, title, artist, star and ⋮ (panel header).
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SongArtworkWidget(
            metadata: metadata,
            size: 64,
            borderRadius: 6,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: _TitleArtist(metadata: metadata)),
        const SizedBox(width: 8),
        _StarButton(metadata: metadata),
      ],
    );
  }
}

/// Favourite star: white disc when the song is liked.
class _StarButton extends StatelessWidget {
  const _StarButton({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final id = metadata.extras?['ytid']?.toString();
    final isRadio = metadata.extras?['isLive'] == true;
    final Listenable source = isRadio
        ? userLikedRadioStations
        : userLikedSongsList;

    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final liked =
            id != null &&
            (isRadio ? isRadioStationLiked(id) : isSongAlreadyLiked(id));
        return _CircleButton(
          tooltip: OngakuStrings.of(context).favorite,
          filled: liked,
          icon: liked ? Icons.star_rounded : Icons.star_outline_rounded,
          onPressed: id == null
              ? null
              : () async {
                  unawaited(HapticFeedback.selectionClick());
                  if (isRadio) {
                    await (liked
                        ? removeRadioStationFromLiked(id)
                        : addRadioStationToLiked(id));
                  } else {
                    await updateSongLikeStatus(
                      id,
                      !liked,
                      songData: mediaItemToMap(metadata),
                    );
                  }
                },
        );
      },
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: OngakuMotion.quick,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? _white : _whiteA(0.16),
          ),
          child: AnimatedSwitcher(
            duration: OngakuMotion.quick,
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Icon(
              icon,
              key: ValueKey(icon),
              size: 22,
              color: filled ? Colors.black87 : _white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shuffle, repeat and autoplay as three pill buttons.
class _ModeChips extends StatelessWidget {
  const _ModeChips();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: shuffleNotifier,
            builder: (context, on, _) => _Chip(
              icon: Icons.shuffle_rounded,
              on: on,
              tooltip: l10n?.shuffle,
              onTap: () => audioHandler.setShuffleMode(
                on ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder<AudioServiceRepeatMode>(
            valueListenable: repeatNotifier,
            builder: (context, mode, _) => _Chip(
              icon: mode == AudioServiceRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              on: mode != AudioServiceRepeatMode.none,
              tooltip: l10n?.repeat,
              onTap: () {
                // Same cycle as Musify: off, all, one.
                final queueLength = audioHandler.queue.valueOrNull?.length ?? 0;
                final next = switch (mode) {
                  AudioServiceRepeatMode.none =>
                    queueLength <= 1
                        ? AudioServiceRepeatMode.one
                        : AudioServiceRepeatMode.all,
                  AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                  _ => AudioServiceRepeatMode.none,
                };
                repeatNotifier.value = next;
                audioHandler.setRepeatMode(next);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: playNextSongAutomatically,
            builder: (context, on, _) => _Chip(
              icon: Icons.all_inclusive_rounded,
              on: on,
              tooltip: OngakuStrings.of(context).autoplay,
              onTap: () {
                // Same storage as the switch in Musify's settings.
                addOrUpdateData<bool>(
                  'settings',
                  'playNextSongAutomatically',
                  !on,
                );
                playNextSongAutomatically.value = !on;
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder<CrossfadeMode>(
            valueListenable: crossfadeMode,
            builder: (context, mode, _) => _Chip(
              icon: Icons.waves_rounded,
              on: mode != CrossfadeMode.off,
              tooltip: OngakuStrings.of(context).crossfade,
              onTap: () => _showCrossfadeSheet(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.on,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: OngakuMotion.quick,
          curve: Curves.easeOutCubic,
          height: 40,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: on ? _whiteA(0.78) : _whiteA(0.14),
          ),
          child: Icon(
            icon,
            size: 22,
            color: on ? Colors.black.withValues(alpha: 0.75) : _white,
          ),
        ),
      ),
    );
  }
}

/// The songs after the current one: tap to play, drag ≡ to move, swipe to
/// remove.
class _UpNext extends StatelessWidget {
  const _UpNext({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final side = dense ? 0.0 : 24.0;

    return StreamBuilder<List<Map>>(
      stream: audioHandler.queueAsMapStream,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? const <Map>[];
        final start = audioHandler.currentQueueIndex + 1;
        final upcoming = start < queue.length
            ? queue.sublist(start)
            : const <Map>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 6),
              child: Text(
                strings.upNext,
                style: const TextStyle(
                  color: _white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Expanded(
              child: upcoming.isEmpty
                  ? const SizedBox.shrink()
                  : ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_white, _white, Colors.transparent],
                        stops: [0, 0.9, 1],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: ReorderableListView.builder(
                        padding: EdgeInsets.fromLTRB(side, 0, side, 24),
                        buildDefaultDragHandles: false,
                        itemCount: upcoming.length,
                        proxyDecorator: (child, _, __) => Material(
                          color: _whiteA(0.12),
                          borderRadius: BorderRadius.circular(10),
                          child: child,
                        ),
                        onReorderItem: (oldIndex, newIndex) {
                          final id = upcoming[oldIndex]['queueEntryId']
                              ?.toString();
                          if (id == null) return;
                          audioHandler.reorderQueueById(id, start + newIndex);
                        },
                        itemBuilder: (context, i) {
                          final song = upcoming[i];
                          final key =
                              '${song['queueEntryId'] ?? song['ytid']}_$i';
                          return Dismissible(
                            key: ValueKey(key),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) =>
                                audioHandler.removeFromQueue(start + i),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              child: const Icon(
                                Icons.delete_rounded,
                                color: _white,
                              ),
                            ),
                            child: _QueueRow(
                              song: song,
                              index: i,
                              onTap: () => audioHandler.skipToSong(start + i),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  final Map song;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artist = song['artist']?.toString() ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SongArtworkWidget(
              metadata: mapToMediaItem(song),
              size: 50,
              borderRadius: 5,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (artist.isNotEmpty)
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _whiteA(0.6), fontSize: 14),
                    ),
                ],
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Icon(Icons.drag_handle_rounded, color: _whiteA(0.45)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thick Apple style progress bar; grows while dragged.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar();

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
      initialData: audioHandler.currentPositionData,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final total = data?.duration ?? Duration.zero;
        // Radio stations have no end. A song whose length is not known yet
        // (the first moments of playback) is not "live": it just shows 0:00
        // until the duration arrives.
        final live =
            audioHandler.mediaItem.valueOrNull?.extras?['isLive'] == true;
        final seekable = !live && total > Duration.zero;
        final played = seekable
            ? (data!.position.inMilliseconds / total.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final value = _dragValue ?? played;
        final shown = seekable
            ? Duration(milliseconds: (total.inMilliseconds * value).round())
            : Duration.zero;

        return LayoutBuilder(
          builder: (context, c) {
            double toValue(double dx) => (dx / c.maxWidth).clamp(0.0, 1.0);
            void seekTo(double v) => audioHandler.seek(
              Duration(milliseconds: (total.inMilliseconds * v).round()),
            );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: !seekable
                  ? null
                  : (d) => setState(
                      () => _dragValue = toValue(d.localPosition.dx),
                    ),
              onHorizontalDragUpdate: !seekable
                  ? null
                  : (d) => setState(
                      () => _dragValue = toValue(d.localPosition.dx),
                    ),
              onHorizontalDragEnd: !seekable
                  ? null
                  : (_) {
                      seekTo(_dragValue ?? value);
                      setState(() => _dragValue = null);
                    },
              onTapUp: !seekable
                  ? null
                  : (d) => seekTo(toValue(d.localPosition.dx)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: OngakuMotion.quick,
                      height: _dragValue != null ? 11 : 7,
                      decoration: BoxDecoration(
                        color: _whiteA(0.22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value,
                        heightFactor: 1,
                        child: ColoredBox(
                          color: _dragValue != null ? _white : _whiteA(0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DefaultTextStyle(
                      // Explicit family: a bare DefaultTextStyle would fall
                      // back to the system font for the times.
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: _whiteA(0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      child: Row(
                        children: [
                          Text(live ? 'LIVE' : _format(shown)),
                          const Spacer(),
                          if (!live)
                            Text(
                              seekable ? '-${_format(total - shown)}' : '-:--',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _PressIcon(
          icon: Icons.fast_rewind_rounded,
          size: size,
          tooltip: context.l10n?.skipToPrevious,
          onTap: audioHandler.skipToPrevious,
        ),
        MiniPlayPauseButton(size: size * 1.3, color: _white),
        _PressIcon(
          icon: Icons.fast_forward_rounded,
          size: size,
          tooltip: context.l10n?.skipToNext,
          onTap: audioHandler.skipToNext,
        ),
      ],
    );
  }
}

/// Icon that pops slightly under the finger, like the iOS transport keys.
class _PressIcon extends StatefulWidget {
  const _PressIcon({
    required this.icon,
    required this.size,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_PressIcon> createState() => _PressIconState();
}

class _PressIconState extends State<_PressIcon> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) {
          _set(false);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: OngakuMotion.fast,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _down ? _whiteA(0.14) : Colors.transparent,
          ),
          child: AnimatedScale(
            scale: _down ? 0.86 : 1,
            duration: OngakuMotion.fast,
            child: Icon(widget.icon, size: widget.size, color: _white),
          ),
        ),
      ),
    );
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: audioHandler.volumeStream,
      initialData: audioHandler.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0);
        return Row(
          children: [
            Icon(Icons.volume_mute_rounded, size: 20, color: _whiteA(0.55)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  void set(double dx) =>
                      audioHandler.setVolume((dx / c.maxWidth).clamp(0.0, 1.0));
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
                    onTapUp: (d) => set(d.localPosition.dx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: _whiteA(0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: volume,
                          heightFactor: 1,
                          child: ColoredBox(color: _whiteA(0.85)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Icon(Icons.volume_up_rounded, size: 20, color: _whiteA(0.55)),
          ],
        );
      },
    );
  }
}

/// Everything that used to live in the ⋯ menu, once each: lyrics, add to a
/// playlist, download, sleep timer and queue.
class _BottomButtons extends StatelessWidget {
  const _BottomButtons({
    required this.metadata,
    required this.lyricsOn,
    required this.queueOn,
    required this.onLyrics,
    required this.onQueue,
  });

  final MediaItem metadata;
  final bool lyricsOn;
  final bool queueOn;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isRadio = metadata.extras?['isLive'] == true;
    final isLocal = metadata.extras?['isLocal'] == true;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToggleSquare(
          icon: Icons.format_quote_rounded,
          on: lyricsOn,
          tooltip: l10n?.lyrics,
          onTap: isRadio ? null : onLyrics,
        ),
        _ToggleSquare(
          icon: Icons.playlist_add_rounded,
          on: false,
          tooltip: l10n?.addToPlaylist,
          onTap: isRadio || offlineMode.value
              ? null
              : () => showAddToPlaylistDialog(
                  context,
                  song: mediaItemToMap(metadata),
                ),
        ),
        _DownloadSquare(metadata: metadata, enabled: !isRadio && !isLocal),
        const _SleepSquare(),
        _ToggleSquare(
          icon: Icons.format_list_bulleted_rounded,
          on: queueOn,
          tooltip: l10n?.queue,
          onTap: isRadio ? null : onQueue,
        ),
      ],
    );
  }
}

/// Download for offline listening, filled when the song is saved.
class _DownloadSquare extends StatefulWidget {
  const _DownloadSquare({required this.metadata, required this.enabled});

  final MediaItem metadata;
  final bool enabled;

  @override
  State<_DownloadSquare> createState() => _DownloadSquareState();
}

class _DownloadSquareState extends State<_DownloadSquare> {
  bool _busy = false;

  Future<void> _toggle(String id, bool saved) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (saved) {
        await OfflinePlaylistService().removeSongFromOfflineAndResync(id);
      } else {
        await makeSongOffline(mediaItemToMap(widget.metadata));
      }
    } catch (e) {
      logger.log('Error toggling offline status', error: e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.metadata.extras?['ytid']?.toString();
    final strings = OngakuStrings.of(context);
    return ListenableBuilder(
      listenable: userOfflineSongs,
      builder: (context, _) {
        final saved = id != null && isSongAlreadyOffline(id);
        return _ToggleSquare(
          icon: _busy
              ? Icons.hourglass_top_rounded
              : (saved
                    ? Icons.download_done_rounded
                    : Icons.arrow_circle_down_rounded),
          on: saved,
          tooltip: saved ? strings.removeDownload : strings.download,
          onTap: widget.enabled && id != null ? () => _toggle(id, saved) : null,
        );
      },
    );
  }
}

/// Sleep timer: lit while a timer runs, tap again to cancel.
class _SleepSquare extends StatelessWidget {
  const _SleepSquare();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    return ValueListenableBuilder<Duration?>(
      valueListenable: sleepTimerNotifier,
      builder: (context, remaining, _) {
        final active = remaining != null;
        return _ToggleSquare(
          icon: Icons.bedtime_rounded,
          on: active,
          tooltip: l10n.sleepTimer,
          onTap: () {
            if (active) {
              audioHandler.cancelSleepTimer();
              sleepTimerNotifier.value = null;
              showToast(context, l10n.sleepTimerCancelled);
            } else {
              _showSleepSheet(context);
            }
          },
        );
      },
    );
  }
}

/// Mode doux: off, Auto or a chosen length, in a panel out of its button.
void _showCrossfadeSheet(BuildContext context) {
  final strings = OngakuStrings.of(context);
  showOngakuPopover<void>(
    context,
    builder: (popover) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.crossfade,
          style: const TextStyle(
            color: _white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const CrossfadeControls(dark: true),
      ],
    ),
  );
}

void _showSleepSheet(BuildContext context) {
  final l10n = context.l10n!;
  final strings = OngakuStrings.of(context);
  const minutes = [5, 10, 15, 30, 45, 60, 90];

  showOngakuPopover<void>(
    context,
    builder: (sheet) => Padding(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.sleepTimer,
            style: const TextStyle(
              color: _white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in minutes)
                _SleepChip(
                  label: strings.minShort(m),
                  onTap: () {
                    audioHandler.setSleepTimer(Duration(minutes: m));
                    Navigator.pop(sheet);
                    showToast(context, l10n.sleepTimerSet);
                  },
                ),
              _SleepChip(
                label: strings.endOfSong,
                onTap: () {
                  audioHandler.setSleepTimerEndOfSong();
                  Navigator.pop(sheet);
                  showToast(context, l10n.sleepTimerSet);
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SleepChip extends StatelessWidget {
  const _SleepChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: _whiteA(0.14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ToggleSquare extends StatelessWidget {
  const _ToggleSquare({
    required this.icon,
    required this.on,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool on;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap!();
              }
            : null,
        child: AnimatedContainer(
          duration: OngakuMotion.quick,
          curve: Curves.easeOutCubic,
          width: 44,
          height: 40,
          decoration: BoxDecoration(
            color: on ? _whiteA(0.85) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 26,
            color: on
                ? Colors.black.withValues(alpha: 0.75)
                : _whiteA(enabled ? 0.85 : 0.3),
          ),
        ),
      ),
    );
  }
}
