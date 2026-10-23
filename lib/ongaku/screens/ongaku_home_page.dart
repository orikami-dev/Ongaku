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
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/announcement_box.dart';
import 'package:musify/widgets/listening_recap_card.dart';
import 'package:musify/widgets/recommended_songs_section.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Apple Music "Accueil": large title, "Pour vous" tall cards, recently
/// played, then recommendations. Same data and actions as Musify's home.
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

  @override
  void initState() {
    super.initState();
    externalRecommendations.addListener(_refreshRecommendedSongs);
  }

  @override
  void dispose() {
    externalRecommendations.removeListener(_refreshRecommendedSongs);
    super.dispose();
  }

  void _refreshRecommendedSongs() {
    if (!mounted) return;
    setState(() => _recommendedSongsFuture = getRecommendedSongs());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: OngakuLargeTitle(title: l10n.home)),
          SliverToBoxAdapter(child: _announcement(context)),
          SliverToBoxAdapter(child: OngakuSectionTitle(title: strings.forYou)),
          SliverToBoxAdapter(child: _forYouShelf(context)),
          SliverToBoxAdapter(child: _recentlyPlayed(context)),
          SliverToBoxAdapter(child: _recap(context)),
          SliverToBoxAdapter(child: _recommended(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
                ? FluentIcons.heart_24_filled
                : FluentIcons.megaphone_24_filled,
            onDismiss: () async => announcementURL.value = null,
          ),
        );
      },
    );
  }

  /// Liked playlists first ("listen again"), then Musify's suggestions.
  Widget _forYouShelf(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final l10n = context.l10n!;
    final width = ongakuShelfItemWidth(context, phone: 1.45, wide: 3.15);
    final height = (width * 1.33).clamp(
      240.0,
      MediaQuery.sizeOf(context).height * 0.55,
    );

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
                height: height,
                child: snapshot.connectionState == ConnectionState.done
                    ? null
                    : const Center(child: CircularProgressIndicator()),
              );
            }

            return OngakuShelf(
              height: height,
              itemWidth: width,
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

  Widget _recentlyPlayed(BuildContext context) {
    final l10n = context.l10n!;
    final width = ongakuShelfItemWidth(context, phone: 2.3, wide: 4.6);

    return ValueListenableBuilder<List>(
      valueListenable: userRecentlyPlayed,
      builder: (context, songs, _) {
        if (songs.isEmpty) return const SizedBox.shrink();
        final shown = songs.take(20).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(
              title: l10n.recentlyPlayed,
              onTap: () => context.go('/library/userSongs/recents'),
            ),
            OngakuShelf(
              height: width + 48,
              itemWidth: width,
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final song = shown[index] as Map;
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

  Widget _recap(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: wrappedEnabled,
      builder: (context, enabled, __) {
        if (!enabled) return const SizedBox.shrink();
        final monthKey = listeningStatsMonthKey(DateTime.now());
        final stats = listeningStatsService.monthStats(monthKey);
        final songs = listeningStatsService.monthTopSongs(monthKey);
        final minutes = monthDisplayMinutes(stats);
        if (minutes <= 0 && songs.isEmpty) return const SizedBox.shrink();

        final preview = songs.take(wrappedShareSongsLimit).toList();
        final margin = ongakuPageMargin(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OngakuSectionTitle(
              title: context.l10n!.timeMachine,
              onTap: () => context.push('/home/timeMachine'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: margin - 8),
              child: ListeningRecapCard(
                periodLabel: formatMonthPeriodLabel(
                  Localizations.localeOf(context),
                  monthKey,
                ),
                minutes: minutes,
                songs: preview,
                onSongTap: (index) => audioHandler.playPlaylistSong(
                  playlist: {
                    'title': context.l10n!.timeMachine,
                    'list': preview,
                  },
                  songIndex: index,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _recommended(BuildContext context) {
    return FutureBuilder<List>(
      future: _recommendedSongsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const [];
        if (data.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ongakuPageMargin(context) - 10,
          ),
          child: RecommendedSongsSection(
            title: context.l10n!.recommendedForYou,
            songs: data,
            listKeyPrefix: 'home_recommended',
          ),
        );
      },
    );
  }
}
