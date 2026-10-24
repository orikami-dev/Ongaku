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
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/local/local_ids.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/io_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Audio files the device can play through just_audio / media_kit.
const localAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'ogg',
  'oga',
  'opus',
  'wav',
  'wma',
  'alac',
  'aiff',
  'aif',
  'mka',
  'webm',
};

/// Songs imported from the device, stored in the Hive `user` box.
///
/// Each song is a regular Musify song map, so the existing player, queue,
/// playlists and likes work with it unchanged. Playback goes through
/// upstream's offline path because the map carries an existing `audioPath`.
final localSongs = ValueNotifier<List<Map>>(_readSongs());

/// Folders added by the user; rescanned when the local library opens.
final localMusicFolders = ValueNotifier<List<String>>(_readFolders());

/// True while an import or a rescan is running.
final localLibraryBusy = ValueNotifier<bool>(false);

const _songsKey = 'ongakuLocalSongs';
const _foldersKey = 'ongakuLocalFolders';

List<Map> _readSongs() {
  try {
    final raw = Hive.box('user').get(_songsKey, defaultValue: const []);
    return (raw as List).whereType<Map>().map(Map.of).toList();
  } catch (_) {
    return [];
  }
}

List<String> _readFolders() {
  try {
    final raw = Hive.box('user').get(_foldersKey, defaultValue: const []);
    return (raw as List).map((e) => e.toString()).toList();
  } catch (_) {
    return [];
  }
}

Future<void> _saveSongs(List<Map> songs) async {
  localSongs.value = songs;
  await addOrUpdateData<List>('user', _songsKey, songs);
}

Future<void> _saveFolders(List<String> folders) async {
  localMusicFolders.value = folders;
  await addOrUpdateData<List>('user', _foldersKey, folders);
}

/// Result of an import, for the UI to report.
class LocalImportResult {
  const LocalImportResult({required this.added, this.permissionDenied = false});

  final int added;
  final bool permissionDenied;
}

/// Lets the user pick audio files and adds them to the local library.
///
/// On Android the picker hands back temporary copies, so they are moved to
/// the app's storage to stay playable after the cache is cleared.
Future<LocalImportResult> pickAndImportLocalFiles() async {
  final files = await FilePicker.pickFiles(type: FileType.audio);
  final paths = files.map((f) => f.path).whereType<String>().toList();
  if (paths.isEmpty) return const LocalImportResult(added: 0);

  return _runBusy(() async {
    final kept = <String>[];
    for (final path in paths) {
      kept.add(Platform.isAndroid ? await _keepCopy(path) : path);
    }
    return LocalImportResult(added: await _importPaths(kept));
  });
}

/// Lets the user pick a folder, imports every audio file inside it
/// (recursively) and remembers it for later rescans.
Future<LocalImportResult> pickAndImportLocalFolder() async {
  if (!await _ensureAudioPermission()) {
    return const LocalImportResult(added: 0, permissionDenied: true);
  }

  final folder = await FilePicker.getDirectoryPath();
  if (folder == null || folder.isEmpty) {
    return const LocalImportResult(added: 0);
  }

  return LocalImportResult(added: await importLocalFolderPath(folder));
}

/// Imports every audio file of [folder] and remembers it for rescans.
Future<int> importLocalFolderPath(String folder) {
  return _runBusy(() async {
    if (!localMusicFolders.value.contains(folder)) {
      await _saveFolders([...localMusicFolders.value, folder]);
    }
    final paths = await Isolate.run(() => _listAudioFiles(folder));
    return _importPaths(paths);
  });
}

/// Picks up new files in remembered folders and drops songs whose file is
/// gone. Cheap when nothing changed.
Future<int> rescanLocalLibrary() async {
  if (localLibraryBusy.value) return 0;
  return _runBusy(() async {
    final folders = localMusicFolders.value;
    final existing = localSongs.value;

    final checks = await Isolate.run(() {
      final missing = <String>[];
      for (final song in existing) {
        final path = song['audioPath']?.toString();
        if (path == null || !File(path).existsSync()) {
          missing.add(song['ytid'].toString());
        }
      }
      final found = <String>[];
      for (final folder in folders) {
        found.addAll(_listAudioFiles(folder));
      }
      return (missing: missing, found: found);
    });

    if (checks.missing.isNotEmpty) {
      final missing = checks.missing.toSet();
      await _saveSongs(
        localSongs.value
            .where((s) => !missing.contains(s['ytid'].toString()))
            .toList(),
      );
    }
    return _importPaths(checks.found);
  });
}

Future<void> removeLocalSong(Map song) async {
  final id = song['ytid']?.toString();
  await _saveSongs(
    localSongs.value.where((s) => s['ytid']?.toString() != id).toList(),
  );
  // Only delete files the app copied itself, never the user's own files.
  final path = song['audioPath']?.toString();
  if (path != null && path.startsWith(_copiesDir)) {
    await _deleteQuietly(path);
  }
  final artwork = song['artworkPath']?.toString();
  if (artwork != null && artwork.startsWith(_artworkDir)) {
    await _deleteQuietly(artwork);
  }
}

