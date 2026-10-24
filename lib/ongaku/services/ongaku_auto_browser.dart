/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show Listenable;
import 'package:musify/main.dart' show audioHandler, isFdroidBuild;
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/ongaku/screens/ongaku_all_songs_page.dart'
    show indexLetter, librarySongs;
import 'package:musify/services/audio_service_android_auto.dart';
import 'package:musify/services/common_services.dart'
    show getRecommendedSongs, userLikedSongsList, userOfflineSongs;
import 'package:musify/services/playlists_manager.dart'
    show userCustomPlaylists;
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:rxdart/rxdart.dart';

/// Android Auto browse tree for Ongaku, layered on upstream's browser.
///
/// The car shows the root's children as tabs (up to four), organised like
/// the app: Home (recents and For You), Library, Playlists and Up Next,
/// each with its own icon. Library holds All Songs, Liked Songs, Local
/// Files, Downloaded and Playlists; song lists start with a Shuffle row.
/// Everything else is served by upstream's [AndroidAutoBrowser], so its
/// behaviour follows Musify updates.
class OngakuAutoBrowser extends AndroidAutoBrowser {
  OngakuAutoBrowser(this._ongakuHost) : super(_ongakuHost);

  final AndroidAutoHost _ongakuHost;

  // Containers served by upstream (ids defined in audio_service_android_auto).
  static const _upstreamQueue = 'current_queue';
  static const _upstreamLiked = 'liked_songs';
  static const _upstreamPlaylists = 'playlists';
  static const _upstreamDownloaded = 'offline_songs';
  static const _upstreamRecent = 'recently_played';

  static const _home = 'ongaku_home';
  static const _library = 'ongaku_library';
  static const _allSongs = 'ongaku_all';
  static const _allSongPrefix = 'ongaku_all:';
  static const _forYouPrefix = 'ongaku_for_you:';
  static const _shufflePrefix = 'ongaku_shuffle:';
  static const _groupTitle = 'android.media.browse.CONTENT_STYLE_GROUP_TITLE';
  static const _singleItemHint =
      'android.media.browse.CONTENT_STYLE_SINGLE_ITEM_HINT';

  /// Song lists that get a Shuffle row on top.
  static bool _shufflable(String id) =>
      id == _allSongs ||
      id == _local ||
      id == _upstreamLiked ||
      id == _upstreamDownloaded ||
      id.startsWith('playlist:');

  List<Map> _allSongsCache = const [];
  List<Map> _forYouCache = const [];
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
      _folder(_home, s.autoHome, 'ic_ongaku_auto_home', grid: true),
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
      _folder(_allSongs, s.allSongs, 'ic_ongaku_auto_all'),
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

  MediaItem _shuffleItem(String parent) => MediaItem(
    id: '$_shufflePrefix$parent',
    title: _strings.autoShuffle,
    artUri: _icon('ic_ongaku_shuffle'),
  );

  MediaItem _grouped(MediaItem item, String group, {bool grid = false}) =>
      item.copyWith(
        extras: {
          ...?item.extras,
          _groupTitle: group,
          if (grid) _singleItemHint: AndroidContentStyle.gridItemHintValue,
        },
      );

  /// Home: recents in a row of artworks, then For You, as in the app.
  Future<List<MediaItem>> _homeItems() async {
    final s = _strings;
    final recents = (await super.children(_upstreamRecent))
        .where((item) => item.playable ?? false)
        .take(8);
    try {
      _forYouCache = List<Map>.from(
        (await getRecommendedSongs().timeout(const Duration(seconds: 12)))
            .whereType<Map>()
            .take(12),
      );
    } catch (_) {
      // Offline or slow: the home tab keeps what it already had.
    }
    return [
      for (final item in recents) _grouped(item, s.autoRecent, grid: true),
      for (var i = 0; i < _forYouCache.length; i++)
        _grouped(
          mapToMediaItem(_forYouCache[i])
              .copyWith(id: '$_forYouPrefix$i', playable: true),
          s.forYou,
        ),
    ];
  }

  List<Map> _computeAllSongs() => _allSongsCache = librarySongs(
    liked: userLikedSongsList.value,
    offline: userOfflineSongs.value,
    playlists: userCustomPlaylists.value,
    local: localSongs.value,
  );

