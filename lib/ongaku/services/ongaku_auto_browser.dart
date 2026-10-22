/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:audio_service/audio_service.dart';
import 'package:musify/main.dart' show isFdroidBuild;
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/services/audio_service_android_auto.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:rxdart/rxdart.dart';

/// Android Auto browse tree for Ongaku, layered on upstream's browser.
///
/// The car shows the root's children as tabs (up to four), so the root is
/// organised like Apple Music in CarPlay: Recents, Library, Playlists and
/// Up Next, each with its own icon. Library holds Liked Songs, Local Files,
/// Downloaded and Playlists. Everything except Local Files is served by
/// upstream's [AndroidAutoBrowser], so its behaviour follows Musify updates.
class OngakuAutoBrowser extends AndroidAutoBrowser {
  OngakuAutoBrowser(this._ongakuHost) : super(_ongakuHost);

  final AndroidAutoHost _ongakuHost;

  // Containers served by upstream (ids defined in audio_service_android_auto).
  static const _upstreamQueue = 'current_queue';
  static const _upstreamLiked = 'liked_songs';
  static const _upstreamPlaylists = 'playlists';
  static const _upstreamDownloaded = 'offline_songs';
  static const _upstreamRecent = 'recently_played';

  static const _library = 'ongaku_library';
  static const _local = 'ongaku_local';
  static const _localSongPrefix = 'ongaku_local:';

  OngakuStrings get _strings =>
      OngakuStrings.forLanguage(languageSetting.languageCode);

  Uri _icon(String name) {
    final package = isFdroidBuild
        ? '$androidApplicationId.fdroid'
        : androidApplicationId;
    return Uri.parse('android.resource://$package/drawable/$name');
  }

  MediaItem _folder(
    String id,
    String title,
    String icon, {
    bool grid = false,
  }) => MediaItem(
    id: id,
    title: title,
    playable: false,
    artUri: _icon(icon),
    extras: {
      'isBrowsable': true,
      AndroidContentStyle.browsableHintKey: grid
          ? AndroidContentStyle.gridItemHintValue
          : AndroidContentStyle.listItemHintValue,
      AndroidContentStyle.playableHintKey:
          AndroidContentStyle.listItemHintValue,
    },
  );

  List<MediaItem> _rootTabs() {
    final s = _strings;
    return [
      _folder(_upstreamRecent, s.autoRecent, 'ic_ongaku_auto_recent'),
      _folder(_library, s.autoLibrary, 'ic_ongaku_auto_library'),
      _folder(
        _upstreamPlaylists,
        s.autoPlaylists,
        'ic_ongaku_auto_playlists',
        grid: true,
      ),
      _folder(_upstreamQueue, s.autoQueue, 'ic_ongaku_auto_queue'),
    ];
  }

  List<MediaItem> _libraryFolders() {
    final s = _strings;
    return [
      _folder(_upstreamLiked, s.autoLiked, 'ic_ongaku_auto_liked'),
      _folder(_local, s.localFiles, 'ic_ongaku_auto_local'),
      _folder(
        _upstreamDownloaded,
        s.autoDownloaded,
        'ic_ongaku_auto_downloads',
      ),
      _folder(
        _upstreamPlaylists,
        s.autoPlaylists,
        'ic_ongaku_auto_playlists',
        grid: true,
      ),
    ];
  }

  MediaItem _localItem(Map song) {
    final artist = song['artist']?.toString().trim() ?? '';
    return mapToMediaItem(song).copyWith(
      id: '$_localSongPrefix${song['ytid']}',
      playable: true,
      displayTitle: song['title']?.toString(),
      displaySubtitle: artist.isEmpty ? appName : artist,
    );
  }

  List<MediaItem> _localItems(Iterable<Map> songs) => [
    for (final song in songs) _localItem(song),
  ];

  @override
  Future<List<MediaItem>> children(String parentMediaId) async {
    if (parentMediaId == AudioService.browsableRootId) return _rootTabs();
    if (parentMediaId == _library) return _libraryFolders();
    if (parentMediaId == _local) {
      final songs = localSongs.value;
      if (songs.isEmpty) {
        return [
          MediaItem(
            id: '$_local:__empty__',
            title: _strings.emptyTitle,
            playable: false,
            extras: const {'isBrowsable': false},
          ),
        ];
      }
      return _localItems(songs);
    }
    return super.children(parentMediaId);
  }

  @override
  void setupMediaBrowserSubscriptions() {
    super.setupMediaBrowserSubscriptions();
    localSongs.addListener(() {
      final subject = subscribeToChildren(_local);
      if (subject is BehaviorSubject<Map<String, dynamic>> &&
          !subject.isClosed) {
        subject.add(<String, dynamic>{});
      }
    });
  }

  @override
  Future<List<MediaItem>> search(String query) async {
    final needle = query.trim().toLowerCase();
    final local = needle.isEmpty
        ? const <Map>[]
        : localSongs.value
              .where((song) {
                final title = song['title']?.toString().toLowerCase() ?? '';
                final artist = song['artist']?.toString().toLowerCase() ?? '';
                return title.contains(needle) || artist.contains(needle);
              })
              .take(15);
    return [..._localItems(local), ...await super.search(query)];
  }

  @override
  Future<MediaItem?> mediaItemForId(String mediaId) async {
    final index = _localIndex(mediaId);
    if (index != null) return _localItem(localSongs.value[index]);
    return super.mediaItemForId(mediaId);
  }

  @override
  Future<void> prepareFromId(String mediaId) async {
    final index = _localIndex(mediaId);
    if (index != null) {
      _ongakuHost.publishPreparedBrowserItem(
        _localItem(localSongs.value[index]),
      );
      return;
    }
    return super.prepareFromId(mediaId);
  }

  @override
  Future<bool> playFromMediaId(String mediaId) async {
    final index = _localIndex(mediaId);
    if (index != null) {
      // Play the whole local library from the chosen song, like the app does.
      await _ongakuHost.playBrowserPlaylist(
        List<Map>.of(localSongs.value),
        songIndex: index,
      );
      return true;
    }
    return super.playFromMediaId(mediaId);
  }

  int? _localIndex(String mediaId) {
    if (!mediaId.startsWith(_localSongPrefix)) return null;
    final ytid = mediaId.substring(_localSongPrefix.length);
    final index = localSongs.value.indexWhere(
      (song) => song['ytid']?.toString() == ytid,
    );
    return index < 0 ? null : index;
  }
}
