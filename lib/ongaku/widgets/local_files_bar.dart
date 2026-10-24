/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/ongaku_routes.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/widgets/playlist_bar.dart';

/// Library row opening the local files screen, styled like its neighbours.
Widget ongakuLocalFilesBar(
  BuildContext context, {
  BorderRadius borderRadius = BorderRadius.zero,
}) {
  return PlaylistBar(
    OngakuStrings.of(context).localFiles,
    onPressed: () => NavigationManager.router.go(localFilesPath),
    cubeIcon: FluentIcons.folder_open_24_regular,
    borderRadius: borderRadius,
    showBuildActions: false,
  );
}

/// The "All Songs" row of the Library tab.
Widget ongakuAllSongsBar(BuildContext context) {
  return PlaylistBar(
    OngakuStrings.of(context).allSongs,
    onPressed: () => NavigationManager.router.go(allSongsPath),
    cubeIcon: FluentIcons.music_note_2_24_regular,
    showBuildActions: false,
  );
}
