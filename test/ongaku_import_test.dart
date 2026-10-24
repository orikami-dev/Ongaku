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

  group('covers and long playlists', () {
    test('Deezer cover', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/playlist/5') {
          return http.Response(
            jsonEncode({'title': 'Mix', 'picture_xl': 'https://cdn/x.jpg'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': [
              {
                'title': 'A',
                'artist': {'name': 'B'},
              },
            ],
          }),
          200,
        );
      });
      final playlist = await fetchDeezerPlaylist(
        'https://www.deezer.com/playlist/5',
        client: client,
      );
      expect(playlist.image, 'https://cdn/x.jpg');
    });

    test('Apple Music reads every song through the web API', () async {
      const token = 'eyJhbGciOi.eyJpc3MiOi.c2lnbmF0dXJl';
      final page =
          '<html><head><meta property="og:title" content="Big - Playlist - '
          'Apple Music"><meta property="og:image" content="https://is1-ssl.'
          'mzstatic.com/image/thumb/a/b/1200x630wp-60.jpg">'
          '<script type="module" src="/assets/index~abc.js"></script></head>'
          '<body><script id="serialized-server-data">'
          '${jsonEncode([
            {
              'items': [
                {
                  'id': '1',
                  'title': 'First',
                  'artistName': 'X',
                  'contentDescriptor': {'kind': 'song'},
                },
              ],
              'id': 'track-list',
            },
          ])}</script></body></html>';
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.startsWith('https://music.apple.com/fr/playlist')) {
          return http.Response.bytes(utf8.encode(page), 200);
        }
        if (url == 'https://music.apple.com/assets/index~abc.js') {
          return http.Response('var t="$token";', 200);
        }
        expect(request.headers['Authorization'], 'Bearer $token');
        if (url.endsWith('/playlists/pl.u-1')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'attributes': {
                    'name': 'Big',
                    'artwork': {'url': 'https://is1/{w}x{h}bb.jpg'},
                  },
                },
              ],
            }),
            200,
          );
        }
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        return http.Response(
          jsonEncode({
            'data': [
              for (var i = 0; i < 100; i++)
                {
                  'attributes': {
                    'name': 'Song ${offset + i}',
                    'artistName': 'Artist',
                  },
                },
            ],
            if (offset < 200)
              'next':
                  '/v1/catalog/fr/playlists/pl.u-1/tracks?offset=${offset + 100}',
          }),
          200,
        );
      });
      final playlist = await fetchAppleMusicPlaylist(
        'https://music.apple.com/fr/playlist/big/pl.u-1',
        client: client,
      );
      expect(playlist.tracks.length, 300);
      expect(playlist.name, 'Big');
      expect(playlist.image, 'https://is1/600x600bb.jpg');
    });

    test('Apple Music keeps the page songs when the API fails', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'music.apple.com' &&
            request.url.path.contains('playlist')) {
          return http.Response.bytes(
            utf8.encode(
              '<html><head><meta property="og:image" content="https://is1-ssl'
              '.mzstatic.com/a/1200x630wp.jpg"></head><body><script id='
              '"serialized-server-data">[{"id":"track-list","items":[{"id":'
              '"1","title":"Only","artistName":"Y","contentDescriptor":'
              '{"kind":"song"}}]}]</script></body></html>',
            ),
            200,
          );
        }
        return http.Response('', 500);
      });
      final playlist = await fetchAppleMusicPlaylist(
        'https://music.apple.com/us/playlist/x/pl.2',
        client: client,
      );
      expect(playlist.tracks.single.title, 'Only');
      expect(playlist.image, 'https://is1-ssl.mzstatic.com/a/600x600bb.jpg');
    });

    test(
      'Spotify: name and cover from oEmbed, all songs from the API',
      () async {
        final next = {
          'props': {
            'pageProps': {
              'state': {
                'settings': {
                  'session': {'accessToken': 'tok'},
                },
                'data': {
                  'entity': {
                    'name': 'Embed name',
                    'trackList': [
                      {'title': 'One', 'subtitle': 'Band'},
                    ],
                  },
                },
              },
            },
          },
        };
        final client = MockClient((request) async {
          final url = request.url;
          if (url.path == '/oembed') {
            return http.Response(
              jsonEncode({
                'title': 'Road Trip',
                'thumbnail_url': 'https://i.scdn.co/image/abc',
              }),
              200,
            );
          }
          if (url.path.startsWith('/embed/')) {
            return http.Response.bytes(
              utf8.encode(
                '<html><script id="__NEXT_DATA__" type="application/json">'
                '${jsonEncode(next)}</script></html>',
              ),
              200,
            );
          }
          expect(request.headers['Authorization'], 'Bearer tok');
          final offset = int.parse(url.queryParameters['offset'] ?? '0');
          return http.Response(
            jsonEncode({
              'items': [
                for (var i = 0; i < 100; i++)
                  {
                    'track': {
                      'name': 'Song ${offset + i}',
                      'artists': [
                        {'name': 'A'},
                        {'name': 'B'},
                      ],
                    },
                  },
              ],
              'next': offset == 0
                  ? 'https://api.spotify.com/v1/playlists/37i/tracks?offset=100'
                  : null,
            }),
            200,
          );
        });
        final playlist = await fetchSpotifyPlaylist(
          'https://open.spotify.com/intl-fr/playlist/37i?si=abc',
          client: client,
        );
        expect(playlist.name, 'Road Trip');
        expect(playlist.image, 'https://i.scdn.co/image/abc');
        expect(playlist.tracks.length, 200);
        expect(playlist.tracks.first.artist, 'A, B');
      },
    );

    test('Spotify falls back to the embed list', () async {
      final client = MockClient((request) async {
        if (request.url.path.startsWith('/embed/')) {
          return http.Response.bytes(
            utf8.encode(
              '<script id="__NEXT_DATA__">{"entity":{"name":"E","trackList":'
              '[{"title":"T","subtitle":"S"}],"coverArt":{"sources":[{"url":'
              '"small","width":64},{"url":"big","width":640}]}}}</script>',
            ),
            200,
          );
        }
        return http.Response('', 401);
      });
      final playlist = await fetchSpotifyPlaylist(
        'spotify:album:xyz',
        client: client,
      );
      expect(playlist.name, 'E');
      expect(playlist.image, 'big');
      expect(playlist.tracks.single.toString(), 'T - S');
    });
  });
}
