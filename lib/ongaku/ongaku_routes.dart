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
import 'package:musify/ongaku/screens/ongaku_browse_page.dart';
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/screens/radio_stations_page.dart';

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

/// Library > Local Files.
GoRoute ongakuLocalFilesRoute(PushPageBuilder pushPage) => GoRoute(
  path: 'localFiles',
  pageBuilder: (context, state) =>
      pushPage(child: const LocalFilesPage(), state: state),
);

/// Ongaku's own tabs, appended after upstream's four branches so upstream's
/// branch indexes never move.
const ongakuBrowseBranchIndex = 4;
const ongakuRadioBranchIndex = 5;
const ongakuBrowsePath = '/browse';
const ongakuRadioPath = '/radio';

final _browseNavigatorKey = GlobalKey<NavigatorState>();
final _radioNavigatorKey = GlobalKey<NavigatorState>();

/// "Nouveautés" and "Radio" tabs. [rootPage] builds a tab's first page,
/// [sharedRoutes] are upstream's artist and album routes.
List<StatefulShellBranch> ongakuExtraBranches({
  required PushPageBuilder rootPage,
  required PushPageBuilder pushPage,
  required List<RouteBase> sharedRoutes,
}) => [
  StatefulShellBranch(
    navigatorKey: _browseNavigatorKey,
    routes: [
      GoRoute(
        path: ongakuBrowsePath,
        pageBuilder: (context, state) =>
            rootPage(child: const OngakuBrowsePage(), state: state),
        routes: [
          GoRoute(
            path: 'playlist/:playlistId',
            pageBuilder: (context, state) => pushPage(
              child: PlaylistPage(
                playlistId: state.pathParameters['playlistId'],
              ),
              state: state,
            ),
          ),
          ...sharedRoutes,
        ],
      ),
    ],
  ),
  StatefulShellBranch(
    navigatorKey: _radioNavigatorKey,
    routes: [
      GoRoute(
        path: ongakuRadioPath,
        pageBuilder: (context, state) =>
            rootPage(child: const RadioStationsPage(), state: state),
      ),
    ],
  ),
];
