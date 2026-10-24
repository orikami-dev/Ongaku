/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPage;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/screens/local_files_page.dart';
import 'package:musify/ongaku/screens/ongaku_acoustic_test_page.dart';
import 'package:musify/ongaku/screens/ongaku_all_songs_page.dart';
import 'package:musify/ongaku/screens/ongaku_hearing_test_page.dart';
import 'package:musify/ongaku/screens/ongaku_import_playlist_page.dart';
import 'package:musify/ongaku/screens/ongaku_sound_page.dart';
import 'package:musify/ongaku/screens/ongaku_you_page.dart';
import 'package:musify/screens/user_songs_page.dart';

/// Path of the local files screen, under the Library tab.
const localFilesPath = '/library/localFiles';

typedef PushPageBuilder = Page<void> Function({
  required Widget child,
  required GoRouterState state,
});

/// iOS push: slides in from the right and supports the swipe-back gesture.
Page<void> ongakuPushPage({
  required Widget child,
  required GoRouterState state,
}) => CupertinoPage<void>(key: state.pageKey, child: child);

/// Path of the A to Z list of every song, under the Library tab.
const allSongsPath = '/library/allSongs';

/// Library > All Songs.
GoRoute ongakuAllSongsRoute(PushPageBuilder pushPage) => GoRoute(
  path: 'allSongs',
  pageBuilder: (context, state) =>
      pushPage(child: const OngakuAllSongsPage(), state: state),
);

/// Library > Local Files.
GoRoute ongakuLocalFilesRoute(PushPageBuilder pushPage) => GoRoute(
  path: 'localFiles',
  pageBuilder: (context, state) =>
      pushPage(child: const LocalFilesPage(), state: state),
);

/// Home > You: listening history and statistics.
GoRoute ongakuYouRoute(PushPageBuilder pushPage) => GoRoute(
  path: 'you',
  pageBuilder: (context, state) =>
      pushPage(child: const OngakuYouPage(), state: state),
);

/// Home > Recently played (a page of its own, so back always works).
GoRoute ongakuRecentsRoute(PushPageBuilder pushPage) => GoRoute(
  path: 'recents',
  pageBuilder: (context, state) => pushPage(
    child: const UserSongsPage(page: 'recents'),
    state: state,
  ),
);

/// Home > "Morceaux préférés" tile, opened inside the home tab.
GoRoute ongakuLikedRoute(PushPageBuilder pushPage) => GoRoute(
  path: 'liked',
  pageBuilder: (context, state) => pushPage(
    child: const UserSongsPage(page: 'liked'),
    state: state,
  ),
);

/// Settings > Import from Deezer / Apple Music.
List<GoRoute> ongakuImportRoutes(PushPageBuilder pushPage) => [
  for (final (path, source) in [
    ('import-spotify', ImportSource.spotify),
    ('import-deezer-playlist', ImportSource.deezer),
    ('import-apple-music-playlist', ImportSource.appleMusic),
    ('import-soundcloud-playlist', ImportSource.soundCloud),
  ])
    GoRoute(
      path: path,
      pageBuilder: (context, state) => pushPage(
        child: OngakuImportPlaylistPage(source: source),
        state: state,
      ),
    ),
];

/// Settings > Son calibré, with its acoustic and hearing tests.
List<GoRoute> ongakuSoundRoutes(PushPageBuilder pushPage) => [
  GoRoute(
    path: 'sound',
    pageBuilder: (context, state) =>
        pushPage(child: const OngakuSoundPage(), state: state),
    routes: [
      GoRoute(
        path: 'acoustic',
        pageBuilder: (context, state) =>
            pushPage(child: const OngakuAcousticTestPage(), state: state),
      ),
      GoRoute(
        path: 'hearing',
        pageBuilder: (context, state) =>
            pushPage(child: const OngakuHearingTestPage(), state: state),
      ),
    ],
  ),
];
