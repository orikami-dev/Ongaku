/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' show Document;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

/// A song read from another service, before it is looked up on YouTube.
class ImportedTrack {
  const ImportedTrack(this.title, this.artist);

  final String title;
  final String artist;

  @override
  String toString() => '$title - $artist';
}

/// A playlist read from another service.
class ImportedPlaylist {
  const ImportedPlaylist(this.name, this.tracks, {this.image});

  final String? name;
  final List<ImportedTrack> tracks;

  /// The cover's URL, when the service shows one.
  final String? image;

  ImportedPlaylist withTracks(List<ImportedTrack> other) =>
      ImportedPlaylist(name, other, image: image);
}

/// Why a playlist could not be read. The page shows a message for each.
enum ImportError { invalidLink, notFound, privateOrEmpty, network, badFile }

class PlaylistImportException implements Exception {
  const PlaylistImportException(this.error, [this.detail]);

  final ImportError error;
  final Object? detail;

  @override
  String toString() => 'PlaylistImportException($error, $detail)';
}

const _userAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

// ---------------------------------------------------------------------------
// Deezer: public API, no account needed for public playlists and albums.
// ---------------------------------------------------------------------------

/// Kind and id of a Deezer link, such as
/// `https://www.deezer.com/fr/playlist/908622995` or `deezer.com/album/302127`.
({String kind, String id})? parseDeezerLink(String link) {
  final match = RegExp(
    r'deezer\.com/(?:[a-z]{2}(?:-[a-z]{2})?/)?(playlist|album)/(\d+)',
    caseSensitive: false,
  ).firstMatch(link);
  if (match == null) return null;
  return (kind: match.group(1)!.toLowerCase(), id: match.group(2)!);
}

/// Whether [link] is a Deezer share link that redirects to the real page
/// (`link.deezer.com/s/...`, `deezer.page.link/...`).
bool isDeezerShortLink(String link) => RegExp(
  r'(link\.deezer\.com|deezer\.page\.link|dzr\.page\.link)/',
  caseSensitive: false,
).hasMatch(link);

/// Reads a public Deezer playlist or album from its link.
Future<ImportedPlaylist> fetchDeezerPlaylist(
  String link, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    var target = link.trim();
    if (parseDeezerLink(target) == null && isDeezerShortLink(target)) {
      target = await _resolveRedirects(c, target);
    }
    final parsed = parseDeezerLink(target);
    if (parsed == null) {
      throw const PlaylistImportException(ImportError.invalidLink);
    }

    final info = await _getJson(
      c,
      Uri.parse('https://api.deezer.com/${parsed.kind}/${parsed.id}'),
    );
    final name = info['title'] as String?;
    final image = (info['picture_xl'] ?? info['cover_xl']) as String?;

    final tracks = <ImportedTrack>[];
    Uri? page = Uri.parse(
      'https://api.deezer.com/${parsed.kind}/${parsed.id}/tracks?limit=100',
    );
    // A safety cap: Deezer playlists hold at most 10,000 songs.
    for (var pages = 0; page != null && pages < 120; pages++) {
      final json = await _getJson(c, page);
      for (final item in (json['data'] as List? ?? const [])) {
        if (item is! Map) continue;
        final title = (item['title'] as String?)?.trim() ?? '';
        final artist = ((item['artist'] as Map?)?['name'] as String?)?.trim();
        if (title.isNotEmpty) tracks.add(ImportedTrack(title, artist ?? ''));
      }
      final next = json['next'];
      page = next is String && next.isNotEmpty ? Uri.parse(next) : null;
    }
    if (tracks.isEmpty) {
      throw const PlaylistImportException(ImportError.privateOrEmpty);
    }
    return ImportedPlaylist(name, tracks, image: image);
  } finally {
    if (client == null) c.close();
  }
}

