/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

/// Themes the home page groups Musify's playlists by, like Apple Music's
/// "moods", "hip-hop" or "party" shelves.
enum PlaylistTheme { moods, charts, hipHop, party, rock, world, other }

/// Title keywords for each theme, checked in this order: a playlist goes to
/// the first theme that matches.
const _keywords = <PlaylistTheme, List<String>>{
  PlaylistTheme.world: [
    'kpop',
    'opm',
    'pinoy',
    'mexican',
    'mexicano',
    'regional',
    'reggaeton',
    'canciones',
    'cancion',
    'canzoni',
    'french',
    'polskie',
    'reggae',
    'disney',
    'christmas',
    'celtic',
    'country',
  ],
  PlaylistTheme.hipHop: ['rap', 'trap', 'phonk', 'r&b'],
  PlaylistTheme.rock: ['rock', 'punk', 'indie', 'classical', 'alt'],
  PlaylistTheme.moods: [
    'goosebumps',
    'sad',
    'emotional',
    'confidence',
    'dopamine',
    'chill',
    'levitate',
    'heart',
    'situationship',
    'work',
    'mint',
    'lounge',
    'spooning',
    'love',
    'wedding',
    'slow',
    'lofi',
    'woods',
    'travel',
  ],
  PlaylistTheme.party: [
    'dance',
    'party',
    'house',
    'remix',
    'upbeat',
    'cardio',
    'car',
    'sing',
    'sped up',
    'ncs',
  ],
  PlaylistTheme.charts: [
    'top',
    'hits',
    'new',
    'certified',
    'fenomen',
    'internet',
    'tiktok',
    'pop',
  ],
};

/// The theme a playlist title belongs to.
PlaylistTheme themeOf(String title) {
  final lower = title.toLowerCase();
  for (final entry in _keywords.entries) {
    if (entry.value.any(lower.contains)) return entry.key;
  }
  return PlaylistTheme.other;
}

/// The playlists of [db] on [theme], in their original order.
List<Map> playlistsForTheme(List<Map> db, PlaylistTheme theme) => [
  for (final playlist in db)
    if (themeOf(playlist['title']?.toString() ?? '') == theme) playlist,
];

/// The artists heard most in [songs] (most recent first), for the
/// "Plus de :" shelves. Local files have no artist page and are skipped.
List<({String id, String name})> topRecentArtists(
  List songs, {
  required int count,
}) {
  final plays = <String, int>{};
  final names = <String, String>{};
  for (final song in songs.whereType<Map>()) {
    final id = song['artistId']?.toString() ?? '';
    if (id.isEmpty || id == 'null' || id.startsWith('local_')) continue;
    plays[id] = (plays[id] ?? 0) + 1;
    names.putIfAbsent(id, () => song['artist']?.toString() ?? '');
  }
  // Ties keep the most recent artist first (map order is insertion order).
  final ids = plays.keys.toList()
    ..sort((a, b) => plays[b]!.compareTo(plays[a]!));
  return [for (final id in ids.take(count)) (id: id, name: names[id]!)];
}
