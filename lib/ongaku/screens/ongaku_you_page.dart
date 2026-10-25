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
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/home/you_stats.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/ongaku/widgets/ongaku_settings_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/song_artwork.dart';
import 'package:musify/widgets/song_bar.dart';

/// Ongaku's colours for Replay: the icon's burgundy, pink and violet.
const _replayColors = [Color(0xFF5A1430), Color(0xFFE8264F), Color(0xFF6E44E8)];

/// "Statistiques d'écoute" (formerly "Vous"). Résumé: a Replay of the
/// chosen month (minutes, songs, artists, plays), top artists, top songs,
/// the minutes month by month and the statistics' settings. Historique:
/// the listening history. Musify's data, shown the Ongaku way.
class OngakuYouPage extends StatefulWidget {
  const OngakuYouPage({super.key});

  @override
  State<OngakuYouPage> createState() => _OngakuYouPageState();
}

enum _YouTab { summary, history }

class _OngakuYouPageState extends State<OngakuYouPage> {
  String _monthKey = listeningStatsMonthKey(DateTime.now());
  bool _allSongs = false;
  _YouTab _tab = _YouTab.summary;

  MonthListening _month(String key) => MonthListening(
    monthDisplayMinutes(listeningStatsService.monthStats(key)),
    listeningStatsService.monthTopSongs(key, limit: 200),
  );

  void _selectMonth(String key) => setState(() {
    _monthKey = key;
    _allSongs = false;
  });

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    return Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: wrappedEnabled,
        builder: (context, enabled, _) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: OngakuLargeTitle(
                  title: strings.statsTitle,
                  showBack: true,
                ),
              ),
              SliverToBoxAdapter(
                child: _Tabs(
                  selected: _tab,
                  onSelected: (tab) => setState(() => _tab = tab),
                ),
              ),
              if (_tab == _YouTab.history)
                const _History()
              else ...[
                if (!enabled)
                  SliverToBoxAdapter(child: _Message(text: strings.statsOff))
                else
                  ..._summary(context, strings),
                SliverToBoxAdapter(child: _StatsSettings(enabled: enabled)),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _summary(BuildContext context, OngakuStrings strings) {
    final current = listeningStatsMonthKey(DateTime.now());
    final keys = {current, ...listeningStatsService.availableMonthKeys}.toList()
      ..sort((a, b) => b.compareTo(a));
    if (!keys.contains(_monthKey)) _monthKey = current;
    final month = _month(_monthKey);
    return [
      if (keys.length > 1)
        SliverToBoxAdapter(
          child: _MonthChips(
            keys: keys,
            selected: _monthKey,
            onSelected: _selectMonth,
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
        SliverToBoxAdapter(child: OngakuSectionTitle(title: strings.topSongs)),
        SliverToBoxAdapter(
          child: _Card(
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
        ),
      ],
      if (keys.length > 1) ...[
        SliverToBoxAdapter(
          child: OngakuSectionTitle(title: strings.monthByMonth),
        ),
        SliverToBoxAdapter(
          child: _Card(
            child: _MonthBars(
              minutes: {
                for (final key in keys.take(12))
                  key: monthDisplayMinutes(
                    listeningStatsService.monthStats(key),
                  ),
              },
              selected: _monthKey,
              onSelected: _selectMonth,
            ),
          ),
        ),
      ],
    ];
  }
}

/// "Résumé" and "Historique", as one rounded control.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onSelected});

  final _YouTab selected;
  final ValueChanged<_YouTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 8, margin, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_YouTab>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _YouTab.summary,
              icon: const Icon(FluentIcons.data_bar_vertical_24_regular),
              label: Text(strings.statsSummary),
            ),
            ButtonSegment(
              value: _YouTab.history,
              icon: const Icon(FluentIcons.history_24_regular),
              label: Text(strings.statsHistory),
            ),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onSelected(s.first),
        ),
      ),
    );
  }
}