Future<Map<String, dynamic>> _getJson(
  http.Client c,
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  final http.Response response;
  try {
    response = await c.get(
      uri,
      headers: {'User-Agent': _userAgent, ...headers},
    );
  } catch (e) {
    throw PlaylistImportException(ImportError.network, e);
  }
  if (response.statusCode != 200) {
    throw PlaylistImportException(ImportError.network, response.statusCode);
  }
  final json = jsonDecode(utf8.decode(response.bodyBytes));
  if (json is! Map<String, dynamic>) {
    throw const PlaylistImportException(ImportError.notFound);
  }
  final error = json['error'];
  if (error is Map) {
    // Deezer answers 200 with an error object: 800 = no data, 4 = quota.
    final code = error['code'];
    throw PlaylistImportException(
      code == 4 ? ImportError.network : ImportError.notFound,
      error['message'],
    );
  }
  return json;
}

/// Follows HTTP redirects by hand and returns the final URL, so that the
/// share link's target is known even when it is not a JSON API.
Future<String> _resolveRedirects(http.Client c, String link) async {
  var current = Uri.parse(link.startsWith('http') ? link : 'https://$link');
  for (var hop = 0; hop < 6; hop++) {
    final request = http.Request('GET', current)
      ..followRedirects = false
      ..headers['User-Agent'] = _userAgent;
    final http.StreamedResponse response;
    try {
      response = await c.send(request);
    } catch (e) {
      throw PlaylistImportException(ImportError.network, e);
    }
    final location = response.headers['location'];
    if (response.isRedirect ||
        (location != null && response.statusCode < 400)) {
      await response.stream.drain<void>();
      if (location == null) break;
      current = current.resolve(location);
      if (parseDeezerLink(current.toString()) != null) break;
      continue;
    }
    // Some share pages redirect in HTML instead of with a header.
    final body = await response.stream.bytesToString();
    final inPage = RegExp(
      r'https?://(?:www\.)?deezer\.com/[^"'
      "'"
      r'\s<>]*(?:playlist|album)/\d+',
    ).firstMatch(body);
    if (inPage != null) return inPage.group(0)!;
    break;
  }
  return current.toString();
}

// ---------------------------------------------------------------------------
// Apple Music: no public API without a paid developer key. Two ways in:
// the public web page of a shared playlist, or a file exported from the
// Music app (Mac) or iTunes (Windows).
// ---------------------------------------------------------------------------

bool isAppleMusicLink(String link) => RegExp(
  r'(music|itunes)\.apple\.com/.*/(playlist|album)/',
  caseSensitive: false,
).hasMatch(link);

/// Reads a public Apple Music playlist or album from its link.
Future<ImportedPlaylist> fetchAppleMusicPlaylist(
  String link, {
  http.Client? client,
}) async {
  final trimmed = link.trim();
  if (!isAppleMusicLink(trimmed)) {
    throw const PlaylistImportException(ImportError.invalidLink);
  }
  final c = client ?? http.Client();
  try {
    final http.Response response;
    try {
      response = await c.get(
        Uri.parse(trimmed.replaceFirst('itunes.apple.com', 'music.apple.com')),
        headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'},
      );
    } catch (e) {
      throw PlaylistImportException(ImportError.network, e);
    }
    if (response.statusCode == 404) {
      throw const PlaylistImportException(ImportError.notFound);
    }
    if (response.statusCode != 200) {
      throw PlaylistImportException(ImportError.network, response.statusCode);
    }
    final page = utf8.decode(response.bodyBytes);
    var playlist = parseAppleMusicPage(page);
    // The page only carries the first songs of a long playlist. The rest
    // comes from the API the Apple Music website itself uses.
    try {
      final full = await _appleApiPlaylist(c, trimmed, page);
      if (full != null && full.tracks.length >= playlist.tracks.length) {
        playlist = ImportedPlaylist(
          full.name ?? playlist.name,
          full.tracks,
          image: full.image ?? playlist.image,
        );
      }
    } on Object catch (_) {
      // Keep what the page gave.
    }
    if (playlist.tracks.isEmpty) {
      throw const PlaylistImportException(ImportError.privateOrEmpty);
    }
    return playlist;
  } finally {
    if (client == null) c.close();
  }
}

