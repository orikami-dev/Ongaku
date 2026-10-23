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
import 'package:flutter/foundation.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';

/// Lock screen / notification player: favourite, previous, play, next and
/// shuffle, like the Samsung media widget. The three middle buttons stay
/// in the collapsed notification.
const ongakuCompactActionIndices = [1, 2, 3];

const _starAction = 'ongakuStar';
const _shuffleAction = 'ongakuShuffle';

bool _isLiked(Map? song) {
  final id = song?['ytid']?.toString();
  if (id == null) return false;
  return song?['isLive'] == true
      ? isRadioStationLiked(id)
      : isSongAlreadyLiked(id);
}

/// Replaces upstream's button list. [hasMultipleTracks] keeps upstream's
/// rewind / fast-forward fallback for single songs. [currentSong] comes
/// from the handler itself: the global `audioHandler` is not assigned yet
/// while the handler is being constructed.
List<MediaControl> ongakuControls({
  required bool playing,
  required bool hasMultipleTracks,
  Map? currentSong,
}) {
  final liked = _isLiked(currentSong);
  final shuffled = shuffleNotifier.value;
  return [
    MediaControl.custom(
      androidIcon: liked
          ? 'drawable/ic_ongaku_star'
          : 'drawable/ic_ongaku_star_outline',
      label: 'Favourite',
      name: _starAction,
    ),
    if (hasMultipleTracks) MediaControl.skipToPrevious else MediaControl.rewind,
    if (playing) MediaControl.pause else MediaControl.play,
    if (hasMultipleTracks)
      MediaControl.skipToNext
    else
      MediaControl.fastForward,
    MediaControl.custom(
      androidIcon: shuffled
          ? 'drawable/ic_ongaku_shuffle'
          : 'drawable/ic_ongaku_shuffle_off',
      label: 'Shuffle',
      name: _shuffleAction,
    ),
  ];
}

/// Handles the two custom buttons. Returns false for any other action.
Future<bool> ongakuCustomAction(String name) async {
  switch (name) {
    case _starAction:
      final song = audioHandler.currentSong;
      final id = song?['ytid']?.toString();
      if (song == null || id == null) return true;
      if (song['isLive'] == true) {
        await (isRadioStationLiked(id)
            ? removeRadioStationFromLiked(id)
            : addRadioStationToLiked(id));
      } else {
        await updateSongLikeStatus(
          id,
          !isSongAlreadyLiked(id),
          songData: Map<String, dynamic>.from(song),
        );
      }
      return true;
    case _shuffleAction:
      await audioHandler.setShuffleMode(
        shuffleNotifier.value
            ? AudioServiceShuffleMode.none
            : AudioServiceShuffleMode.all,
      );
      return true;
  }
  return false;
}

/// Redraws the buttons when the favourite or shuffle state changes, since
/// upstream only republishes the playback state when playback changes.
void ongakuWatchNotificationState() {
  void refresh() {
    final state = audioHandler.playbackState.valueOrNull;
    if (state == null || audioHandler.mediaItem.valueOrNull == null) return;
    audioHandler.playbackState.add(
      state.copyWith(
        controls: ongakuControls(
          playing: state.playing,
          hasMultipleTracks: (audioHandler.queue.valueOrNull?.length ?? 0) > 1,
          currentSong: audioHandler.currentSong,
        ),
      ),
    );
  }

  Listenable.merge([
    userLikedSongsList,
    userLikedRadioStations,
    shuffleNotifier,
  ]).addListener(refresh);
  audioHandler.mediaItem.listen((_) => refresh());
}
