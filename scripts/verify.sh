#!/usr/bin/env bash
# Checks that Ongaku still works after a change or an upstream merge.
set -euo pipefail

flutter pub get
flutter analyze
flutter test

# Every Ongaku hook in upstream files must still be there.
missing=0
check() { grep -q "$2" "$1" || { echo "MISSING HOOK in $1: $2"; missing=1; }; }
check lib/main.dart "getOngakuTheme"
check lib/main.dart "getOngakuColorScheme"
check lib/services/router_service.dart "OngakuShell"
check lib/services/router_service.dart "ongakuLocalFilesRoute"
check lib/services/router_service.dart "ongakuPushPage"
check lib/screens/library_page.dart "ongakuLocalFilesBar"
check lib/screens/library_page.dart "OngakuLargeTitle"
check lib/screens/search_page.dart "OngakuLargeTitle"
check lib/services/audio_service.dart "ongakuControls"
check lib/services/common_services.dart "isLocalSongId"
check lib/utilities/mediaitem.dart "isLocal"
check lib/services/update_manager.dart "updateCheckUrl"
check lib/screens/settings_page.dart "ongakuClosePicker"
check lib/screens/settings_page.dart "import-deezer-playlist"
check lib/services/router_service.dart "ongakuImportRoutes"
check lib/services/router_service.dart "ongakuLikedRoute"
check lib/screens/settings_page.dart "ongakuAccentSheet"
check lib/screens/settings_page.dart "OngakuSponsorCards"
check lib/screens/about_page.dart "OngakuAboutHeader"
check lib/utilities/flutter_bottom_sheet.dart "showDragHandle: false"
check lib/widgets/playlist_hero_artwork.dart "Ongaku"
check lib/widgets/confirmation_dialog.dart "onError"
check android/app/build.gradle.kts "com.orikami.ongaku"
check lib/main.dart "ongakuStartSound"
check lib/services/router_service.dart "ongakuSoundRoutes"
check lib/services/router_service.dart "applicationVersion: ongakuVersion"
check lib/screens/settings_page.dart "/settings/sound"
check lib/screens/settings_page.dart "equalizer is replaced by Son calibré"
check pubspec.yaml "ongaku_sound"
check lib/main.dart "ongakuWatchPaletteIcon"
check lib/main.dart "OngakuSystemBars"
check lib/services/update_manager.dart "isLatestVersionHigher(ongakuVersion"
check lib/utilities/flutter_toast.dart "ongakuToastAnimation"
check lib/screens/settings_page.dart "ongakuCheckUpdatesNow"
check lib/screens/settings_page.dart "import-soundcloud-playlist"
check lib/widgets/playlist_page/like_button.dart "Ongaku: the theme tints icon buttons"
check lib/screens/settings_page.dart "OngakuPalettePicker"
check android/app/src/main/AndroidManifest.xml "com.orikami.ongaku.palette.ongaku"
check lib/widgets/playlist_page/playlist_sliver_app_bar.dart "OngakuPlaylistSpace"
check lib/widgets/playlist_page/playlist_header.dart "OngakuChipRow"
check lib/screens/playlist_page.dart "actions: \["
check lib/screens/artist_page.dart "actions: \["
check lib/services/router_service.dart "ongakuAllSongsRoute"
check lib/screens/library_page.dart "ongakuAllSongsBar"
check lib/services/router_service.dart "OngakuLibraryPage()"
check lib/services/router_service.dart "ongakuLibraryRoutes"
check lib/screens/library_page.dart "ongakuPlaylistsOnly"
check lib/widgets/song_bar.dart "OngakuSwipeToLike("
check lib/screens/search_page.dart "OngakuSearchHistoryHeader()"
check lib/screens/settings_page.dart "live on the Statistiques"
check lib/services/audio_service.dart "OngakuAutoBrowser(this)"
python3 scripts/brand_strings.py --check || missing=1
[ "$missing" = 0 ] || { echo "An upstream change removed an Ongaku hook: re-apply it (see ONGAKU.md)."; exit 1; }
echo "OK"