/// Extracts the songs of an Apple Music web page. Reads the page's own data
/// (`serialized-server-data`), then the schema.org description as a fallback.
ImportedPlaylist parseAppleMusicPage(String page) {
  final document = html.parse(page);
  final name = _appleName(document);
  final image = _appleImage(document);

  final serialized = document.getElementById('serialized-server-data')?.text;
  if (serialized != null && serialized.trim().isNotEmpty) {
    try {
      final data = jsonDecode(serialized);
      // The song list is its own section ("track-list"); other sections
      // (more by the curator, similar playlists) are left out when found.
      final sections = <Object?>[];
      _findTrackSections(data, sections);
      final tracks = <ImportedTrack>[];
      final seen = <String>{};
      _collectAppleSongs(sections.isEmpty ? data : sections, tracks, seen);
      if (tracks.isNotEmpty) {
        return ImportedPlaylist(name, tracks, image: image);
      }
    } on FormatException {
      // Fall through to the schema.org data.
    }
  }

  for (final script in document.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    try {
      final tracks = _schemaTracks(jsonDecode(script.text));
      if (tracks.isNotEmpty) {
        return ImportedPlaylist(name, tracks, image: image);
      }
    } on FormatException {
      continue;
    }
  }
  return ImportedPlaylist(name, const [], image: image);
}

/// The page's share picture, asked for as a 600 px square cover.
String? _appleImage(Document document) {
  final og = document
      .querySelector('meta[property="og:image"]')
      ?.attributes['content']
      ?.trim();
  if (og == null || og.isEmpty) return null;
  return appleArtwork(og);
}

/// Apple's artwork URLs end with the size, such as `1200x630wp-60.jpg` or the
/// template `{w}x{h}bb.jpg`: ask for a 600 px square.
String appleArtwork(String url) {
  if (url.contains('{w}')) {
    return url
        .replaceAll('{w}', '600')
        .replaceAll('{h}', '600')
        .replaceAll('{c}', 'bb')
        .replaceAll('{f}', 'jpg');
  }
  if (!url.contains('mzstatic.com')) return url;
  return url.replaceFirst(RegExp(r'/[^/]+$'), '/600x600bb.jpg');
}

/// Storefront, kind and id of an Apple Music link, such as
/// `https://music.apple.com/fr/playlist/chill/pl.u-abc` (kind `playlists`).
({String storefront, String kind, String id})? parseAppleMusicLink(
  String link,
) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final kindIndex = segments.indexWhere((s) => s == 'playlist' || s == 'album');
  if (kindIndex < 1 || kindIndex == segments.length - 1) return null;
  return (
    storefront: segments[kindIndex - 1],
    kind: '${segments[kindIndex]}s',
    id: segments.last,
  );
}

