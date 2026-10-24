import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/screens/ongaku_all_songs_page.dart';

void main() {
  test('library songs are merged once and filed A to Z, # last', () {
    final songs = librarySongs(
      liked: [
        {'ytid': 'a', 'title': 'Été indien', 'artist': 'X'},
        {'ytid': 'b', 'title': 'beat', 'artist': 'Y'},
      ],
      offline: [
        {'ytid': 'a', 'title': 'Été indien', 'artist': 'X'},
      ],
      playlists: [
        {
          'list': [
            {'ytid': 'c', 'title': '99 Luftballons', 'artist': 'Z'},
            {'ytid': 'd', 'title': '"Alors on danse"', 'artist': 'W'},
          ],
        },
      ],
      local: [
        {'ytid': 'local:1', 'title': '夜に駆ける', 'artist': 'V'},
      ],
    );
    expect(songs.map((s) => s['ytid']), ['d', 'b', 'a', 'c', 'local:1']);
    expect(songs.map((s) => indexLetter(s['title'])), [
      'A',
      'B',
      'E',
      '#',
      '#',
    ]);
  });
}
