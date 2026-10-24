// Ongaku: Deezer and Apple Music playlist readers, without the network.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musify/ongaku/import/playlist_sources.dart';

void main() {
  group('Deezer', () {
    test('reads link ids', () {
      expect(
        parseDeezerLink('https://www.deezer.com/fr/playlist/908622995?utm=x'),
        (kind: 'playlist', id: '908622995'),
      );
      expect(parseDeezerLink('deezer.com/album/302127'), (
        kind: 'album',
        id: '302127',
      ));
      expect(parseDeezerLink('https://www.deezer.com/fr/artist/27'), isNull);
    });

    test('reads every page of a playlist', () async {
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url == 'https://api.deezer.com/playlist/42') {
          return http.Response(jsonEncode({'title': 'Mon Mix'}), 200);
        }
        if (url.startsWith('https://api.deezer.com/playlist/42/tracks')) {
          final second = request.url.queryParameters['index'] == '100';
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'title': second ? 'Été' : 'One',
                    'artist': {'name': second ? 'Zaz' : 'Daft Punk'},
                  },
                ],
                if (!second) 'next': 'https://api.deezer.com/playlist/42/tracks?limit=100&index=100',
              }),
            ),
            200,
          );
        }
        return http.Response('', 404);
      });
      final playlist = await fetchDeezerPlaylist(
        'https://www.deezer.com/fr/playlist/42',
        client: client,
      );
      expect(playlist.name, 'Mon Mix');
      expect(playlist.tracks.map((t) => '$t'), [
        'One - Daft Punk',
        'Été - Zaz',
      ]);
    });

    test('follows share links', () async {
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url == 'https://link.deezer.com/s/abc') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://www.deezer.com/fr/playlist/7'},
          );
        }
        if (url == 'https://api.deezer.com/playlist/7') {
          return http.Response(jsonEncode({'title': 'Short'}), 200);
        }
        return http.Response(
          jsonEncode({
            'data': [
              {
                'title': 'Song',
                'artist': {'name': 'Band'},
              },
            ],
          }),
          200,
        );
      });
      final playlist = await fetchDeezerPlaylist(
        'https://link.deezer.com/s/abc',
        client: client,
      );
      expect(playlist.name, 'Short');
      expect(playlist.tracks.single.title, 'Song');
    });

    test('reports a missing playlist', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'type': 'DataException',
              'message': 'no data',
              'code': 800,
            },
          }),
          200,
        ),
      );
      expect(
        fetchDeezerPlaylist(
          'https://www.deezer.com/playlist/1',
          client: client,
        ),
        throwsA(
          isA<PlaylistImportException>().having(
            (e) => e.error,
            'error',
            ImportError.notFound,
          ),
        ),
      );
    });
  });

  group('Apple Music', () {
    test('reads the page data', () {
      final data = [
        {
          'data': {
            'sections': [
              {
                'id': 'playlist-detail-header-section',
                'items': [
                  {
                    'title': 'Chill Mix',
                    'artistName': 'Apple Music',
                    'contentDescriptor': {'kind': 'playlist'},
                  },
                ],
              },
              {
                'id': 'track-list - pl.123',
                'itemKind': 'trackLockup',
                'items': [
                  {
                    'id': 's1',
                    'title': 'Blinding Lights',
                    'artistName': 'The Weeknd',
                    'contentDescriptor': {'kind': 'song'},
                  },
                  {
                    'id': 's2',
                    'title': "L'amour",
                    'artistName': 'Angèle',
                    'contentDescriptor': {'kind': 'song'},
                  },
                ],
              },
              {
                'id': 'more-by-curator',
                'items': [
                  {
                    'id': 's9',
                    'title': 'Other',
                    'artistName': 'Someone',
                    'contentDescriptor': {'kind': 'song'},
                  },
                ],
              },
            ],
          },
        },
      ];
      final page =
          '<html><head><meta property="og:title" '
          'content="Chill Mix by Apple Music on Apple Music"></head><body>'
          '<script type="application/json" id="serialized-server-data">'
          '${jsonEncode(data)}</script></body></html>';
      final playlist = parseAppleMusicPage(page);
      expect(playlist.name, 'Chill Mix');
      expect(playlist.tracks.map((t) => '$t'), [
        'Blinding Lights - The Weeknd',
        "L'amour - Angèle",
      ]);
    });

    test('falls back to schema.org data', () {
      final schema = {
        '@type': 'MusicPlaylist',
        'name': 'Road Trip',
        'track': [
          {
            '@type': 'MusicRecording',
            'name': 'Africa',
            'byArtist': [
              {'@type': 'MusicGroup', 'name': 'Toto'},
            ],
          },
        ],
      };
      final page =
          '<html><head><script type="application/ld+json">'
          '${jsonEncode(schema)}</script></head></html>';
      expect(
        parseAppleMusicPage(page).tracks.single.toString(),
        'Africa - Toto',
      );
    });

    test('rejects other links', () {
      expect(
        isAppleMusicLink('https://music.apple.com/fr/playlist/x/pl.1'),
        isTrue,
      );
      expect(
        fetchAppleMusicPlaylist('https://open.spotify.com/playlist/1'),
        throwsA(isA<PlaylistImportException>()),
      );
    });

    test('reads a Music app text export (UTF-16)', () {
      const text =
          'Nom\tArtiste\tCompositeur\tAlbum\tDurée\r'
          'Hey Jude\tThe Beatles\tLennon\t1\t431\r'
          'Bohemian Rhapsody\tQueen\tMercury\tA Night\t355\r';
      final units = text.codeUnits;
      final bytes = Uint8List(2 + units.length * 2)
        ..[0] = 0xFF
        ..[1] = 0xFE;
      for (var i = 0; i < units.length; i++) {
        bytes[2 + i * 2] = units[i] & 0xFF;
        bytes[3 + i * 2] = units[i] >> 8;
      }
      final playlist = parsePlaylistFile(bytes, fileName: 'Rock.txt');
      expect(playlist.name, 'Rock');
      expect(playlist.tracks.map((t) => '$t'), [
        'Hey Jude - The Beatles',
        'Bohemian Rhapsody - Queen',
      ]);
    });

    test('reads a CSV export', () {
      final bytes = Uint8List.fromList(
        utf8.encode('Track name,Artist name,Album\n"Hello, World",Adele,25\n'),
      );
      expect(
        parsePlaylistFile(bytes).tracks.single.toString(),
        'Hello, World - Adele',
      );
    });

    test('rejects a file without songs', () {
      expect(
        () => parsePlaylistFile(Uint8List.fromList(utf8.encode('a,b\n1,2\n'))),
        throwsA(isA<PlaylistImportException>()),
      );
    });
  });
}
