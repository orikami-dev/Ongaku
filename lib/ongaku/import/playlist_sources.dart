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
  const ImportedPlaylist(this.name, this.tracks);

  final String? name;
  final List<ImportedTrack> tracks;
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
    return ImportedPlaylist(name, tracks);
  } finally {
    if (client == null) c.close();
  }
}

Future<Map<String, dynamic>> _getJson(http.Client c, Uri uri) async {
  final http.Response response;
  try {
    response = await c.get(uri, headers: {'User-Agent': _userAgent});
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
    final playlist = parseAppleMusicPage(utf8.decode(response.bodyBytes));
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
      if (tracks.isNotEmpty) return ImportedPlaylist(name, tracks);
    } on FormatException {
      // Fall through to the schema.org data.
    }
  }

  for (final script in document.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    try {
      final tracks = _schemaTracks(jsonDecode(script.text));
      if (tracks.isNotEmpty) return ImportedPlaylist(name, tracks);
    } on FormatException {
      continue;
    }
  }
  return ImportedPlaylist(name, const []);
}

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
