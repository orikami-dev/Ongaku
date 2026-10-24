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
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/database/playlists.db.dart';
import 'package:musify/database/radio_stations.db.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/home/home_shelves.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/services/artist_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/announcement_box.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Apple Music "Accueil", laid out like the app: a small title that settles
/// in the top bar on scroll, "Pour vous" tall cards, recently played,
/// "Plus de : artist" shelves, themed playlist shelves, radios, your
/// playlists and Replay. Same data and actions as Musify's home.
class OngakuHomePage extends StatefulWidget {
  const OngakuHomePage({super.key});

  @override
  State<OngakuHomePage> createState() => _OngakuHomePageState();
}

class _OngakuHomePageState extends State<OngakuHomePage> {
  late final Future<List> _suggestedPlaylistsFuture = getPlaylists(
    playlistsNum: recommendedCubesNumber,
  );
  late Future<List> _recommendedSongsFuture = getRecommendedSongs();
  late final Future<List<Map<String, dynamic>>> _artistsFuture = _loadArtists();
  final _scrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    externalRecommendations.addListener(_refreshRecommendedSongs);
  }

  @override
  void dispose() {
    externalRecommendations.removeListener(_refreshRecommendedSongs);
    _scrolled.dispose();
    super.dispose();
  }

  void _refreshRecommendedSongs() {
    if (!mounted) return;
    setState(() => _recommendedSongsFuture = getRecommendedSongs());
  }

  /// The two artists heard most in the recently played songs, with their
  /// releases, for the "Plus de :" shelves.
  Future<List<Map<String, dynamic>>> _loadArtists() async {
    if (offlineMode.value) return const [];
    final picks = topRecentArtists(userRecentlyPlayed.value, count: 2);
    final profiles = await Future.wait(
      picks.map(
        (pick) => getArtistProfile(pick.id, preferredName: pick.name).catchError(
          (_) => null,
        ),
      ),
    );
    return [
      for (final profile in profiles)
        if (profile != null && (profile['releases'] as List? ?? []).isNotEmpty)
          profile,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    const barHeight = 48.0;

    return Scaffold(
      body: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (n.depth == 0) _scrolled.value = n.metrics.pixels > 64;
              return false;
            },
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: topInset + barHeight - 12),
                ),
                SliverToBoxAdapter(
                  child: OngakuLargeTitle(
                    title: l10n.home,
                    includeStatusBar: false,
                    trailing: const OngakuYouButton(),
                  ),
                ),
                SliverToBoxAdapter(child: _announcement(context)),
                SliverToBoxAdapter(
                  child: OngakuSectionTitle(title: strings.forYou),
                ),
                SliverToBoxAdapter(child: _forYouShelf(context)),
                SliverToBoxAdapter(child: _recentlyPlayed(context)),
                SliverToBoxAdapter(child: _artistShelf(context, 0)),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.moods),
                ),
                SliverToBoxAdapter(child: _radios(context)),
                SliverToBoxAdapter(child: _artistShelf(context, 1)),
                SliverToBoxAdapter(child: _yourPlaylists(context)),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.charts),
                ),
                SliverToBoxAdapter(child: _recommended(context)),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.hipHop),
                ),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.party),
                ),
                SliverToBoxAdapter(child: _albums(context)),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.rock),
                ),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.world),
                ),
                SliverToBoxAdapter(
                  child: _themeShelf(context, PlaylistTheme.other),
                ),
                SliverToBoxAdapter(child: _replay(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
          _TopBar(
            title: l10n.home,
            scrolled: _scrolled,
            height: topInset + barHeight,
            onRefresh: () {
              _refreshRecommendedSongs();
              showToast(context, OngakuStrings.of(context).refreshed);
            },
          ),
        ],
      ),
    );
  }

  Widget _announcement(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: announcementURL,
      builder: (_, url, __) {
        if (url == null) return const SizedBox.shrink();
        final sponsorship = isSponsorshipAnnouncementUrl(url);
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ongakuPageMargin(context) - 8,
          ),
          child: AnnouncementBox(
            message: sponsorship
                ? context.l10n!.sponsorProject
                : context.l10n!.newAnnouncement,
            url: url,
            icon: sponsorship
                ? FluentIcons.star_24_filled
                : FluentIcons.megaphone_24_filled,
            onDismiss: () async => announcementURL.value = null,
          ),
        );
      },
    );
  }

  ({double width, double height}) _tallSize(BuildContext context) {
    final width = ongakuShelfItemWidth(context, phone: 1.5, wide: 3.15);
    final height = (width * 1.33).clamp(
      240.0,
      MediaQuery.sizeOf(context).height * 0.58,
    );
    return (width: width, height: height);
  }

  /// Liked playlists first ("listen again"), then Musify's suggestions.
  Widget _forYouShelf(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final l10n = context.l10n!;
    final size = _tallSize(context);

    return ValueListenableBuilder<List<Map>>(
      valueListenable: userLikedPlaylists,
      builder: (context, liked, _) {
        return FutureBuilder<List>(
          future: _suggestedPlaylistsFuture,
          builder: (context, snapshot) {
            final favourites = liked
                .where((p) => !isArtistPlaylist(p))
                .take(recommendedCubesNumber)
                .map((p) => (p, strings.listenAgain));
            final suggested = (snapshot.data ?? const []).whereType<Map>().map(
              (p) =>
                  (p, p['isAlbum'] == true ? l10n.album : strings.madeForYou),
            );
            final items = [...favourites, ...suggested];

            if (items.isEmpty) {
              return SizedBox(
                height: size.height,
                child: snapshot.connectionState == ConnectionState.done
                    ? null
                    : const Center(child: CircularProgressIndicator()),
              );
            }

            return OngakuShelf(
              height: size.height,
              itemWidth: size.width,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final (playlist, caption) = items[index];
                return OngakuTallCard(
                  image: playlist['image']?.toString(),
                  caption: caption,
                  title: playlist['title']?.toString() ?? '',
                  subtitle: playlist['artist']?.toString(),
                  onTap: () =>
                      context.push('/home/playlist/${playlist['ytid']}'),
                );
              },
            );
          },
        );
      },
    );
  }

  double _squareWidth(BuildContext context) =>
      ongakuShelfItemWidth(context, phone: 2.3, wide: 4.6);

  /// "Écoutés récemment": the favourite songs first, as in Apple Music,
  /// then the songs played last.
  Widget _recentlyPlayed(BuildContext context) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);
    final width = _squareWidth(context);
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<List>(
      valueListenable: userRecentlyPlayed,
      builder: (context, songs, _) {
        final shown = songs.take(20).toList();
        return ValueListenableBuilder<List>(
          valueListenable: userLikedSongsList,
          builder: (context, liked, _) {
            final hasLiked = liked.isNotEmpty;
            if (shown.isEmpty && !hasLiked) return const SizedBox.shrink();
            final offset = hasLiked ? 1 : 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OngakuSectionTitle(
                  title: strings.recentlyPlayed,
                  onTap: () => context.push('/home/recents'),
                ),
                OngakuShelf(
                  height: width + 48,
                  itemWidth: width,
                  itemCount: shown.length + offset,
                  itemBuilder: (context, index) {
                    if (hasLiked && index == 0) {
                      return OngakuSquareTile(
                        artwork: ColoredBox(
                          color: colorScheme.onSurface.withValues(alpha: 0.07),
                          child: Center(
                            child: Icon(
                              Icons.star_rounded,
                              size: width * 0.55,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        title: l10n.likedSongs,
                        onTap: () => context.push('/home/liked'),
                      );
                    }
                    final song = shown[index - offset] as Map;
                    return OngakuSquareTile(
                      artwork: LayoutBuilder(
                        builder: (context, c) => SongArtworkWidget(
                          metadata: mapToMediaItem(song),
                          size: c.maxWidth,
                          borderRadius: 0,
                        ),
                      ),
                      title: song['title']?.toString() ?? '',
                      subtitle: song['artist']?.toString(),
                      onTap: () => audioHandler.playPlaylistSong(
                        playlist: {'title': l10n.recentlyPlayed, 'list': shown},
                        songIndex: index - offset,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// "Plus de : artist": the releases of an artist heard recently.
  Widget _artistShelf(BuildContext context, int position) {
    final width = _squareWidth(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _artistsFuture,
      builder: (context, snapshot) {
        final artists = snapshot.data ?? const [];
        if (artists.length <= position) return const SizedBox.shrink();
        final artist = artists[position];
        final releases = (artist['releases'] as List).whereType<Map>().toList();
        final artistId = artist['ytid']?.toString() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuArtistSectionTitle(
              label: OngakuStrings.of(context).moreBy,
              name: artist['title']?.toString() ?? '',
              image: artist['image']?.toString(),
              onTap: () => context.push(
                NavigationManager.artistPath(context, artistId),
                extra: artist,
              ),
            ),
            OngakuShelf(
              height: width + 48,
              itemWidth: width,
              itemCount: releases.length,
              itemBuilder: (context, index) {
                final release = releases[index];
                return OngakuSquareTile(
                  artwork: OngakuCoverImage(release['image']?.toString()),
                  title: release['title']?.toString() ?? '',
                  subtitle:
                      release['artist']?.toString() ??
                      release['year']?.toString(),
                  onTap: () => context.push(
                    NavigationManager.albumPath(
                      context,
                      release['ytid']?.toString() ?? '',
                    ),
                    extra: release,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// A shelf of Musify's playlists on one theme.
  Widget _themeShelf(BuildContext context, PlaylistTheme theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: offlineMode,
      builder: (context, offline, _) {
        if (offline) return const SizedBox.shrink();
        final items = playlistsForTheme(playlistsDB, theme);
        if (items.isEmpty) return const SizedBox.shrink();
        final width = _squareWidth(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(
              title: OngakuStrings.of(context).themeTitle(theme),
              shrinkToFit: true,
            ),
            OngakuShelf(
              height: width + 30,
              itemWidth: width,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final playlist = items[index];
                return OngakuSquareTile(
                  artwork: OngakuCoverImage(playlist['image']?.toString()),
                  title: playlist['title']?.toString() ?? '',
                  onTap: () =>
                      context.push('/home/playlist/${playlist['ytid']}'),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Musify's album list, as a shelf.
  Widget _albums(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: offlineMode,
      builder: (context, offline, _) {
        if (offline) return const SizedBox.shrink();
        final albums = playlists
            .where((p) => p['isAlbum'] == true)
            .take(24)
            .toList();
        if (albums.isEmpty) return const SizedBox.shrink();
        final width = _squareWidth(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(title: OngakuStrings.of(context).essentialAlbums),
            OngakuShelf(
              height: width + 48,
              itemWidth: width,
              itemCount: albums.length,
              itemBuilder: (context, index) {
                final album = albums[index];
                return OngakuSquareTile(
                  artwork: OngakuCoverImage(album['image']?.toString()),
                  title: album['title']?.toString() ?? '',
                  subtitle: album['artist']?.toString(),
                  onTap: () => context.push('/home/playlist/${album['ytid']}'),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Radio stations, liked ones first; a tap starts the stream.
  Widget _radios(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: offlineMode,
      builder: (context, offline, _) {
        if (offline || radioStationsDB.isEmpty) return const SizedBox.shrink();
        final strings = OngakuStrings.of(context);
        final liked = userLikedRadioStations.value.toSet();
        final stations = [...radioStationsDB]
          ..sort(
            (a, b) =>
                (liked.contains(b.id) ? 1 : 0) - (liked.contains(a.id) ? 1 : 0),
          );
        final shown = stations.take(16).toList();
        final width = _squareWidth(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(
              title: strings.radios,
              onTap: () => context.push('/library/radioStations'),
            ),
            OngakuShelf(
              height: width + 48,
              itemWidth: width,
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final station = shown[index];
                return OngakuSquareTile(
                  artwork: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(width * 0.12),
                      child: OngakuCoverImage(station.image, fit: BoxFit.contain),
                    ),
                  ),
                  title: station.name,
                  subtitle: strings.radioStation,
                  onTap: () async {
                    final ok = await audioHandler.playRadioStream(
                      id: station.id,
                      name: station.name,
                      streamUrl: station.streamUrl,
                      image: station.image,
                      genre: station.genre,
                    );
                    if (!ok && context.mounted) {
                      showToast(context, context.l10n!.error);
                    }
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// The user's own playlists (created or imported) as tall cards.
  Widget _yourPlaylists(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final size = _tallSize(context);
    return ValueListenableBuilder<List>(
      valueListenable: userCustomPlaylists,
      builder: (context, custom, _) {
        final items = custom.whereType<Map>().toList().reversed.toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(
              title: strings.yourPlaylists,
              onTap: () => context.go('/library'),
            ),
            OngakuShelf(
              height: size.height,
              itemWidth: size.width,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final playlist = items[index];
                final count = (playlist['list'] as List?)?.length ?? 0;
                return OngakuTallCard(
                  image: playlist['image']?.toString(),
                  caption: strings.songCount(count),
                  title: playlist['title']?.toString() ?? '',
                  onTap: () =>
                      context.push('/home/playlist/${playlist['ytid']}'),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Musify's suggested songs, as a shelf.
  Widget _recommended(BuildContext context) {
    return FutureBuilder<List>(
      future: _recommendedSongsFuture,
      builder: (context, snapshot) {
        final data = (snapshot.data ?? const []).whereType<Map>().toList();
        if (data.isEmpty) return const SizedBox.shrink();
        final width = _squareWidth(context);
        final title = context.l10n!.recommendedForYou;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(title: title),
            OngakuShelf(
              height: width + 48,
              itemWidth: width,
              itemCount: data.length,
              itemBuilder: (context, index) {
                final song = data[index];
                return OngakuSquareTile(
                  artwork: LayoutBuilder(
                    builder: (context, c) => SongArtworkWidget(
                      metadata: mapToMediaItem(song),
                      size: c.maxWidth,
                      borderRadius: 0,
                    ),
                  ),
                  title: song['title']?.toString() ?? '',
                  subtitle: song['artist']?.toString(),
                  onTap: () => audioHandler.playPlaylistSong(
                    playlist: {'title': title, 'list': data},
                    songIndex: index,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// "Replay : votre classement musical": this month and the history.
  Widget _replay(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: wrappedEnabled,
      builder: (context, enabled, __) {
        if (!enabled) return const SizedBox.shrink();
        final strings = OngakuStrings.of(context);
        final monthKey = listeningStatsMonthKey(DateTime.now());
        final stats = listeningStatsService.monthStats(monthKey);
        final top = listeningStatsService.monthTopSongs(monthKey);
        final minutes = monthDisplayMinutes(stats);
        final hasMonth = minutes > 0 || top.isNotEmpty;
        final hasHistory = userRecentlyPlayed.value.isNotEmpty;
        if (!hasMonth && !hasHistory) return const SizedBox.shrink();

        final size = _tallSize(context);
        final month = formatMonthPeriodLabel(
          Localizations.localeOf(context),
          monthKey,
        );
        final artists = top
            .map((s) => s['artist']?.toString() ?? '')
            .where((a) => a.isNotEmpty)
            .toSet()
            .take(3)
            .join(', ');
        final cards = [
          if (hasMonth)
            OngakuReplayCard(
              title: strings.replayMonth(month),
              caption: strings.minShort(minutes),
              subtitle: artists,
              colors: const [
                Color(0xFFF7B733),
                Color(0xFF6EE7C7),
                Color(0xFFB45AA0),
                Color(0xFFE94E77),
              ],
              onTap: () => context.push('/home/you'),
            ),
          if (hasHistory)
            OngakuReplayCard(
              title: strings.replayHistory,
              caption: context.l10n!.recentlyPlayed,
              subtitle: userRecentlyPlayed.value
                  .whereType<Map>()
                  .map((s) => s['artist']?.toString() ?? '')
                  .where((a) => a.isNotEmpty)
                  .toSet()
                  .take(3)
                  .join(', '),
              colors: const [
                Color(0xFF5B4FD6),
                Color(0xFF3FA7D6),
                Color(0xFFE8456B),
                Color(0xFFE8456B),
              ],
              onTap: () => context.push('/home/recents'),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(title: strings.replayTitle),
            OngakuShelf(
              height: size.height,
              itemWidth: size.width,
              itemCount: cards.length,
              itemBuilder: (context, index) => cards[index],
            ),
          ],
        );
      },
    );
  }
}

/// Top bar: transparent with the menu button at first, then the small page
/// title on the page colour once the large title has scrolled away.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.scrolled,
    required this.height,
    required this.onRefresh,
  });

  final String title;
  final ValueNotifier<bool> scrolled;
  final double height;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      builder: (context, isScrolled, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: height,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top,
            left: margin,
            right: margin - 12,
          ),
          decoration: BoxDecoration(
            color: isScrolled
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
          ),
          child: Row(
            children: [
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isScrolled ? 1 : 0,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              _HomeMenu(onRefresh: onRefresh),
            ],
          ),
        );
      },
    );
  }
}

enum _MenuAction { refresh, history, mix }

/// The "⋮" menu of the home page: fresh recommendations, the listening
/// history and a shuffled mix of the liked songs and local files.
class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.onRefresh});

  final VoidCallback onRefresh;

  Future<void> _playMix(BuildContext context) async {
    final seen = <String>{};
    final songs = <Map>[
      for (final song in [...userLikedSongsList.value, ...localSongs.value])
        if (song is Map && seen.add(song['ytid']?.toString() ?? '')) song,
    ]..shuffle();
    if (songs.isEmpty) {
      showToast(context, OngakuStrings.of(context).nothingToMix);
      return;
    }
    await audioHandler.addPlaylistToQueue(songs, replace: true, startIndex: 0);
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    return PopupMenuButton<_MenuAction>(
      icon: Icon(
        Icons.more_vert_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      onSelected: (action) => switch (action) {
        _MenuAction.refresh => onRefresh(),
        _MenuAction.history => context.push('/home/recents'),
        _MenuAction.mix => _playMix(context),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _MenuAction.refresh,
          child: _MenuRow(Icons.refresh_rounded, strings.refreshRecommendations),
        ),
        PopupMenuItem(
          value: _MenuAction.history,
          child: _MenuRow(Icons.history_rounded, strings.listeningHistory),
        ),
        PopupMenuItem(
          value: _MenuAction.mix,
          child: _MenuRow(Icons.shuffle_rounded, strings.shuffleMix),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
