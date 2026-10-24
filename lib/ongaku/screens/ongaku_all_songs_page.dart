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
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';
import 'package:musify/services/common_services.dart'
    show userLikedSongsList, userOfflineSongs;
import 'package:musify/services/playlists_manager.dart'
    show userCustomPlaylists;
import 'package:musify/utilities/song_filtering.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/song_bar.dart';

/// Every song of the library in one list, A to Z: liked, downloaded, in a
/// playlist of the user or imported from the device.
List<Map> librarySongs({
  required List liked,
  required List offline,
  required List<Map> playlists,
  required List<Map> local,
}) {
  final seen = <String>{};
  final songs = <Map>[];
  void add(Object? song) {
    if (song is! Map) return;
    final id = song['ytid']?.toString() ?? '';
    final key = id.isNotEmpty ? id : '${song['title']}|${song['artist']}';
    if (seen.add(key)) songs.add(song);
  }

  liked.forEach(add);
  offline.forEach(add);
  for (final playlist in playlists) {
    (playlist['list'] as List? ?? const []).forEach(add);
  }
  local.forEach(add);

  songs.sort((a, b) {
    final byTitle = sortKey(a['title']).compareTo(sortKey(b['title']));
    return byTitle != 0
        ? byTitle
        : sortKey(a['artist']).compareTo(sortKey(b['artist']));
  });
  // Titles that do not start with a Latin letter go last, under "#".
  final letters = songs.where((s) => indexLetter(s['title']) != '#');
  final others = songs.where((s) => indexLetter(s['title']) == '#');
  return [...letters, ...others];
}

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'a', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', //
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', //
  'ö': 'o', 'ø': 'o', 'œ': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ß': 's',
};

/// The title folded for sorting: lower case, without accents or the
/// punctuation some titles start with.
String sortKey(Object? title) {
  final lower = (title?.toString() ?? '').toLowerCase().trimLeft();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString().replaceFirst(RegExp(r'''^["'(\[¿¡«“‘.\-_*]+'''), '');
}

/// The letter a title is filed under, or "#".
String indexLetter(Object? title) {
  final key = sortKey(title);
  if (key.isEmpty) return '#';
  final first = key[0];
  return RegExp('[a-z]').hasMatch(first) ? first.toUpperCase() : '#';
}

/// Library > All Songs.
class OngakuAllSongsPage extends StatefulWidget {
  const OngakuAllSongsPage({super.key});

  @override
  State<OngakuAllSongsPage> createState() => _OngakuAllSongsPageState();
}

