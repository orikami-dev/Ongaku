/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/song_filtering.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/song_bar.dart';

enum _LocalSort { recent, title, artist }

/// Library > Local Files: songs imported from the device.
class LocalFilesPage extends StatefulWidget {
  const LocalFilesPage({super.key});

  @override
  State<LocalFilesPage> createState() => _LocalFilesPageState();
}

class _LocalFilesPageState extends State<LocalFilesPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _LocalSort _sort = _LocalSort.recent;

  @override
  void initState() {
    super.initState();
    // Pick up files added to remembered folders since last time.
    if (localMusicFolders.value.isNotEmpty) {
      unawaited(rescanLocalLibrary());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map> _sorted(List<Map> songs) {
    final list = List<Map>.of(songs);
    int byKey(Map a, Map b, String key) => (a[key] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b[key] ?? '').toString().toLowerCase());
    switch (_sort) {
      case _LocalSort.recent:
        list.sort(
          (a, b) => ((b['dateAdded'] ?? 0) as int).compareTo(
            (a['dateAdded'] ?? 0) as int,
          ),
        );
      case _LocalSort.title:
        list.sort((a, b) => byKey(a, b, 'title'));
      case _LocalSort.artist:
        list.sort((a, b) {
          final c = byKey(a, b, 'artist');
          return c != 0 ? c : byKey(a, b, 'title');
        });
    }
    return list;
  }

  Map<String, dynamic> _playlist(List<Map> songs, String title) => {
    'ytid': '',
    'title': title,
    'source': 'user-created',
    'list': songs,
  };

  Future<void> _addFiles() async {
    final result = await pickAndImportLocalFiles();
    _report(result);
  }

  Future<void> _addFolder() async {
    final result = await pickAndImportLocalFolder();
    _report(result);
  }

  Future<void> _rescan() async {
    final added = await rescanLocalLibrary();
    _report(LocalImportResult(added: added));
  }

  void _report(LocalImportResult result) {
    if (!mounted) return;
    final strings = OngakuStrings.of(context);
    if (result.permissionDenied) {
      showToast(context, strings.permissionDenied);
    } else if (result.added > 0) {
      showToast(context, strings.songsAdded(result.added));
    } else {
      showToast(context, strings.noNewSongs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.localFiles),
        actions: [
          PopupMenuButton<Object>(
            icon: const Icon(FluentIcons.more_horizontal_24_regular),
            onSelected: (value) {
              if (value is _LocalSort) {
                setState(() => _sort = value);
              } else if (value == 'files') {
                _addFiles();
              } else if (value == 'folder') {
                _addFolder();
              } else if (value == 'rescan') {
                _rescan();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'files', child: Text(strings.addFiles)),
              PopupMenuItem(value: 'folder', child: Text(strings.addFolder)),
              PopupMenuItem(value: 'rescan', child: Text(strings.rescan)),
              const PopupMenuDivider(),
              for (final (sort, label) in [
                (_LocalSort.recent, strings.sortRecent),
                (_LocalSort.title, strings.sortTitle),
                (_LocalSort.artist, strings.sortArtist),
              ])
                CheckedPopupMenuItem(
                  value: sort,
                  checked: _sort == sort,
                  child: Text(label),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ValueListenableBuilder<bool>(
            valueListenable: localLibraryBusy,
            builder: (context, busy, _) => busy
                ? LinearProgressIndicator(
                    minHeight: 2,
                    color: colorScheme.primary,
                    backgroundColor: Colors.transparent,
                  )
                : const SizedBox(height: 2),
          ),
        ),
      ),
      body: ValueListenableBuilder<List<Map>>(
        valueListenable: localSongs,
        builder: (context, songs, _) {
          if (songs.isEmpty)
            return _EmptyState(onAddFiles: _addFiles, onAddFolder: _addFolder);

          final sorted = _sorted(songs);
          final visible = _query.isEmpty
              ? sorted
              : filterSongsByQuery(sorted, _query).cast<Map>().toList();
          final playlist = _playlist(sorted, strings.localFiles);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.songCount(songs.length),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(FluentIcons.play_24_filled),
                              label: Text(context.l10n!.play),
                              onPressed: () => audioHandler.playPlaylistSong(
                                playlist: playlist,
                                songIndex: 0,
                                shuffle: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(
                                FluentIcons.arrow_shuffle_24_filled,
                              ),
                              label: Text(context.l10n!.shuffle),
                              onPressed: () => audioHandler.addPlaylistToQueue(
                                sorted,
                                replace: true,
                                shuffle: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _FolderChips(
                        onAddFiles: _addFiles,
                        onAddFolder: _addFolder,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: context.l10n!.search,
                          prefixIcon: const Icon(
                            FluentIcons.search_24_regular,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final song = visible[index];
                    return SongBar(
                      key: ValueKey(song['ytid']),
                      song,
                      true,
                      backgroundColor: Colors.transparent,
                      showMusicDuration: true,
                      onPlay: () => audioHandler.playPlaylistSong(
                        playlist: playlist,
                        songIndex: sorted.indexOf(song),
                      ),
                      onRemove: () => removeLocalSong(song),
                    );
                  },
                ),
              ),
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }
}

class _FolderChips extends StatelessWidget {
  const _FolderChips({required this.onAddFiles, required this.onAddFolder});

  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);

    return ValueListenableBuilder<List<String>>(
      valueListenable: localMusicFolders,
      builder: (context, folders, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(FluentIcons.document_add_24_regular, size: 18),
              label: Text(strings.addFiles),
              onPressed: onAddFiles,
            ),
            ActionChip(
              avatar: const Icon(FluentIcons.folder_add_24_regular, size: 18),
              label: Text(strings.addFolder),
              onPressed: onAddFolder,
            ),
            for (final folder in folders)
              InputChip(
                avatar: const Icon(FluentIcons.folder_24_regular, size: 18),
                label: Text(folder.split('/').where((p) => p.isNotEmpty).last),
                tooltip: folder,
                deleteButtonTooltipMessage: strings.removeFolder,
                onDeleted: () => removeLocalFolder(folder),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFiles, required this.onAddFolder});

  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.folder_open_24_regular,
                size: 64,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                strings.emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.emptyBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(FluentIcons.folder_add_24_regular),
                  label: Text(strings.addFolder),
                  onPressed: onAddFolder,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(FluentIcons.document_add_24_regular),
                  label: Text(strings.addFiles),
                  onPressed: onAddFiles,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
