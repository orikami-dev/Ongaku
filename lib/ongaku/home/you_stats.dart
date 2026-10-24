/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

/// An artist of a month's listening, with the song that represents them.
class ArtistListening {
  const ArtistListening(this.name, this.seconds, this.plays, this.song);

  final String name;
  final int seconds;
  final int plays;

  /// Their most played song, for the artwork.
  final Map<String, dynamic> song;
}

/// What the "Vous" page shows for one month, read from Musify's listening
/// stats (`songs` sorted by Musify, most listened first).
class MonthListening {
  MonthListening(this.minutes, this.songs)
    : plays = songs.fold(0, (sum, s) => sum + _int(s['playCount'])),
      artists = _artists(songs);

  final int minutes;
  final List<Map<String, dynamic>> songs;
  final int plays;
  final List<ArtistListening> artists;

  bool get isEmpty => minutes == 0 && songs.isEmpty;

  static List<ArtistListening> _artists(List<Map<String, dynamic>> songs) {
    final seconds = <String, int>{};
    final plays = <String, int>{};
    final first = <String, Map<String, dynamic>>{};
    for (final song in songs) {
      final name = song['artist']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      seconds[name] = (seconds[name] ?? 0) + _int(song['seconds']);
      plays[name] = (plays[name] ?? 0) + _int(song['playCount']);
      first.putIfAbsent(name, () => song);
    }
    return [
      for (final name in seconds.keys)
        ArtistListening(name, seconds[name]!, plays[name]!, first[name]!),
    ]..sort((a, b) {
      final bySeconds = b.seconds.compareTo(a.seconds);
      return bySeconds != 0 ? bySeconds : b.plays.compareTo(a.plays);
    });
  }
}

int _int(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
