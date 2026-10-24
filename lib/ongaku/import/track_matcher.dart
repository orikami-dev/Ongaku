/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/import/playlist_sources.dart';
import 'package:musify/services/artist_service.dart' show ytMusicClient;
import 'package:musify/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Result of looking up imported songs on YouTube Music.
class MatchResult {
  const MatchResult(this.found, this.missing, {required this.rateLimited});

  /// Songs in the playlist's order, in Musify's song format.
  final List<Map<String, dynamic>> found;
  final List<ImportedTrack> missing;

  /// YouTube stopped answering: the remaining songs were not searched.
  final bool rateLimited;
}

/// Looks up each song on YouTube Music, the same way as Musify's Spotify
/// import: batches of 12, a short pause between batches, one retry pass for
/// misses, and a stop as soon as YouTube rate-limits the device.
Future<MatchResult> matchTracks(
  List<ImportedTrack> tracks, {
  required void Function(int done, int total) onProgress,
}) async {
  const batchSize = 12;
  const batchPause = Duration(milliseconds: 150);

  final found = <int, Map<String, dynamic>>{};
  var pending = [for (var i = 0; i < tracks.length; i++) i];
  var rateLimited = false;
  var done = 0;
  var total = tracks.length;

  for (var pass = 0; pass < 2 && pending.isNotEmpty && !rateLimited; pass++) {
    if (pass == 1) total += pending.length;
    final missing = <int>[];
    for (var i = 0; i < pending.length; i += batchSize) {
      final batch = pending.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((index) => _find(tracks[index])),
      );
      for (var j = 0; j < batch.length; j++) {
        final (song, limited) = results[j];
        if (limited) rateLimited = true;
        if (song == null) {
          missing.add(batch[j]);
        } else {
          found[batch[j]] = song;
        }
      }
      done += batch.length;
      onProgress(done, total);
      if (rateLimited) {
        missing.addAll(pending.skip(i + batchSize));
        break;
      }
      await Future<void>.delayed(batchPause);
    }
    pending = missing;
  }

  return MatchResult(
    [
      for (var i = 0; i < tracks.length; i++)
        if (found[i] case final song?) song,
    ],
    [for (final i in pending) tracks[i]],
    rateLimited: rateLimited,
  );
}

Future<(Map<String, dynamic>?, bool)> _find(ImportedTrack track) async {
  final query = track.artist.isEmpty
      ? track.title
      : '${track.title} ${track.artist}';
  const attempts = 2;
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      final video = await ytMusicClient.music.searchSong(
        query,
        expectedArtist: track.artist.isEmpty ? null : track.artist,
        expectedTitle: track.title,
      );
      if (video == null) return (null, false);
      return (Map<String, dynamic>.from(returnSongLayout(0, video)), false);
    } on RequestLimitExceededException {
      if (attempt == attempts - 1) return (null, true);
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (e, stackTrace) {
      if (attempt == attempts - 1) {
        logger.log(
          'Ongaku import: no match for "$query"',
          error: e,
          stackTrace: stackTrace,
        );
        return (null, false);
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
  }
  return (null, false);
}
