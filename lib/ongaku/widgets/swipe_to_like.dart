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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/utilities/flutter_toast.dart';

/// What shows under a row being swiped: the theme colour and an icon.
class OngakuSwipeBackground extends StatelessWidget {
  const OngakuSwipeBackground({
    super.key,
    required this.icon,
    required this.alignment,
    this.borderRadius,
  });

  final IconData icon;
  final Alignment alignment;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: borderRadius,
      ),
      child: Icon(icon, color: colorScheme.onPrimary, size: 26),
    );
  }
}

/// Likes the song (or takes it out of the favourites) and says so.
Future<void> ongakuToggleLike(BuildContext context, Map song) async {
  final id = song['ytid']?.toString() ?? '';
  if (id.isEmpty) return;
  final liked = !isSongAlreadyLiked(id);
  unawaited(HapticFeedback.mediumImpact());
  final l10n = context.l10n!;
  showToast(
    context,
    liked ? l10n.addedToLikedSongs : l10n.removedFromLikedSongs,
    duration: const Duration(seconds: 1),
  );
  await updateSongLikeStatus(id, liked, songData: song);
}

/// Swipe a song to the right to add it to the favourite songs. The row
/// springs back in place: nothing leaves the list.
class OngakuSwipeToLike extends StatelessWidget {
  const OngakuSwipeToLike({
    super.key,
    required this.song,
    required this.child,
    this.borderRadius,
  });

  final Map song;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final id = song['ytid']?.toString() ?? '';
    if (id.isEmpty || song['isLive'] == true) return child;
    return Dismissible(
      key: ValueKey('ongaku-like-$id-${identityHashCode(song)}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3},
      confirmDismiss: (_) async {
        await ongakuToggleLike(context, song);
        return false;
      },
      background: OngakuSwipeBackground(
        icon: isSongAlreadyLiked(id)
            ? Icons.star_border_rounded
            : Icons.star_rounded,
        alignment: Alignment.centerLeft,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}
