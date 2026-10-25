/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:collection';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Where "Exporter les journaux" sends the report: the project's own logs
/// mailbox (chosen by Orikami for every version, public ones included).
const ongakuLogsAddress = 'orikami.logs@gmail.com';

/// Lines of the journal kept for the report.
const ongakuJournalLines = 500;

/// The app's journal: Musify's error log plus Ongaku's key steps, the last
/// [ongakuJournalLines] lines only, in memory.
class OngakuJournal {
  OngakuJournal._();

  static final _lines = ListQueue<String>();
  static final started = DateTime.now();
  static bool _watching = false;

  /// The trace of the crash that last closed the app, if any.
  static String? lastCrash = _readCrash();

  /// The last error Flutter reported (the app stayed open).
  static String? lastError;

  /// Adds `text` (one or more lines).
  static void add(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      _lines.addLast(line);
      while (_lines.length > ongakuJournalLines) {
        _lines.removeFirst();
      }
    }
  }

  /// A key step, with the time in front.
  static void note(String step) => add('[${DateTime.now()}] $step');

  static String get text => _lines.join('\n');

  /// Keeps the crash trace read at start, so it is still there for an
  /// export later on.
  static void keepCrash(String trace) {
    lastCrash = trace;
    try {
      Hive.box('settings').put('ongakuLastCrash', trace);
    } catch (_) {}
  }

  /// Notes playback steps and errors (no titles: ids only, which the
  /// report then numbers).
  static void watch(BaseAudioHandler handler) {
    if (_watching) return;
    _watching = true;
    note('start');
    handler.mediaItem
        .map((item) => item?.id)
        .distinct()
        .listen((id) => note(id == null ? 'player: empty' : 'play $id'));
    handler.playbackState
        .map((s) => s.processingState)
        .distinct()
        .listen((state) => note('player: ${state.name}'));
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      lastError = '${details.exceptionAsString()}\n${details.stack ?? ''}';
      add('[${DateTime.now()}] Flutter error: ${details.exceptionAsString()}');
      previous?.call(details);
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      lastError = '$error\n$stack';
      add('[${DateTime.now()}] Uncaught: $error');
      return platform?.call(error, stack) ?? false;
    };
  }
}

String? _readCrash() {
  try {
    return Hive.box('settings').get('ongakuLastCrash') as String?;
  } catch (_) {
    return null;
  }
}

/// Removes what is personal from a report, on the phone, before anyone sees
/// it: e-mails, file paths, the user's songs (titles, artists, albums),
/// YouTube ids (numbered, so a sequence can still be followed), URL
/// parameters, IP and MAC addresses, and the names given to the phone and
/// its accessories.
class OngakuScrubber {
  OngakuScrubber({
    Iterable<String> titles = const [],
    Iterable<String> artists = const [],
    Iterable<String> albums = const [],
    Iterable<String> deviceNames = const [],
  }) {
    void addAll(Iterable<String> words, String tag) {
      for (final w in words) {
        final t = w.trim();
        // Very short words ("Go", "U2") would cut ordinary log words.
        if (t.length >= 3) _words.putIfAbsent(t, () => tag);
      }
    }

    addAll(deviceNames, '<appareil>');
    addAll(titles, '<titre>');
    addAll(albums, '<album>');
    addAll(artists, '<artiste>');
  }

  final _words = <String, String>{};
  final _ids = <String, int>{};

  static final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
  static final _path = RegExp(
    r'''(/storage|/sdcard|/data/user|/data/data|/mnt|/document|content://)[^\s'"),\]]*''',
  );
  static final _query = RegExp(r'''(https?://[^\s?'"]+)\?[^\s'"]*''');
  static final _ipv4 = RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b');
  static final _ipv6 = RegExp(r'\b([0-9a-fA-F]{1,4}:){4,7}[0-9a-fA-F]{1,4}\b');
  static final _mac = RegExp(r'\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b');
  // Playlists, albums, channels: their prefixes make them unambiguous.
  static final _listId = RegExp(
    r'\b(PL|OLAK5uy_|RD|VL|UC|MPRE|MPLA|FL|LL|UU)[A-Za-z0-9_-]{10,}\b',
  );
  // An 11-character video id, told apart from an ordinary word or a code
  // name by a digit, a "-", or capitals inside it.
  static final _videoId = RegExp(
    '(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{11}(?![A-Za-z0-9_-])',
  );

  static bool _looksLikeId(String s) =>
      RegExp('[0-9-]').hasMatch(s) ||
      RegExp('[A-Z]').allMatches(s.substring(1)).length >= 2;

  String _number(String id) =>
      '<id-${_ids.putIfAbsent(id, () => _ids.length + 1)}>';

  String scrub(String text) {
    var out = text
        .replaceAll(_email, '<email>')
        .replaceAllMapped(_query, (m) => '${m[1]}?<masqué>')
        .replaceAll(_path, '<fichier>')
        .replaceAll(_mac, '<mac>')
        .replaceAll(_ipv6, '<ip>')
        .replaceAll(_ipv4, '<ip>');
    // Longest first, so "Paper Moons (Live)" goes before "Paper Moons".
    final words = _words.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final w in words) {
      out = out.replaceAll(
        RegExp(RegExp.escape(w), caseSensitive: false),
        _words[w]!,
      );
    }
    out = out.replaceAllMapped(_listId, (m) => _number(m[0]!));
    out = out.replaceAllMapped(
      _videoId,
      (m) => _looksLikeId(m[0]!) ? _number(m[0]!) : m[0]!,
    );
    return out;
  }
}

/// Builds the report: a technical header, the sound state, the journal, the
/// last crash and the last error, then filters it all.
String buildOngakuReport({
  required Map<String, String> header,
  required Map<String, String> sound,
  required String journal,
  required OngakuScrubber scrubber,
  String? crash,
  String? error,
}) {
  final b = StringBuffer()..writeln('== Ongaku, journaux ==');
  header.forEach((k, v) => b.writeln('$k: $v'));
  b
    ..writeln()
    ..writeln('== Son ==');
  sound.forEach((k, v) => b.writeln('$k: $v'));
  b
    ..writeln()
    ..writeln('== Journal ($ongakuJournalLines dernières lignes) ==')
    ..writeln(journal.isEmpty ? '(vide)' : journal);
  if (crash != null && crash.isNotEmpty) {
    b
      ..writeln()
      ..writeln('== Dernier plantage ==')
      ..writeln(crash);
  }
  if (error != null && error.isNotEmpty) {
    b
      ..writeln()
      ..writeln('== Dernière erreur ==')
      ..writeln(error);
  }
  return scrubber.scrub(b.toString());
}
