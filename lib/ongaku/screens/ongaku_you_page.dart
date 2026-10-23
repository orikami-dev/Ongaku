/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/ongaku/widgets/ongaku_settings_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/widgets/listening_recap_card.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/song_bar.dart';

/// "Vous": this month's listening statistics, then the listening history.
/// One tap on the round button of the home screen opens it.
class OngakuYouPage extends StatelessWidget {
  const OngakuYouPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: OngakuLargeTitle(title: strings.you, showBack: true),
          ),
          SliverToBoxAdapter(child: _Stats(strings: strings)),
          SliverToBoxAdapter(
            child: OngakuSectionTitle(title: strings.listeningHistory),
          ),
          ValueListenableBuilder<List>(
            valueListenable: userRecentlyPlayed,
            builder: (context, songs, _) {
              if (songs.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(margin),
                    child: Text(
                      context.l10n!.recentlyPlayedMsg,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                );
              }
              final history = songs.whereType<Map>().toList();
              final playlist = {
                'title': context.l10n!.recentlyPlayed,
                'list': history,
              };
              // Same rounded card as the settings groups.
              return SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: SliverToBoxAdapter(
                  child: ClipRSuperellipse(
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      children: [
                        for (var index = 0; index < history.length; index++)
                          SongBar(
                            history[index],
                            true,
                            key: ValueKey(
                              'you_${history[index]['ytid']}_$index',
                            ),
                            onPlay: () => audioHandler.playPlaylistSong(
                              playlist: playlist,
                              songIndex: index,
                            ),
                            isRecentSong: true,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SliverMiniPlayerBottomSpace(),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.strings});

  final OngakuStrings strings;

  @override
  Widget build(BuildContext context) {
    final margin = ongakuPageMargin(context);
    final monthKey = listeningStatsMonthKey(DateTime.now());
    final stats = listeningStatsService.monthStats(monthKey);
    final songs = listeningStatsService.monthTopSongs(monthKey);
    final minutes = monthDisplayMinutes(stats);
    final preview = songs.take(wrappedShareSongsLimit).toList();

    return ValueListenableBuilder<bool>(
      valueListenable: wrappedEnabled,
      builder: (context, enabled, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OngakuSectionTitle(title: strings.thisMonth),
          if (enabled && (minutes > 0 || preview.isNotEmpty))
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
          Padding(
            padding: EdgeInsets.fromLTRB(margin, 14, margin, 0),
            child: OngakuSettingsGroup(
              title: '',
              tint: const Color(0xFFFF2D55),
              children: [
                OngakuSettingsRow(
                  title: strings.allStats,
                  icon: Icons.insights_rounded,
                  onTap: () => context.push('/home/timeMachine'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