class _OngakuAllSongsPageState extends State<OngakuAllSongsPage> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';
  final _activeLetter = ValueNotifier<String?>(null);
  final _headerKey = GlobalKey();

  static const _headerExtent = 36.0;

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    _activeLetter.dispose();
    super.dispose();
  }

  /// The height of one song row, fixed so that a letter of the index can
  /// jump straight to its section, whatever the length of the list.
  double _rowExtent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = scaler.scale(15) * 1.4 + 2 + scaler.scale(13) * 1.4;
    return 20 + (text > 52 ? text : 52) + 4;
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.allSongs)),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          userLikedSongsList,
          userOfflineSongs,
          userCustomPlaylists,
          localSongs,
        ]),
        builder: (context, _) {
          final sorted = librarySongs(
            liked: userLikedSongsList.value,
            offline: userOfflineSongs.value,
            playlists: userCustomPlaylists.value,
            local: localSongs.value,
          );
          if (sorted.isEmpty) return _Empty(text: strings.allSongsEmpty);

          final visible = _query.isEmpty
              ? sorted
              : filterSongsByQuery(sorted, _query).cast<Map>().toList();
          final playlist = <String, dynamic>{
            'ytid': '',
            'title': strings.allSongs,
            'source': 'user-created',
            'list': sorted,
          };

          // Rows: a letter header before the first song of each letter.
          final rows = <Object>[];
          final offsets = <String, double>{};
          final rowExtent = _rowExtent(context);
          var offset = 0.0;
          String? letter;
          for (final song in visible) {
            final next = indexLetter(song['title']);
            if (next != letter) {
              letter = next;
              offsets[next] = offset;
              rows.add(next);
              offset += _headerExtent;
            }
            rows.add(song);
            offset += rowExtent;
          }

          final header = _Header(
            key: _headerKey,
            count: sorted.length,
            onPlay: () => audioHandler.playPlaylistSong(
              playlist: playlist,
              songIndex: 0,
              shuffle: false,
            ),
            onShuffle: () => audioHandler.addPlaylistToQueue(
              sorted,
              replace: true,
              shuffle: true,
            ),
            searchController: _searchController,
            onSearch: (value) => setState(() => _query = value),
          );

          return Stack(
            children: [
              CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: header),
                  SliverPadding(
                    padding: const EdgeInsets.only(left: 10, right: 28),
                    sliver: SliverVariedExtentList.builder(
                      itemCount: rows.length,
                      itemExtentBuilder: (index, _) => index < rows.length
                          ? (rows[index] is String ? _headerExtent : rowExtent)
                          : null,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is String) {
                          return _LetterHeader(letter: row);
                        }
                        final song = row as Map;
                        return SongBar(
                          key: ValueKey('${song['ytid']}|${song['title']}'),
                          song,
                          true,
                          backgroundColor: Colors.transparent,
                          showMusicDuration: true,
                          onPlay: () => audioHandler.playPlaylistSong(
                            playlist: playlist,
                            songIndex: sorted.indexOf(song),
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverMiniPlayerBottomSpace(),
                ],
              ),
              if (offsets.length > 1)
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: _LetterIndex(
                      letters: offsets.keys.toList(),
                      active: _activeLetter,
                      color: colorScheme.primary,
                      onLetter: (value) {
                        _activeLetter.value = value;
                        final target = _headerHeight + offsets[value]!;
                        final max = _scroll.position.maxScrollExtent;
                        _scroll.jumpTo(target > max ? max : target);
                      },
                      onEnd: () => _activeLetter.value = null,
                    ),
                  ),
                ),
              ValueListenableBuilder<String?>(
                valueListenable: _activeLetter,
                builder: (context, value, _) => IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: value == null ? 0 : 1,
                      duration: OngakuMotion.fast,
                      child: Container(
                        width: 84,
                        height: 84,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          value ?? '',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Height of the header above the list, as laid out.
  double get _headerHeight => _headerKey.currentContext?.size?.height ?? 0;
}

class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.count,
    required this.onPlay,
    required this.onShuffle,
    required this.searchController,
    required this.onSearch,
  });

  final int count;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.songCount(count),
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(FluentIcons.play_24_filled),
                  label: Text(context.l10n!.play),
                  onPressed: onPlay,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(FluentIcons.arrow_shuffle_24_filled),
                  label: Text(context.l10n!.shuffle),
                  onPressed: onShuffle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: context.l10n!.search,
              prefixIcon: const Icon(FluentIcons.search_24_regular, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _LetterHeader extends StatelessWidget {
  const _LetterHeader({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Text(
            letter,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }
}

/// The column of letters on the right edge: tap or slide along it to jump.
class _LetterIndex extends StatelessWidget {
  const _LetterIndex({
    required this.letters,
    required this.active,
    required this.color,
    required this.onLetter,
    required this.onEnd,
  });

  final List<String> letters;
  final ValueNotifier<String?> active;
  final Color color;
  final ValueChanged<String> onLetter;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Letters shrink on short screens so the whole alphabet fits.
        final slot = (constraints.maxHeight * 0.8 / letters.length).clamp(
          10.0,
          20.0,
        );
        final height = slot * letters.length;

        void pick(double dy) {
          final index = (dy / slot).floor().clamp(0, letters.length - 1);
          final letter = letters[index];
          if (active.value != letter) onLetter(letter);
        }

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => pick(details.localPosition.dy),
            onTapUp: (_) => onEnd(),
            onVerticalDragStart: (details) => pick(details.localPosition.dy),
            onVerticalDragUpdate: (details) => pick(details.localPosition.dy),
            onVerticalDragEnd: (_) => onEnd(),
            onVerticalDragCancel: onEnd,
            child: SizedBox(
              width: 22,
              height: height,
              child: Column(
                children: [
                  for (final letter in letters)
                    SizedBox(
                      height: slot,
                      child: Center(
                        child: Text(
                          letter,
                          style: TextStyle(
                            fontSize: slot * 0.62,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.music_note_2_24_regular,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