/// Reads the whole playlist through amp-api.music.apple.com, with the
/// public token the Apple Music website embeds in its script.
Future<ImportedPlaylist?> _appleApiPlaylist(
  http.Client c,
  String link,
  String page,
) async {
  final parsed = parseAppleMusicLink(link);
  if (parsed == null) return null;
  final token = await _appleToken(c, page);
  if (token == null) return null;
  final headers = {
    'Authorization': 'Bearer $token',
    'Origin': 'https://music.apple.com',
    'Referer': 'https://music.apple.com/',
  };
  const host = 'https://amp-api.music.apple.com';
  final base = '/v1/catalog/${parsed.storefront}/${parsed.kind}/${parsed.id}';

  final info = await _getJson(c, Uri.parse('$host$base'), headers: headers);
  final data = info['data'];
  final attributes = data is List && data.isNotEmpty && data.first is Map
      ? (data.first as Map)['attributes'] as Map?
      : null;
  final artwork = (attributes?['artwork'] as Map?)?['url'] as String?;

  final tracks = <ImportedTrack>[];
  String? next = '$base/tracks?limit=100';
  // A safety cap at 30,000 songs.
  for (var pages = 0; next != null && pages < 300; pages++) {
    final json = await _getJson(c, Uri.parse('$host$next'), headers: headers);
    for (final item in (json['data'] as List? ?? const [])) {
      final a = item is Map ? item['attributes'] : null;
      if (a is! Map) continue;
      final title = (a['name'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;
      tracks.add(ImportedTrack(title, (a['artistName'] as String?) ?? ''));
    }
    final n = json['next'];
    next = n is String && n.isNotEmpty ? n : null;
  }
  return ImportedPlaylist(
    attributes?['name'] as String?,
    tracks,
    image: artwork == null ? null : appleArtwork(artwork),
  );
}

Future<String?> _appleToken(http.Client c, String page) async {
  final scripts = RegExp(r'src="(/assets/index[~-][^"]+\.js)"')
      .allMatches(page)
      .map((m) => m.group(1)!);
  for (final src in scripts) {
    final response = await c.get(
      Uri.parse('https://music.apple.com$src'),
      headers: {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) continue;
    final token = _jwt.firstMatch(response.body)?.group(0);
    if (token != null) return token;
  }
  return null;
}

final _jwt = RegExp(r'eyJh[\w-]+\.[\w-]+\.[\w-]+');

String? _appleName(Document document) {
  final og = document
      .querySelector('meta[property="og:title"]')
      ?.attributes['content']
      ?.trim();
  if (og == null || og.isEmpty) return null;
  // "Name by Curator on Apple Music" / "Name - Playlist - Apple Music".
  return og
      .replaceFirst(RegExp(r'\s+on Apple Music$'), '')
      .replaceFirst(RegExp(r'\s+-\s+(Playlist|Album)\s+-\s+Apple Music$'), '')
      .replaceFirst(RegExp(r'\s+-\s+Apple Music$'), '')
      .replaceFirst(RegExp(r'\s+by\s+[^,]+$'), '')
      .trim();
}

void _findTrackSections(Object? node, List<Object?> out) {
  if (node is List) {
    for (final child in node) {
      _findTrackSections(child, out);
    }
  } else if (node is Map) {
    final id = node['id'];
    final kind = node['itemKind'];
    if (node['items'] is List &&
        ((id is String && id.startsWith('track-list')) ||
            kind == 'trackLockup' ||
            kind == 'songs')) {
      out.add(node['items']);
      return;
    }
    for (final value in node.values) {
      _findTrackSections(value, out);
    }
  }
}

/// Walks the page data and keeps every item that describes a song.
void _collectAppleSongs(
  Object? node,
  List<ImportedTrack> out,
  Set<String> seen,
) {
  if (node is List) {
    for (final child in node) {
      _collectAppleSongs(child, out, seen);
    }
    return;
  }
  if (node is! Map) return;

  final title = node['title'];
  final artist = node['artistName'];
  if (title is String && artist is String && _isAppleSong(node)) {
    final id = node['id']?.toString() ?? '$title|$artist';
    if (seen.add(id)) out.add(ImportedTrack(title.trim(), artist.trim()));
    return;
  }
  for (final value in node.values) {
    _collectAppleSongs(value, out, seen);
  }
}

bool _isAppleSong(Map node) {
  final descriptor = node['contentDescriptor'];
  if (descriptor is Map) {
    final kind = descriptor['kind'];
    return kind == 'song' || kind == 'musicVideo';
  }
  final type = node['type'] ?? node['kind'];
  if (type is String) return type == 'songs' || type == 'song';
  return node['duration'] is num;
}

List<ImportedTrack> _schemaTracks(Object? json) {
  final tracks = <ImportedTrack>[];
  void visit(Object? node) {
    if (node is List) {
      node.forEach(visit);
    } else if (node is Map) {
      if (node['@type'] == 'MusicRecording' && node['name'] is String) {
        final by = node['byArtist'];
        final artist = by is Map
            ? by['name']
            : by is List && by.isNotEmpty && by.first is Map
            ? (by.first as Map)['name']
            : null;
        tracks.add(
          ImportedTrack((node['name'] as String).trim(), '${artist ?? ''}'),
        );
        return;
      }
      node.values.forEach(visit);
    }
  }

  visit(json);
  return tracks;
}

// ---------------------------------------------------------------------------
// Spotify: name and cover from the public oEmbed endpoint, songs from the
// embed player's page (with its anonymous token for long playlists). A CSV
// export stays available for the full list when Spotify refuses.
// ---------------------------------------------------------------------------

/// Kind and id of a Spotify link, such as
/// `https://open.spotify.com/intl-fr/playlist/37i9dQZF1DXcBWIGoYBM5M?si=x`.
({String kind, String id})? parseSpotifyLink(String link) {
  final match = RegExp(
    r'open\.spotify\.com/(?:intl-[a-z-]+/)?(?:embed/)?(playlist|album)/([A-Za-z0-9]+)',
    caseSensitive: false,
  ).firstMatch(link);
  if (match != null) {
    return (kind: match.group(1)!.toLowerCase(), id: match.group(2)!);
  }
  final uri = RegExp('spotify:(playlist|album):([A-Za-z0-9]+)')
      .firstMatch(link);
  if (uri == null) return null;
  return (kind: uri.group(1)!, id: uri.group(2)!);
}

/// Reads a public Spotify playlist or album from its link.
Future<ImportedPlaylist> fetchSpotifyPlaylist(
  String link, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    var target = link.trim();
    if (parseSpotifyLink(target) == null &&
        RegExp(r'spotify\.link/|spotify\.app\.link/').hasMatch(target)) {
      target = await _resolveRedirects(c, target);
    }
    final parsed = parseSpotifyLink(target);
    if (parsed == null) {
      throw const PlaylistImportException(ImportError.invalidLink);
    }
    final canonical = 'https://open.spotify.com/${parsed.kind}/${parsed.id}';

    String? name;
    String? image;
    try {
      final oembed = await _getJson(
        c,
        Uri.parse('https://open.spotify.com/oembed?url=$canonical'),
      );
      name = oembed['title'] as String?;
      image = oembed['thumbnail_url'] as String?;
    } on PlaylistImportException {
      // The embed page below also has them.
    }

    final http.Response embed;
    try {
      embed = await c.get(
        Uri.parse('https://open.spotify.com/embed/${parsed.kind}/${parsed.id}'),
        headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'},
      );
    } catch (e) {
      throw PlaylistImportException(ImportError.network, e);
    }
    if (embed.statusCode == 404) {
      throw const PlaylistImportException(ImportError.notFound);
    }
    if (embed.statusCode != 200) {
      throw PlaylistImportException(ImportError.network, embed.statusCode);
    }
    final fromPage = parseSpotifyEmbedPage(utf8.decode(embed.bodyBytes));
    var tracks = fromPage.playlist.tracks;

    final token = fromPage.token;
    if (token != null) {
      try {
        final all = await _spotifyApiTracks(c, parsed.kind, parsed.id, token);
        if (all.length > tracks.length) tracks = all;
      } on Object catch (_) {
        // Keep the embed page's songs.
      }
    }
    if (tracks.isEmpty) {
      throw const PlaylistImportException(ImportError.privateOrEmpty);
    }
    return ImportedPlaylist(
      name ?? fromPage.playlist.name,
      tracks,
      image: image ?? fromPage.playlist.image,
    );
  } finally {
    if (client == null) c.close();
  }
}

/// Songs, name, cover and anonymous token of Spotify's embed player page.
({ImportedPlaylist playlist, String? token}) parseSpotifyEmbedPage(
  String page,
) {
  final script = html.parse(page).getElementById('__NEXT_DATA__')?.text;
  if (script == null) {
    return (playlist: const ImportedPlaylist(null, []), token: null);
  }
  final Object? data;
  try {
    data = jsonDecode(script);
  } on FormatException {
    return (playlist: const ImportedPlaylist(null, []), token: null);
  }

  String? token;
  Map? entity;
  void visit(Object? node) {
    if (node is List) {
      node.forEach(visit);
    } else if (node is Map) {
      if (token == null && node['accessToken'] is String) {
        token = node['accessToken'] as String;
      }
      if (entity == null && node['trackList'] is List) entity = node;
      node.values.forEach(visit);
    }
  }

  visit(data);
  final tracks = <ImportedTrack>[];
  for (final item in (entity?['trackList'] as List? ?? const [])) {
    if (item is! Map) continue;
    final title = (item['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) continue;
    tracks.add(
      ImportedTrack(title, (item['subtitle'] as String?)?.trim() ?? ''),
    );
  }
  String? image;
  final cover = entity?['coverArt'];
  if (cover is Map && cover['sources'] is List) {
    final sources = (cover['sources'] as List).whereType<Map>().toList()
      ..sort(
        (a, b) =>
            ((b['width'] ?? 0) as num).compareTo((a['width'] ?? 0) as num),
      );
    if (sources.isNotEmpty) image = sources.first['url'] as String?;
  }
  final name = (entity?['name'] ?? entity?['title']) as String?;
  return (playlist: ImportedPlaylist(name, tracks, image: image), token: token);
}

Future<List<ImportedTrack>> _spotifyApiTracks(
  http.Client c,
  String kind,
  String id,
  String token,
) async {
  final headers = {'Authorization': 'Bearer $token'};
  final tracks = <ImportedTrack>[];
  String? next = 'https://api.spotify.com/v1/${kind}s/$id/tracks?limit=100';
  for (var pages = 0; next != null && pages < 120; pages++) {
    final json = await _getJson(c, Uri.parse(next), headers: headers);
    for (final item in (json['items'] as List? ?? const [])) {
      if (item is! Map) continue;
      // Playlists wrap each song in {track: ...}; albums list songs directly.
      final track = item['track'] is Map ? item['track'] as Map : item;
      final title = (track['name'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;
      final artists = (track['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => a['name'])
          .whereType<String>()
          .join(', ');
      tracks.add(ImportedTrack(title, artists));
    }
    final n = json['next'];
    next = n is String && n.isNotEmpty ? n : null;
  }
  return tracks;
}

/// Reads a playlist exported from the Music app or iTunes
/// (File > Library > Export Playlist, "Text" format: UTF-16, one song per
/// line, tab-separated), or a CSV file with title and artist columns.
ImportedPlaylist parsePlaylistFile(Uint8List bytes, {String? fileName}) {
  final text = decodeText(bytes);
  final lines = text
      .split(RegExp(r'\r\n|\r|\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) {
    throw const PlaylistImportException(ImportError.badFile);
  }

  final separator = lines.first.contains('\t')
      ? '\t'
      : lines.first.contains(';') && !lines.first.contains(',')
      ? ';'
      : ',';
  final rows = [for (final line in lines) _splitRow(line, separator)];
  final headers = [
    for (final h in rows.first) h.replaceFirst('﻿', '').trim().toLowerCase(),
  ];

  final titleIndex = _column(headers, _titleHeaders);
  final artistIndex = _column(headers, _artistHeaders);
  if (titleIndex == -1) {
    throw const PlaylistImportException(ImportError.badFile);
  }

  final tracks = <ImportedTrack>[];
  for (final row in rows.skip(1)) {
    if (row.length <= titleIndex) continue;
    final title = row[titleIndex].trim();
    if (title.isEmpty) continue;
    final artist = artistIndex != -1 && row.length > artistIndex
        ? row[artistIndex].trim()
        : '';
    tracks.add(ImportedTrack(title, artist));
  }
  if (tracks.isEmpty) throw const PlaylistImportException(ImportError.badFile);

  final base = fileName?.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  return ImportedPlaylist(base == null || base.isEmpty ? null : base, tracks);
}

// Column names of the Music app / iTunes export in its main languages, and
// of common converters (Soundiiz, TuneMyMusic, Exportify).
const _titleHeaders = {
  'name',
  'nom',
  'title',
  'titre',
  'track name',
  'track',
  'song',
  'song name',
  'morceau',
  'titel',
  'nombre',
  'título',
  'titolo',
  'nome',
  '名前',
  'タイトル',
};
const _artistHeaders = {
  'artist',
  'artiste',
  'artist name',
  'artist name(s)',
  'artists',
  'interprète',
  'künstler',
  'interpret',
  'artista',
  'intérprete',
  'artisti',
  'アーティスト',
};

int _column(List<String> headers, Set<String> names) {
  final exact = headers.indexWhere(names.contains);
  if (exact != -1) return exact;
  return headers.indexWhere(
    (h) => names.any((n) => n.length > 3 && h.startsWith(n)),
  );
}

List<String> _splitRow(String line, String separator) {
  if (separator == '\t') return line.split('\t');
  final fields = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == separator && !quoted) {
      fields.add(field.toString());
      field = StringBuffer();
    } else {
      field.write(ch);
    }
  }
  fields.add(field.toString());
  return fields;
}

/// Decodes UTF-16 (with or without a byte order mark, as iTunes writes it)
/// or UTF-8 text.
String decodeText(Uint8List bytes) {
  if (bytes.length >= 2) {
    final b0 = bytes[0];
    final b1 = bytes[1];
    if (b0 == 0xFF && b1 == 0xFE) return _utf16(bytes, 2, little: true);
    if (b0 == 0xFE && b1 == 0xFF) return _utf16(bytes, 2, little: false);
    // No mark, but every other byte is zero: UTF-16 text in ASCII range.
    if (bytes.length >= 4 && b1 == 0 && bytes[3] == 0 && b0 != 0) {
      return _utf16(bytes, 0, little: true);
    }
    if (bytes.length >= 4 && b0 == 0 && bytes[2] == 0 && b1 != 0) {
      return _utf16(bytes, 0, little: false);
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _utf16(Uint8List bytes, int start, {required bool little}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(
      little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

// ---------------------------------------------------------------------------
// SoundCloud: the public page of a set (playlist or album) carries its data;
// the songs it only lists by id are read from the API the SoundCloud website
// uses, with the public client id its scripts embed.
// ---------------------------------------------------------------------------

/// Whether [link] points at a SoundCloud set, or is a share link to one
/// (`on.soundcloud.com/...`).
bool isSoundCloudLink(String link) => RegExp(
  r'((?:www\.|m\.)?soundcloud\.com/[^/\s]+/sets/[^\s?#]+|on\.soundcloud\.com/\w+)',
  caseSensitive: false,
).hasMatch(link);

/// Reads a public SoundCloud set from its link.
Future<ImportedPlaylist> fetchSoundCloudPlaylist(
  String link, {
  http.Client? client,
}) async {
  var target = link.trim();
  if (!isSoundCloudLink(target)) {
    throw const PlaylistImportException(ImportError.invalidLink);
  }
  target = target.replaceFirst('://m.soundcloud.com', '://soundcloud.com');
  if (!target.startsWith('http')) target = 'https://$target';
  final c = client ?? http.Client();
  try {
    final http.Response response;
    try {
      response = await c.get(
        Uri.parse(target),
        headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'},
      );
    } catch (e) {
      throw PlaylistImportException(ImportError.network, e);
    }
    if (response.statusCode == 404) {
      throw const PlaylistImportException(ImportError.notFound);
    }
    if (response.statusCode != 200) {
      throw PlaylistImportException(ImportError.network, response.statusCode);
    }
    final page = utf8.decode(response.bodyBytes);
    final set = parseSoundCloudPage(page);
    if (set == null) {
      throw const PlaylistImportException(ImportError.notFound);
    }
    var tracks = set.tracks;
    if (set.missingIds.isNotEmpty) {
      final clientId = await _soundCloudClientId(c, page);
      if (clientId != null) {
        final more = await _soundCloudTracks(c, set.missingIds, clientId);
        tracks = [
          for (final entry in set.order)
            if (entry.track != null)
              entry.track!
            else if (more[entry.id] != null)
              more[entry.id]!,
        ];
      }
    }
    if (tracks.isEmpty) {
      throw const PlaylistImportException(ImportError.privateOrEmpty);
    }
    return ImportedPlaylist(set.name, tracks, image: set.image);
  } finally {
    if (client == null) c.close();
  }
}

/// The set described by a SoundCloud page (`window.__sc_hydration`): its
/// name, cover, the songs given in full, and the ids of the others.
({
  String? name,
  String? image,
  List<ImportedTrack> tracks,
  List<int> missingIds,
  List<({int id, ImportedTrack? track})> order,
})?
parseSoundCloudPage(String page) {
  final match = RegExp(
    r'window\.__sc_hydration\s*=\s*(\[.*?\]);\s*</script>',
    dotAll: true,
  ).firstMatch(page);
  if (match == null) return null;
  final Object? hydration;
  try {
    hydration = jsonDecode(match.group(1)!);
  } catch (_) {
    return null;
  }
  if (hydration is! List) return null;
  final playlist = hydration
      .whereType<Map>()
      .where((h) => h['hydratable'] == 'playlist')
      .map((h) => h['data'])
      .whereType<Map>()
      .firstOrNull;
  if (playlist == null) return null;

  final order = <({int id, ImportedTrack? track})>[];
  final missing = <int>[];
  for (final item in (playlist['tracks'] as List? ?? const [])) {
    if (item is! Map) continue;
    final id = item['id'];
    final track = soundCloudTrack(item);
    if (id is int) order.add((id: id, track: track));
    if (track == null && id is int) missing.add(id);
  }
  final art =
      (playlist['artwork_url'] as String?) ??
      ((playlist['user'] as Map?)?['avatar_url'] as String?);
  return (
    name: (playlist['title'] as String?)?.trim(),
    image: art?.replaceFirst('-large.', '-t500x500.'),
    tracks: [
      for (final e in order)
        if (e.track != null) e.track!,
    ],
    missingIds: missing,
    order: order,
  );
}

/// A SoundCloud track object as a song: the artist named by the label when
/// there is one, else the uploader.
ImportedTrack? soundCloudTrack(Map item) {
  final title = (item['title'] as String?)?.trim() ?? '';
  if (title.isEmpty) return null;
  final meta = item['publisher_metadata'];
  final artist =
      (meta is Map ? meta['artist'] as String? : null)?.trim() ??
      ((item['user'] as Map?)?['username'] as String?)?.trim() ??
      '';
  return ImportedTrack(title, artist);
}

Future<String?> _soundCloudClientId(http.Client c, String page) async {
  final scripts = RegExp(
    r'<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"',
  ).allMatches(page).map((m) => m.group(1)!).toList();
  // The id is usually in the last scripts.
  for (final src in scripts.reversed) {
    try {
      final response = await c.get(
        Uri.parse(src),
        headers: {'User-Agent': _userAgent},
      );
      if (response.statusCode != 200) continue;
      final id = RegExp(r'client_id\s*[:=]\s*"?([A-Za-z0-9]{20,40})')
          .firstMatch(response.body)
          ?.group(1);
      if (id != null) return id;
    } catch (_) {}
  }
  return null;
}

Future<Map<int, ImportedTrack>> _soundCloudTracks(
  http.Client c,
  List<int> ids,
  String clientId,
) async {
  final found = <int, ImportedTrack>{};
  for (var i = 0; i < ids.length; i += 50) {
    final batch = ids.sublist(i, (i + 50).clamp(0, ids.length));
    try {
      final response = await c.get(
        Uri.parse(
          'https://api-v2.soundcloud.com/tracks?ids=${batch.join(',')}'
          '&client_id=$clientId',
        ),
        headers: {'User-Agent': _userAgent},
      );
      if (response.statusCode != 200) continue;
      final list = jsonDecode(utf8.decode(response.bodyBytes));
      if (list is! List) continue;
      for (final item in list.whereType<Map>()) {
        final id = item['id'];
        final track = soundCloudTrack(item);
        if (id is int && track != null) found[id] = track;
      }
    } catch (_) {}
  }
  return found;
}