  /// All Songs, A to Z with the letter as the group title.
  List<MediaItem> _allSongItems() {
    final songs = _computeAllSongs();
    return [
      for (var i = 0; i < songs.length; i++)
        _grouped(
          mapToMediaItem(songs[i])
              .copyWith(id: '$_allSongPrefix$i', playable: true),
          indexLetter(songs[i]['title']),
        ),
    ];
  }

  MediaItem _empty(String parent) => MediaItem(
    id: '$parent:__empty__',
    title: _strings.emptyTitle,
    playable: false,
    extras: const {'isBrowsable': false},
  );

  @override
  Future<List<MediaItem>> children(String parentMediaId) async {
    if (parentMediaId == AudioService.browsableRootId) return _rootTabs();
    if (parentMediaId == _library) return _libraryFolders();
    if (parentMediaId == _home) {
      final items = await _homeItems();
      return items.isEmpty ? [_empty(_home)] : items;
    }
    final List<MediaItem> items;
    if (parentMediaId == _local) {
      items = _localItems(localSongs.value);
    } else if (parentMediaId == _allSongs) {
      items = _allSongItems();
    } else {
      items = await super.children(parentMediaId);
    }
    if (!_shufflable(parentMediaId)) return items;
    if (items.where((item) => item.playable ?? false).isEmpty) {
      return items.isEmpty ? [_empty(parentMediaId)] : items;
    }
    return [_shuffleItem(parentMediaId), ...items];
  }

  /// Shuffle row: a random song of the list first, the rest shuffled.
  Future<bool> _playShuffled(String parent) async {
    final songs = (await children(parent))
        .where(
          (item) =>
              (item.playable ?? false) && !item.id.startsWith(_shufflePrefix),
        )
        .toList();
    if (songs.isEmpty) return true;
    final pick = songs[Random().nextInt(songs.length)];
    await playFromMediaId(pick.id);
    await audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    return true;
  }

  @override
  void setupMediaBrowserSubscriptions() {
    super.setupMediaBrowserSubscriptions();
    void refresh(String parent) {
      final subject = subscribeToChildren(parent);
      if (subject is BehaviorSubject<Map<String, dynamic>> &&
          !subject.isClosed) {
        subject.add(<String, dynamic>{});
      }
    }

    localSongs.addListener(() => refresh(_local));
    Listenable.merge([
      userLikedSongsList,
      userOfflineSongs,
      userCustomPlaylists,
      localSongs,
    ]).addListener(() => refresh(_allSongs));
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
    final list = _listFor(mediaId);
    if (list != null) return mapToMediaItem(list.songs[list.index]);
    final index = _localIndex(mediaId);
    if (index != null) return _localItem(localSongs.value[index]);
    return super.mediaItemForId(mediaId);
  }

  @override
  Future<void> prepareFromId(String mediaId) async {
    final list = _listFor(mediaId);
    if (list != null) {
      _ongakuHost.publishPreparedBrowserItem(
        mapToMediaItem(list.songs[list.index]),
      );
      return;
    }
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
    if (mediaId.startsWith(_shufflePrefix)) {
      return _playShuffled(mediaId.substring(_shufflePrefix.length));
    }
    final list = _listFor(mediaId);
    if (list != null) {
      await _ongakuHost.playBrowserPlaylist(
        List<Map>.of(list.songs),
        songIndex: list.index,
      );
      return true;
    }
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

  /// The song list and position behind an All Songs or For You item.
  ({List<Map> songs, int index})? _listFor(String mediaId) {
    final List<Map> songs;
    final String rest;
    if (mediaId.startsWith(_allSongPrefix)) {
      if (_allSongsCache.isEmpty) _computeAllSongs();
      songs = _allSongsCache;
      rest = mediaId.substring(_allSongPrefix.length);
    } else if (mediaId.startsWith(_forYouPrefix)) {
      songs = _forYouCache;
      rest = mediaId.substring(_forYouPrefix.length);
    } else {
      return null;
    }
    final index = int.tryParse(rest);
    if (index == null || index < 0 || index >= songs.length) return null;
    return (songs: songs, index: index);
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
