# Ongaku

Apple Music style edition of [Musify](https://github.com/gokadzev/Musify) (GPL-3.0).
Same features and library as Musify, new interface, plus local file playback.
Layouts adapt to phones, foldables, tablets and desktops.

## How it stays in sync with Musify

All Ongaku code lives in **`lib/ongaku/`** (theme, shell, mini player, full-screen
player, local files, layout helpers, branding). Upstream files are only touched by
small hooks marked `Ongaku:` or importing `package:musify/ongaku/...`:

| File | Hook |
| --- | --- |
| `lib/main.dart` | `getOngakuTheme` / `getOngakuColorScheme` / `OngakuScrollBehavior`, name constants |
| `lib/services/router_service.dart` | `OngakuShell` instead of `BottomNavigationPage`, iOS page transitions, Local Files route |
| `lib/screens/library_page.dart` | "Local Files" row, large title |
| `lib/screens/search_page.dart` | large title |
| `lib/widgets/section_header.dart` | Ongaku section title, compact action buttons |
| `lib/services/common_services.dart` | 3 guards: local songs never call YouTube |
| `lib/utilities/mediaitem.dart` | carries local artwork/path through `MediaItem` |
| `lib/widgets/song_bar.dart` | shows local artwork |
| `lib/services/update_manager.dart` | update URLs point at Ongaku, not Musify |
| `lib/services/settings_manager.dart`, `lib/theme/app_colors.dart` | default accent (Apple red), system colors off |
| `lib/widgets/shapes/*` | squircle instead of cookie shapes |
| `lib/screens/{home,about}_page.dart`, `listening_recap_card.dart`, `linux_media_controls.dart` | app name |
| `android/`, `linux/`, `windows/` | app id `com.orikami.ongaku`, labels |
| `pubspec.yaml` | 3 dependencies (`# Ongaku`), Inter font |

Everything else (playback, YouTube extraction, library, playlists, stats, proxy,
equalizer, downloads...) is untouched Musify code, so upstream bug fixes and API
updates arrive unchanged.

```
scripts/sync_upstream.sh   # fetch + merge Musify, then verify
scripts/verify.sh          # analyze + tests + checks that every hook is still present
```

`.github/workflows/ongaku_sync.yml` does the same every day and opens a pull
request when Musify changed (or an issue if a hook conflicts). Merge it when green.
Upstream's own release workflows are left as they are to avoid merge conflicts:
disable them in the GitHub Actions settings of the repository.

## Local files

Library > Local Files: add files, or a folder (scanned recursively, rescanned on
open). Tags and cover art are read from the files (MP3/ID3, M4A, FLAC, OGG, ...),
with `Artist - Title` file names and `cover.jpg` as fallbacks. Local songs are normal
Musify songs (`ytid` starting with `local_`, with an `audioPath`), so queue, likes,
playlists, shuffle and offline mode work with them.

## Paused

Android Auto and the video mode. The Android Auto tabs (Recents, Library, Playlists, Up Next, with local files) are written in `lib/ongaku/services/ongaku_auto_browser.dart` but not enabled; to enable them, replace `AndroidAutoBrowser(this)` by `OngakuAutoBrowser(this)` in `lib/services/audio_service.dart`.

## Changing the name

Edit `lib/ongaku/brand.dart`, `android/app/build.gradle.kts` (`applicationId`),
the Android label, and the Linux/Windows titles.

## Layout, lyrics and lock screen (v3)

* `screens/ongaku_shell.dart`: 5 tabs (Home, New, Radio, Library, Search). Phone: mini player docked above the bar. Open foldable or tablet: tabs left, mini player right. `ongaku_routes.dart` adds branches 4 (New) and 5 (Radio) after upstream's four, so upstream indexes never move.
* `screens/ongaku_now_playing_page.dart`: full screen player on phones, right-hand panel on wide screens with lyrics filling the left side.
* `lyrics/synced_lyrics.dart`: .lrc next to a local file, then LRCLIB, then Musify's plain lyrics spread over the song.
* `theme/artwork_palette.dart` + `widgets/artwork_background.dart`: backgrounds take the colours of the current artwork.
* `services/ongaku_notification.dart`: lock screen buttons (favourite, previous, play, next, shuffle). Hooks in `audio_service.dart`: `_controls`, the three `androidCompactActionIndices` and `customAction`; one line in `main.dart`.
* Icon: `scripts/make_ongaku_icon.py <res dir> <out dir>`.

## v4

* Bar: Home, Library, Search, Settings. "You" is the round button on the Home title (route /home/you: stats + listening history). Recently played opens /home/recents as a pushed page.
* Settings are grouped by category (`settings_page.dart` `_buildCategories`); `CustomBar` and `SectionHeader` delegate to `widgets/ongaku_settings_ui.dart` and `ongaku_page_parts.dart`, so every list in the app shares the iOS look.
* Player: the old ⋯ menu is gone; its actions sit in the bottom row. The heart icon became a star everywhere (`FluentIcons.star_*`).
* Lyrics: wider LRCLIB search and a per-session timing nudge (± 0.5 s).

## v6

* Fixes: the notification buttons no longer read the global handler while it
  is being built (a `LateInitializationError` was logged at every start and
  broke upstream's desktop tests); the progress bar showed "LIVE" until a
  song's length was known; the player kept the previous song's colours when a
  song had no artwork; the times under the progress bar used the system font.
* Library and Search get the same large title as Home and Settings; long
  section titles shrink instead of being cut; the You page has a back chevron
  and a rounded history card; the accent colour swatch shows on every
  platform; local songs can be added to playlists from the player.
* `test/ongaku_screenshots_test.dart` renders every screen to PNG without a
  device (phone, open foldable, light and dark). Skipped by default:

  ```
  flutter test test/ongaku_screenshots_test.dart \
    --dart-define=ONGAKU_SHOTS=true --dart-define=ONGAKU_SHOTS_DIR=/tmp/shots
  ```
