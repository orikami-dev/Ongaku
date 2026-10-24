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
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:musify/services/common_services.dart' show getSongLyrics;
import 'package:musify/services/data_manager.dart';

/// One line of lyrics and the moment it is sung.
class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

/// Lyrics with a time for every line.
///
/// [synced] is false when only plain text was found: the times are then
/// spread over the song so the lines still follow the music, roughly.
class TimedLyrics {
  const TimedLyrics(this.lines, {required this.synced});

  final List<LyricLine> lines;
  final bool synced;

  /// Index of the line being sung at [position], or -1 before the first one.
  int indexAt(Duration position) {
    var low = 0, high = lines.length - 1, found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].time <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }
}

final _memory = <String, TimedLyrics?>{};
const _cacheCategory = 'cache';

/// The lyrics of [id] if already found in this session (null: not yet
/// looked up, or none), so they show without waiting.
({TimedLyrics? lyrics})? timedLyricsInMemory(String id) =>
    _memory.containsKey(id) ? (lyrics: _memory[id]) : null;

/// Finds lyrics for [item], best source first:
/// 1. a .lrc file next to a local audio file,
/// 2. LRCLIB, a free database of time-synced lyrics,
/// 3. Musify's own plain-text lyrics, spread over the song.
Future<TimedLyrics?> fetchTimedLyrics(MediaItem item) async {
  final key = item.id;
  if (_memory.containsKey(key)) return _memory[key];

  final duration = item.duration;
  TimedLyrics? result;

  final audioPath = item.extras?['audioPath']?.toString();
  if (audioPath != null && item.extras?['isLocal'] == true) {
    result = await _fromSidecar(audioPath);
  }

  if (result == null) {
    final stored = await getData(_cacheCategory, 'ongakuLrc_$key');
    if (stored is String && stored.isNotEmpty) result = parseLrc(stored);
  }

  if (result == null) {
    final lrc = await _fromLrclib(item);
    if (lrc != null) {
      result = parseLrc(lrc);
      if (result != null) {
        await addOrUpdateData(_cacheCategory, 'ongakuLrc_$key', lrc);
      }
    }
  }

  if (result == null) {
    final plain = await getSongLyrics(item.artist, item.title);
    if (plain != null && plain.trim().isNotEmpty) {
      result = spreadPlainLyrics(plain, duration);
    }
  }

  _memory[key] = result;
  return result;
}

Future<TimedLyrics?> _fromSidecar(String audioPath) async {
  try {
    final dot = audioPath.lastIndexOf('.');
    final base = dot > 0 ? audioPath.substring(0, dot) : audioPath;
    for (final ext in const ['.lrc', '.LRC']) {
      final file = File('$base$ext');
      if (file.existsSync()) return parseLrc(await file.readAsString());
    }
  } catch (_) {}
  return null;
}

Future<String?> _fromLrclib(MediaItem item) async {
  final artist = _cleanArtist(item.artist ?? '');
  final title = _cleanTitle(item.title, artist);
  if (title.isEmpty) return null;
  final seconds = item.duration?.inSeconds;

  try {
    // 1. Exact match on title, artist and length.
    final exact = await _lrclibGet('/api/get', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
      if (seconds != null) 'duration': seconds.toString(),
    });
    if (exact is Map && exact['syncedLyrics'] is String) {
      return exact['syncedLyrics'] as String;
    }

    // 2. Looser searches, YouTube titles rarely match to the letter.
    final queries = <Map<String, String>>[
      {'track_name': title, if (artist.isNotEmpty) 'artist_name': artist},
      {'q': '$title $artist'.trim()},
      {'track_name': title},
    ];
    for (final query in queries) {
      final found = await _lrclibGet('/api/search', query);
      if (found is! List) continue;
      final candidates = found
          .whereType<Map>()
          .where((r) => r['syncedLyrics'] is String)
          .toList();
      if (candidates.isEmpty) continue;
      if (seconds != null) {
        // Closest length first: a version that runs 3 minutes against a
        // 4 minute video would drift.
        int gap(Map r) =>
            ((r['duration'] as num? ?? 0) - seconds).abs().round();
        candidates.sort((a, b) => gap(a).compareTo(gap(b)));
        if (gap(candidates.first) > 25) continue;
      }
      return candidates.first['syncedLyrics'] as String;
    }
  } catch (_) {}
  return null;
}

