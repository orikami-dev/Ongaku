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
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/home/you_stats.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Ongaku's colours for Replay: the icon's burgundy, pink and violet.
const _replayColors = [Color(0xFF5A1430), Color(0xFFE8264F), Color(0xFF6E44E8)];

/// "Vous": a Replay of the chosen month (minutes, songs, artists, plays),
/// top artists, top songs and the minutes month by month. Musify's
/// listening statistics, shown the Ongaku way.
class OngakuYouPage extends StatefulWidget {
  const OngakuYouPage({super.key});

  @override
  State<OngakuYouPage> createState() => _OngakuYouPageState();
}

class _OngakuYouPageState extends State<OngakuYouPage> {
  String _monthKey = listeningStatsMonthKey(DateTime.now());
  bool _allSongs = false;

  MonthListening _month(String key) => MonthListening(
    monthDisplayMinutes(listeningStatsService.monthStats(key)),
    listeningStatsService.monthTopSongs(key, limit: 200),
  );

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    return Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: wrappedEnabled,
        builder: (context, enabled, _) {
          final current = listeningStatsMonthKey(DateTime.now());
          final keys = {current, ...listeningStatsService.availableMonthKeys}
              .toList()
            ..sort((a, b) => b.compareTo(a));
          if (!keys.contains(_monthKey)) _monthKey = current;
          final month = _month(_monthKey);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: OngakuLargeTitle(title: strings.you, showBack: true),
              ),
              if (!enabled)
                SliverToBoxAdapter(
                  child: _Message(
                    text: strings.statsOff,
                    action: strings.openSettings,
                    onAction: () => context.go('/settings'),
                  ),
                )
              else ...[
                if (keys.length > 1)
                  SliverToBoxAdapter(
                    child: _MonthChips(
                      keys: keys,
                      selected: _monthKey,
                      onSelected: (key) => setState(() {
                        _monthKey = key;
                        _allSongs = false;
                      }),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _ReplayCard(monthKey: _monthKey, month: month),
                ),
                if (month.isEmpty)
                  SliverToBoxAdapter(child: _Message(text: strings.statsEmpty))
                else ...[
                  if (month.artists.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: OngakuSectionTitle(title: strings.topArtists),
                    ),
                    SliverToBoxAdapter(child: _TopArtists(month: month)),
                  ],
                  SliverToBoxAdapter(
                    child: OngakuSectionTitle(title: strings.topSongs),
                  ),
                  SliverToBoxAdapter(
                    child: _TopSongs(
                      month: month,
                      title: formatMonthPeriodLabel(
                        Localizations.localeOf(context),
                        _monthKey,
                      ),
                      all: _allSongs,
                      onShowAll: () => setState(() => _allSongs = true),
                    ),
                  ),
                ],
                if (keys.length > 1) ...[
                  SliverToBoxAdapter(
                    child: OngakuSectionTitle(title: strings.monthByMonth),
                  ),
                  SliverToBoxAdapter(
                    child: _MonthBars(
                      minutes: {
                        for (final key in keys.take(12))
                          key: monthDisplayMinutes(
                            listeningStatsService.monthStats(key),
                          ),
                      },
                      selected: _monthKey,
                      onSelected: (key) => setState(() {
                        _monthKey = key;
                        _allSongs = false;
                      }),
                    ),
                  ),
                ],
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }
}

/// Months that have statistics, newest first.
class _MonthChips extends StatelessWidget {
  const _MonthChips({
    required this.keys,
    required this.selected,
    required this.onSelected,
  });

  final List<String> keys;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final locale = Localizations.localeOf(context);
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(margin, 12, margin, 4),
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = keys[index];
          final isSelected = key == selected;
          return GestureDetector(
            onTap: () => onSelected(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                formatMonthPeriodLabel(locale, key),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The month's Replay: minutes in large, then songs, artists and plays.
class _ReplayCard extends StatelessWidget {
  const _ReplayCard({required this.monthKey, required this.month});

  final String monthKey;
  final MonthListening month;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);
    final label = formatMonthPeriodLabel(
      Localizations.localeOf(context),
      monthKey,
    );
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _replayColors,
              stops: [0, 0.6, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Replay',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  number.format(month.minutes),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontSize: 64,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.minutesListened,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Figure(number.format(month.songs.length), strings.statSongs),
                    const SizedBox(width: 10),
                    _Figure(
                      number.format(month.artists.length),
                      strings.statArtists,
                    ),
                    const SizedBox(width: 10),
                    _Figure(number.format(month.plays), strings.statPlays),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round artworks of the artists heard most, with their minutes.
class _TopArtists extends StatelessWidget {
  const _TopArtists({required this.month});

  final MonthListening month;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final artists = month.artists.take(10).toList();
    const size = 104.0;
    return OngakuShelf(
      height: size + 58,
      itemWidth: size,
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return Column(
          children: [
            ClipOval(
              child: SongArtworkWidget(
                metadata: mapToMediaItem(artist.song),
                size: size,
                borderRadius: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${index + 1}. ${artist.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              strings.minShort(
                (artist.seconds / Duration.secondsPerMinute).ceil(),
              ),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Numbered list of the month's songs; a tap plays from that song.
class _TopSongs extends StatelessWidget {
  const _TopSongs({
    required this.month,
    required this.title,
    required this.all,
    required this.onShowAll,
  });

  final MonthListening month;
  final String title;
  final bool all;
  final VoidCallback onShowAll;

  static const _shown = 10;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final songs = month.songs;
    final count = all ? songs.length : songs.length.clamp(0, _shown);
    final playlist = {'title': 'Replay · $title', 'list': songs};

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => audioHandler.playPlaylistSong(
                playlist: playlist,
                songIndex: i,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: i < 3
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.45),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SongArtworkWidget(
                      metadata: mapToMediaItem(songs[i]),
                      size: 52,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            songs[i]['title']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            songs[i]['artist']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.playCount(_plays(songs[i])),
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!all && songs.length > _shown)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onShowAll,
                child: Text(strings.showAllSongs(songs.length)),
              ),
            ),
        ],
      ),
    );
  }

  static int _plays(Map song) =>
      int.tryParse(song['playCount']?.toString() ?? '') ?? 0;
}

/// Minutes per month as bars, the chosen month in the accent colour.
class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.minutes,
    required this.selected,
    required this.onSelected,
  });

  /// Newest first.
  final Map<String, int> minutes;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final locale = Localizations.localeOf(context).toString();
    final entries = minutes.entries.toList().reversed.toList();
    final top = entries.fold(1, (m, e) => e.value > m ? e.value : m);
    const barArea = 120.0;

    String shortMonth(String key) {
      final parts = key.split('-');
      final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat.MMM(locale).format(date);
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final entry in entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 6 + (barArea - 6) * entry.value / top,
                        decoration: BoxDecoration(
                          color: entry.key == selected
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shortMonth(entry.key),
                        maxLines: 1,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: entry.key == selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final margin = ongakuPageMargin(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 24, margin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.6,
              ),
              fontSize: 15,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