/// A rounded surface around a block of the page.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final margin = ongakuPageMargin(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The listening history (moved here from the home menu): play it all,
/// shuffled or from a song, and clear it.
class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    return ValueListenableBuilder<List>(
      valueListenable: userRecentlyPlayed,
      builder: (context, songs, _) {
        final list = songs.whereType<Map>().toList();
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: _Message(text: strings.historyEmpty),
          );
        }
        final playlist = {'title': l10n.recentlyPlayed, 'list': list};
        return SliverList.list(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 14, margin, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => audioHandler.playPlaylistSong(
                        playlist: playlist,
                        songIndex: 0,
                      ),
                      icon: const Icon(FluentIcons.play_24_filled),
                      label: Text(strings.historyPlay),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => audioHandler.addPlaylistToQueue(
                        [...list]..shuffle(),
                        replace: true,
                        startIndex: 0,
                      ),
                      icon: const Icon(FluentIcons.arrow_shuffle_24_regular),
                      label: Text(strings.shuffleMix),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 4, margin, 6),
              child: Text(
                strings.songCount(list.length),
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            for (var i = 0; i < list.length; i++)
              SongBar(
                list[i],
                true,
                isRecentSong: true,
                onPlay: () => audioHandler.playPlaylistSong(
                  playlist: playlist,
                  songIndex: i,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
              child: OngakuSettingsGroup(
                title: '',
                tint: const Color(0xFFFF3B30),
                children: [
                  OngakuSettingsRow(
                    title: l10n.clearRecentlyPlayed,
                    icon: FluentIcons.delete_24_regular,
                    textColor: const Color(0xFFFF3B30),
                    onTap: () => _confirmClear(
                      context,
                      l10n.clearRecentlyPlayedQuestion,
                      () async {
                        userRecentlyPlayed.value = [];
                        await deleteData('user', 'recentlyPlayedSongs');
                      },
                      l10n.recentlyPlayedMsg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Asks before clearing, then says it is done.
void _confirmClear(
  BuildContext context,
  String question,
  Future<void> Function() onClear,
  String done,
) {
  final l10n = context.l10n!;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => ConfirmationDialog(
      confirmationMessage: question,
      submitMessage: l10n.clear,
      isDangerous: true,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onSubmit: () async {
        Navigator.of(dialogContext).pop();
        await onClear();
        if (context.mounted) showToast(context, '$done!');
      },
    ),
  );
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
              duration: OngakuMotion.quick,
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
                    _Figure(
                      number.format(month.songs.length),
                      strings.statSongs,
                    ),
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
                        duration: OngakuMotion.quick,
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
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final margin = ongakuPageMargin(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 24, margin, 0),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          fontSize: 15,
        ),
      ),
    );
  }
}

/// The statistics' own settings, at the bottom of the summary: record
/// them or not (Musify's settings switch), and clear them.
class _StatsSettings extends StatelessWidget {
  const _StatsSettings({required this.enabled});

  final bool enabled;

  Future<void> _set(bool value) async {
    // Same steps as Musify's settings page.
    if (!value) {
      audioHandler.resetListeningStatsSession(
        countCurrentTick: true,
        flushStats: false,
      );
      await listeningStatsService.flush();
    }
    await addOrUpdateData<bool>('settings', 'wrappedEnabled', value);
    wrappedEnabled.value = value;
    listeningStatsService.reload();
    if (value) audioHandler.startListeningStatsSessionIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 28, margin, 0),
      child: OngakuSettingsGroup(
        title: strings.statsSettings,
        tint: Theme.of(context).colorScheme.primary,
        children: [
          OngakuSettingsRow(
            title: strings.statsRecord,
            icon: FluentIcons.data_bar_vertical_24_regular,
            description: l10n.listeningStatsDescription,
            trailing: Switch(value: enabled, onChanged: _set),
            onTap: () => _set(!enabled),
          ),
          OngakuSettingsRow(
            title: l10n.clearListeningStats,
            icon: FluentIcons.delete_24_regular,
            iconColor: const Color(0xFFFF3B30),
            textColor: const Color(0xFFFF3B30),
            onTap: () => _confirmClear(
              context,
              l10n.clearListeningStatsQuestion,
              () async {
                audioHandler.resetListeningStatsSession(flushStats: false);
                await listeningStatsService.clearStats();
                audioHandler.startListeningStatsSessionIfNeeded();
              },
              l10n.listeningStatsCleared,
            ),
          ),
        ],
      ),
    );
  }
}