Future<Object?> _lrclibGet(String path, Map<String, String> params) async {
  final response = await http
      .get(
        Uri.https('lrclib.net', path, params),
        headers: const {
          'User-Agent': 'Ongaku (https://github.com/gokadzev/Musify)',
        },
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) return null;
  return jsonDecode(utf8.decode(response.bodyBytes));
}

final _noise = RegExp(
  r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|clip|visuali[sz]er|hd|4k|mv|remaster|live|explicit)[^\)\]]*[\)\]]',
  caseSensitive: false,
);

String _cleanTitle(String title, String artist) {
  var t = title
      .replaceAll(RegExp(r'[【\[][^】\]]*[】\]]'), '')
      .replaceAll(_noise, '');
  // YouTube titles are often "Artist - Title".
  final dash = t.indexOf(' - ');
  if (dash > 0) {
    final left = t.substring(0, dash).trim().toLowerCase();
    if (artist.isEmpty ||
        left.contains(artist.toLowerCase().split(' ').first)) {
      t = t.substring(dash + 3);
    }
  }
  return t
      .replaceAll(RegExp(r'\s*(ft\.|feat\.).*$', caseSensitive: false), '')
      .trim();
}

String _cleanArtist(String artist) => artist
    .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
    .replaceAll(RegExp(r'VEVO$'), '')
    .split(RegExp(r',|&| feat\.| ft\.| x ', caseSensitive: false))
    .first
    .trim();

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC text. Returns null when it has no time tags.
TimedLyrics? parseLrc(String lrc) {
  final lines = <LyricLine>[];
  var offset = Duration.zero;
  for (final raw in const LineSplitter().convert(lrc)) {
    final offsetMatch = RegExp(r'^\[offset:\s*([+-]?\d+)\]').firstMatch(raw);
    if (offsetMatch != null) {
      offset = Duration(milliseconds: int.parse(offsetMatch.group(1)!));
      continue;
    }
    final tags = _timeTag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    final text = raw.substring(tags.last.end).trim();
    for (final tag in tags) {
      final fraction = tag.group(3) ?? '0';
      final millis = int.parse(fraction.padRight(3, '0').substring(0, 3));
      lines.add(
        LyricLine(
          Duration(
                minutes: int.parse(tag.group(1)!),
                seconds: int.parse(tag.group(2)!),
                milliseconds: millis,
              ) -
              offset,
          text,
        ),
      );
    }
  }
  if (lines.isEmpty) return null;
  lines.sort((a, b) => a.time.compareTo(b.time));
  return TimedLyrics(lines, synced: true);
}

/// Spreads plain lyrics over [duration], longer lines getting more time.
TimedLyrics spreadPlainLyrics(String text, Duration? duration) {
  final rows = const LineSplitter()
      .convert(text)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('©'))
      .toList();
  final total = (duration ?? const Duration(minutes: 3)).inMilliseconds;
  // Songs rarely start singing right away or end on a word.
  final start = total * 0.06;
  final span = total * 0.86;
  final weights = [for (final r in rows) 8 + r.length];
  final sum = weights.fold<int>(0, (a, b) => a + b);
  var acc = 0;
  final lines = <LyricLine>[];
  for (var i = 0; i < rows.length; i++) {
    lines.add(
      LyricLine(
        Duration(milliseconds: (start + span * acc / sum).round()),
        rows[i],
      ),
    );
    acc += weights[i];
  }
  return TimedLyrics(lines, synced: false);
}
