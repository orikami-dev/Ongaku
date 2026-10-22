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
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/models/position_data.dart';
import 'package:musify/ongaku/screens/ongaku_now_playing_page.dart';
import 'package:musify/ongaku/widgets/glass.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Floating "glass" capsule shown above the tab bar, like Apple Music.
///
/// Tap or swipe up to open the player, swipe left/right to change track.
class OngakuMiniPlayer extends StatelessWidget {
  const OngakuMiniPlayer({super.key});

  static const double height = 62;

  /// Space the mini player takes, including its outer margin.
  static const double totalHeight = height + 8;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      initialData: audioHandler.mediaItem.valueOrNull,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        if (metadata == null) return const SizedBox.shrink();
        return _MiniPlayerCapsule(metadata: metadata);
      },
    );
  }
}

class _MiniPlayerCapsule extends StatelessWidget {
  const _MiniPlayerCapsule({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: '${metadata.title}, ${metadata.artist ?? ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openOngakuNowPlaying(context),
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
        child: GlassSurface(
          height: OngakuMiniPlayer.height,
          borderRadius: 18,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 9, right: 6),
                child: Row(
                  children: [
                    SongArtworkWidget(
                      metadata: metadata,
                      size: 44,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previous, ?current],
                        ),
                        child: _TitleAndArtist(
                          key: ValueKey(metadata.id),
                          metadata: metadata,
                        ),
                      ),
                    ),
                    const _MiniPlayPauseButton(),
                    IconButton(
                      onPressed: audioHandler.skipToNext,
                      tooltip: context.l10n?.skipToNext,
                      icon: Icon(
                        FluentIcons.next_24_filled,
                        color: colorScheme.onSurface,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 18,
                right: 18,
                bottom: 0,
                child: _MiniProgressLine(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleAndArtist extends StatelessWidget {
  const _TitleAndArtist({super.key, required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artist = metadata.artist;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
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
              color: colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (artist != null && artist.isNotEmpty)
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
      ],
    );
  }
}

class _MiniPlayPauseButton extends StatelessWidget {
  const _MiniPlayPauseButton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState.distinct(
        (a, b) =>
            a.playing == b.playing && a.processingState == b.processingState,
      ),
      builder: (context, snapshot) {
        final state = snapshot.data;
        final processing = state?.processingState;
        final playing = state?.playing ?? false;

        if (processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering) {
          return SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          );
        }

        final completed = processing == AudioProcessingState.completed;
        return IconButton(
          tooltip: playing ? context.l10n?.pause : context.l10n?.play,
          onPressed: completed
              ? audioHandler.playAgain
              : (playing ? audioHandler.pause : audioHandler.play),
          icon: Icon(
            completed
                ? FluentIcons.arrow_counterclockwise_24_filled
                : (playing
                      ? FluentIcons.pause_24_filled
                      : FluentIcons.play_24_filled),
            color: colorScheme.onSurface,
            size: 28,
          ),
        );
      },
    );
  }
}

class _MiniProgressLine extends StatelessWidget {
  const _MiniProgressLine();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
      initialData: audioHandler.currentPositionData,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final total = data?.duration.inMilliseconds ?? 0;
        final progress = total <= 0
            ? 0.0
            : (data!.position.inMilliseconds / total).clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        );
      },
    );
  }
}
