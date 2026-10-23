/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/screens/ongaku_now_playing_page.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Apple Music mini player: artwork, title, then play/pause and next, in
/// that order, docked above the tabs on phones and beside them when the
/// screen is open.
///
/// Tap or swipe up to open the player, swipe sideways to change song.
class OngakuMiniPlayer extends StatelessWidget {
  const OngakuMiniPlayer({super.key});

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      initialData: audioHandler.mediaItem.valueOrNull,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        if (metadata == null) return const SizedBox.shrink();
        return _MiniPlayerBar(metadata: metadata);
      },
    );
  }
}

class _MiniPlayerBar extends StatefulWidget {
  const _MiniPlayerBar({required this.metadata});

  final MediaItem metadata;

  @override
  State<_MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<_MiniPlayerBar> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = widget.metadata;

    return Semantics(
      button: true,
      label: '${metadata.title}, ${metadata.artist ?? ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openOngakuNowPlaying(context),
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -200) {
            openOngakuNowPlaying(context);
          }
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -400 && audioHandler.hasNext) {
            audioHandler.skipToNext();
          } else if (velocity > 400) {
            audioHandler.skipToPrevious();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: OngakuMiniPlayer.height,
          color: _pressed
              ? colorScheme.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: colorScheme.onSurface.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: SongArtworkWidget(
                  metadata: metadata,
                  size: 46,
                  borderRadius: 6,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0.06, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: MarqueeWidget(
                    key: ValueKey(metadata.id),
                    manualScrollEnabled: false,
                    animationDuration: const Duration(seconds: 8),
                    backDuration: const Duration(seconds: 2),
                    pauseDuration: const Duration(seconds: 2),
                    child: Text(
                      metadata.title,
                      maxLines: 1,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const MiniPlayPauseButton(),
              _MiniIconButton(
                icon: Icons.fast_forward_rounded,
                tooltip: context.l10n?.skipToNext,
                onPressed: audioHandler.skipToNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: 34,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Play / pause / replay with a spinner while loading, same size as the
/// other mini player buttons so they line up.
class MiniPlayPauseButton extends StatelessWidget {
  const MiniPlayPauseButton({super.key, this.size = 34, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.onSurface;

    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState.distinct(
        (a, b) =>
            a.playing == b.playing && a.processingState == b.processingState,
      ),
      initialData: audioHandler.playbackState.valueOrNull,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final processing = state?.processingState;
        final playing = state?.playing ?? false;
        final loading =
            processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering;
        final completed = processing == AudioProcessingState.completed;

        final Widget child;
        if (loading) {
          child = SizedBox.square(
            key: const ValueKey('loading'),
            dimension: size * 0.62,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
          );
        } else {
          final icon = completed
              ? Icons.replay_rounded
              : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded);
          child = Icon(icon, key: ValueKey(icon), size: size, color: color);
        }

        return IconButton(
          tooltip: playing ? context.l10n?.pause : context.l10n?.play,
          constraints: BoxConstraints.tightFor(
            width: size + 14,
            height: size + 14,
          ),
          padding: EdgeInsets.zero,
          onPressed: loading
              ? null
              : completed
              ? audioHandler.playAgain
              : (playing ? audioHandler.pause : audioHandler.play),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
