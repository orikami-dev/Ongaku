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
import 'package:musify/ongaku/widgets/artwork_background.dart';
import 'package:musify/ongaku/widgets/ongaku_mini_player.dart'
    show MiniPlayPauseButton;
import 'package:musify/ongaku/widgets/synced_lyrics_view.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/now_playing/bottom_actions_row.dart';
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
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, _) => const OngakuNowPlayingPage(),
    ),
  );
}

/// Open foldables, tablets and desktops show the player as a side panel.
bool usesPlayerPanel(Size size) => size.width >= 600 && size.height >= 480;

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

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _toggleLyrics(bool panel) => setState(() {
    if (panel) {
      _panelLyrics = !_panelLyrics;
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
    final height = MediaQuery.sizeOf(context).height;
    final padding = MediaQuery.paddingOf(context);

    final content = Column(
      children: [
        SizedBox(height: padding.top + 8),
        const _Grabber(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(a),
                child: child,
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
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        },
        child: Material(
          type: MaterialType.transparency,
          child: ArtworkBackground(
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: _white),
              child: content,
            ),
          ),
        ),
      ),
    );
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
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            (landscape ? padding.top : 0) + 22,
            22 + padding.right,
            padding.bottom + 14,
          ),
          child: Column(
            children: [
              _PanelHeader(metadata: metadata),
              const SizedBox(height: 16),
              const _ModeChips(),
              const SizedBox(height: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, a) =>
                      FadeTransition(opacity: a, child: child),
                  child: _panelQueue
                      ? const _UpNext(key: ValueKey('queue'), dense: true)
                      : Center(
                          key: const ValueKey('art'),
                          child: _BigArtwork(metadata: metadata),
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
            // Lyrics take the whole left side, on the song's colours.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_panelLyrics,
                child: AnimatedOpacity(
                  opacity: _panelLyrics ? 1 : 0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  child: FadeTransition(
                    opacity: animation,
                    child: ArtworkBackground(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: panelWidth,
                          left: padding.left,
                        ),
                        child: _panelLyrics
                            ? SyncedLyricsView(
                                fontSize: (w - panelWidth) > 700 ? 38 : 32,
                                padding: EdgeInsets.fromLTRB(
                                  48,
                                  padding.top + 12,
                                  40,
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
            Positioned(
              right: 0,
              bottom: 0,
              width: panelWidth,
              height: panelHeight,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(1.05, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: GestureDetector(
                  onHorizontalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 600) {
                      Navigator.of(context).maybePop();
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
              duration: const Duration(milliseconds: 520),
              curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
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
              const SizedBox(width: 10),
              _MoreButton(metadata: metadata),
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
      duration: const Duration(milliseconds: 300),
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
        const SizedBox(width: 10),
        _MoreButton(metadata: metadata),
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

/// ⋮: Musify's full set of song actions (download, sleep timer, playlist…).
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return _CircleButton(
      tooltip: OngakuStrings.of(context).moreOptions,
      icon: Icons.more_horiz_rounded,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        backgroundColor: const Color(0xFF1F1F1F),
        showDragHandle: true,
        builder: (sheetContext) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              brightness: Brightness.dark,
              surfaceContainerHigh: const Color(0xFF2A2A2A),
              onSurface: _white,
              onSurfaceVariant: _whiteA(0.7),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: BottomActionsRow(
                metadata: metadata,
                iconSize: 26,
                isLargeScreen: true,
                lyricsController: _CloseSheet(sheetContext),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Upstream's lyrics button flips a card; here it just closes the sheet,
/// lyrics have their own button.
class _CloseSheet {
  _CloseSheet(this.context);

  final BuildContext context;

  void flipcard() => Navigator.of(context).pop();
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
          duration: const Duration(milliseconds: 220),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? _white : _whiteA(0.16),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
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
          duration: const Duration(milliseconds: 240),
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
        final live = total <= Duration.zero;
        final played = live
            ? 0.0
            : (data!.position.inMilliseconds / total.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        final value = _dragValue ?? played;
        final shown = live
            ? Duration.zero
            : Duration(milliseconds: (total.inMilliseconds * value).round());

        return LayoutBuilder(
          builder: (context, c) {
            double toValue(double dx) => (dx / c.maxWidth).clamp(0.0, 1.0);
            void seekTo(double v) => audioHandler.seek(
              Duration(milliseconds: (total.inMilliseconds * v).round()),
            );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: live
                  ? null
                  : (d) => setState(
                      () => _dragValue = toValue(d.localPosition.dx),
                    ),
              onHorizontalDragUpdate: live
                  ? null
                  : (d) => setState(
                      () => _dragValue = toValue(d.localPosition.dx),
                    ),
              onHorizontalDragEnd: live
                  ? null
                  : (_) {
                      seekTo(_dragValue ?? value);
                      setState(() => _dragValue = null);
                    },
              onTapUp: live ? null : (d) => seekTo(toValue(d.localPosition.dx)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
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
                      style: TextStyle(
                        color: _whiteA(0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      child: Row(
                        children: [
                          Text(live ? 'LIVE' : _format(shown)),
                          const Spacer(),
                          if (!live) Text('-${_format(total - shown)}'),
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
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _down ? _whiteA(0.14) : Colors.transparent,
          ),
          child: AnimatedScale(
            scale: _down ? 0.86 : 1,
            duration: const Duration(milliseconds: 160),
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

/// Lyrics, add to playlist, and queue, as in the reference layout.
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
          duration: const Duration(milliseconds: 240),
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