Future<void> removeLocalFolder(String folder) async {
  await _saveFolders(
    localMusicFolders.value.where((f) => f != folder).toList(),
  );
  await _saveSongs(
    localSongs.value
        .where(
          (s) => !(s['audioPath']?.toString() ?? '').startsWith(
            folder.endsWith('/') ? folder : '$folder/',
          ),
        )
        .toList(),
  );
}

// ------------------------------------------------------------------ helpers

String get _copiesDir => '$applicationDirPath/ongaku_local_music';
String get _artworkDir => '$applicationDirPath/ongaku_local_artwork';

Future<T> _runBusy<T>(Future<T> Function() task) async {
  localLibraryBusy.value = true;
  try {
    return await task();
  } finally {
    localLibraryBusy.value = false;
  }
}

Future<bool> _ensureAudioPermission() async {
  if (!Platform.isAndroid) return true;
  try {
    // READ_MEDIA_AUDIO on Android 13+, READ_EXTERNAL_STORAGE before.
    final audio = await Permission.audio.request();
    if (audio.isGranted || audio.isLimited) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  } catch (e, stackTrace) {
    logger.log(
      'Audio permission request failed',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<String> _keepCopy(String tempPath) async {
  try {
    final source = File(tempPath);
    final name = tempPath.split(Platform.pathSeparator).last;
    final dir = Directory(_copiesDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    var target = File('${dir.path}/$name');
    var i = 1;
    while (await target.exists()) {
      if (await target.length() == await source.length()) return target.path;
      target = File('${dir.path}/${i++}_$name');
    }
    await source.copy(target.path);
    return target.path;
  } catch (e, stackTrace) {
    logger.log('Could not keep local file', error: e, stackTrace: stackTrace);
    return tempPath;
  }
}

List<String> _listAudioFiles(String folder) {
  final result = <String>[];
  try {
    final dir = Directory(folder);
    if (!dir.existsSync()) return result;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final dot = entity.path.lastIndexOf('.');
      if (dot == -1) continue;
      final ext = entity.path.substring(dot + 1).toLowerCase();
      if (localAudioExtensions.contains(ext)) result.add(entity.path);
    }
  } catch (_) {
    // Unreadable folders are skipped; the rest of the scan continues.
  }
  result.sort();
  return result;
}

/// Reads tags off the main isolate and adds songs not already present.
Future<int> _importPaths(List<String> paths) async {
  final known = {for (final s in localSongs.value) s['audioPath']?.toString()};
  final fresh = paths.where((p) => !known.contains(p)).toSet().toList();
  if (fresh.isEmpty) return 0;

  final artworkDir = _artworkDir;
  final now = DateTime.now().millisecondsSinceEpoch;
  final songs = await Isolate.run(
    () => [for (final path in fresh) _buildSong(path, artworkDir, now)],
  );

  await _saveSongs([...localSongs.value, ...songs]);
  return songs.length;
}

/// Builds a Musify-compatible song map for a local file.
Map<String, dynamic> _buildSong(String path, String artworkDir, int now) {
  final id = localSongIdForPath(path);
  final fileName = path.split(Platform.pathSeparator).last;
  final baseName = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;

  String? title;
  String? artist;
  String? album;
  int? duration;
  String? artworkPath;

  try {
    final tags = readMetadata(File(path), getImage: true);
    title = _clean(tags.title);
    artist = _clean(tags.artist) ?? _clean(tags.albumArtist);
    album = _clean(tags.album);
    duration = tags.duration?.inSeconds;
    if (tags.pictures.isNotEmpty) {
      final picture = tags.pictures.first;
      final ext = picture.mimetype.contains('png') ? 'png' : 'jpg';
      final file = File('$artworkDir/$id.$ext');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(picture.bytes);
      artworkPath = file.path;
    }
  } catch (_) {
    // Untagged or unsupported container: fall back to the file name below.
  }

  // "Artist - Title.mp3" is the most common naming for untagged files.
  if (title == null) {
    final parts = baseName.split(' - ');
    if (parts.length >= 2 && artist == null) {
      artist = parts.first.trim();
      title = parts.sublist(1).join(' - ').trim();
    } else {
      title = baseName.trim();
    }
  }

  artworkPath ??= _folderCover(File(path).parent);

  return {
    'id': id,
    'ytid': id,
    'title': title,
    'artist': artist ?? '',
    'album': album ?? '',
    'audioPath': path,
    'artworkPath': artworkPath,
    'highResImage': '',
    'lowResImage': '',
    'isLive': false,
    'isLocal': true,
    'dateAdded': now,
    if (duration != null && duration > 0) 'duration': duration,
  };
}

String? _clean(String? value) {
  final v = value?.replaceAll('\u0000', '').trim();
  return v == null || v.isEmpty ? null : v;
}

String? _folderCover(Directory dir) {
  const names = ['cover', 'folder', 'front', 'album', 'albumart'];
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot == -1) continue;
      final base = name.substring(0, dot);
      final ext = name.substring(dot + 1);
      if (names.contains(base) && {'jpg', 'jpeg', 'png'}.contains(ext)) {
        return entity.path;
      }
    }
  } catch (_) {}
  return null;
}

Future<void> _deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// Stable id for a file path (also used by [isLocalSongId]).
String localSongIdForPath(String path) =>
    '$localSongIdPrefix${sha1.convert(utf8.encode(path)).toString().substring(0, 16)}';
