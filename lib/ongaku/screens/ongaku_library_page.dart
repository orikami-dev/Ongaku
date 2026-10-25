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
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/ongaku_routes.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';

/// Opens a playlist, album or artist of the library.
void ongakuOpenCollection(BuildContext context, Map item) {
  final id = item['ytid']?.toString() ?? '';
  if (id.isEmpty) return;
  if (isArtistPlaylist(item)) {
    context.push(NavigationManager.artistPath(context, id), extra: item);
    return;
  }
  context.push('/home/playlist/$id');
}

/// The most recently added playlists and albums, newest first. Liked items
/// are stored in the order they were added and have no date, so they are
/// interleaved with the dated custom playlists.
List<Map> ongakuRecentlyAdded({
  required List<Map> liked,
  required List<Map> custom,
  int limit = 6,
}) {
  final dated = [...custom]
    ..sort(
      (a, b) => ((b['createdAt'] as num?) ?? 0).compareTo(
        (a['createdAt'] as num?) ?? 0,
      ),
    );
  final likedNewest = liked.reversed.toList();
  final result = <Map>[];
  final seen = <String>{};
  for (var i = 0; result.length < limit; i++) {
    if (i >= dated.length && i >= likedNewest.length) break;
    for (final list in [likedNewest, dated]) {
      if (i < list.length && result.length < limit) {
        final id = list[i]['ytid']?.toString() ?? '';
        if (seen.add(id)) result.add(list[i]);
      }
    }
  }
  return result;
}

/// One row of the Library list.
class OngakuLibraryCategory {
  const OngakuLibraryCategory(
    this.id,
    this.icon,
    this.path, {
    this.online = false,
  });

  final String id;
  final IconData icon;
  final String path;

  /// Hidden in offline mode.
  final bool online;
}

const ongakuLibraryCategories = [
  OngakuLibraryCategory(
    'playlists',
    Icons.queue_music_rounded,
    '/library/playlists',
  ),
  OngakuLibraryCategory('artists', Icons.mic_none_rounded, '/library/artists'),
  OngakuLibraryCategory(
    'albums',
    Icons.album_outlined,
    '/library/albums',
    online: true,
  ),
  OngakuLibraryCategory('songs', Icons.music_note_rounded, allSongsPath),
  OngakuLibraryCategory(
    'liked',
    Icons.star_border_rounded,
    '/library/userSongs/liked',
    online: true,
  ),
  OngakuLibraryCategory(
    'downloaded',
    Icons.arrow_circle_down_rounded,
    '/library/userSongs/offline',
  ),
  OngakuLibraryCategory(
    'localFiles',
    Icons.folder_open_rounded,
    localFilesPath,
  ),
  OngakuLibraryCategory(
    'recents',
    Icons.history_rounded,
    '/library/userSongs/recents',
    online: true,
  ),
  OngakuLibraryCategory(
    'radio',
    Icons.radio_rounded,
    '/library/radioStations',
    online: true,
  ),
];

/// Categories the listener hid with "Edit".
final ValueNotifier<List<String>> ongakuHiddenLibraryCategories = ValueNotifier(
  _readList('ongakuHiddenLibraryCategories'),
);

void _setHidden(List<String> ids) {
  ongakuHiddenLibraryCategories.value = ids;
  try {
    Hive.box('settings').put('ongakuHiddenLibraryCategories', ids);
  } catch (_) {}
}

/// The listener's order of the categories ("Edit", drag ≡).
final ValueNotifier<List<String>> ongakuLibraryOrder = ValueNotifier(
  _readList('ongakuLibraryOrder'),
);

List<String> _readList(String key) {
  try {
    final value = Hive.box('settings').get(key);
    return value is List ? value.cast<String>() : const [];
  } catch (_) {
    return const [];
  }
}

/// Every category, in the saved order; new ones keep their default place
/// at the end.
List<OngakuLibraryCategory> ongakuOrderedCategories(List<String> order) {
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  final list = [...ongakuLibraryCategories];
  final defaults = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((a, b) {
    final ra = rank[a.id] ?? order.length + defaults[a.id]!;
    final rb = rank[b.id] ?? order.length + defaults[b.id]!;
    return ra.compareTo(rb);
  });
  return list;
}

/// Moves one of the [visible] rows from [from] to [to] (already adjusted for
/// the removed row) inside the full [order], hidden rows staying put.
List<String> ongakuMoveCategory(
  List<String> order,
  List<String> visible,
  int from,
  int to,
) {
  final moved = visible[from];
  final rest = [...visible]..removeAt(from);
  if (rest.isEmpty) return order;
  final full = order.where((id) => id != moved).toList();
  final at = to < rest.length
      ? full.indexOf(rest[to])
      : full.indexOf(rest.last) + 1;
  full.insert(at, moved);
  return full;
}

void _setOrder(List<String> ids) {
  ongakuLibraryOrder.value = ids;
  try {
    Hive.box('settings').put('ongakuLibraryOrder', ids);
  } catch (_) {}
}

/// The Library tab, Apple Music style: pinned items in a grid, the list of
/// categories, then what was added recently.
class OngakuLibraryPage extends StatefulWidget {
  const OngakuLibraryPage({super.key});

  @override
  State<OngakuLibraryPage> createState() => _OngakuLibraryPageState();
}

class _OngakuLibraryPageState extends State<OngakuLibraryPage> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);

    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([
          pinnedPlaylistIds,
          offlineMode,
          userCustomPlaylists,
          userLikedPlaylists,
          ongakuHiddenLibraryCategories,
          ongakuLibraryOrder,
        ]),
        builder: (context, _) {
          final pins = resolvePinnedPlaylists(pinnedPlaylistIds.value);
          final hidden = ongakuHiddenLibraryCategories.value;
          final ordered = ongakuOrderedCategories(ongakuLibraryOrder.value);
          final categories = ordered
              .where((c) => !c.online || !offlineMode.value)
              .where((c) => _editing || !hidden.contains(c.id))
              .toList();
          final recent = offlineMode.value
              ? const <Map>[]
              : ongakuRecentlyAdded(
                  liked: userLikedPlaylists.value,
                  custom: userCustomPlaylists.value,
                );

          return CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: OngakuLargeTitle(
                  title: context.l10n!.library,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _editing = !_editing),
                        child: Text(
                          _editing ? strings.libDone : strings.libEdit,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: _editing
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!offlineMode.value)
                        IconButton(
                          tooltip: context.l10n!.addPlaylist,
                          onPressed: () => showCreatePlaylistDialog(context),
                          icon: Icon(
                            Icons.add_rounded,
                            size: 28,
                            color: colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (pins.isNotEmpty || _editing)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(margin, 16, margin, 4),
                  sliver: pins.isEmpty
                      ? SliverToBoxAdapter(
                          child: Text(
                            strings.libPinHint,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        )
                      : _grid(context, pins, phoneColumns: 3, pinned: true),
                ),
              SliverPadding(
                padding: EdgeInsets.only(left: margin, top: 8),
                sliver: SliverReorderableList(
                  itemCount: categories.length,
                  proxyDecorator: (child, _, __) => Material(
                    color: colorScheme.surfaceContainerHigh,
                    elevation: 6,
                    child: child,
                  ),
                  onReorderItem: (from, to) => _setOrder(
                    ongakuMoveCategory(
                      [for (final c in ordered) c.id],
                      [for (final c in categories) c.id],
                      from,
                      to,
                    ),
                  ),
                  itemBuilder: (context, i) => _CategoryRow(
                    key: ValueKey(categories[i].id),
                    index: i,
                    category: categories[i],
                    label: _label(context, categories[i].id),
                    editing: _editing,
                    shown: !hidden.contains(categories[i].id),
                    last: i == categories.length - 1,
                    onToggle: () {
                      final id = categories[i].id;
                      _setHidden(
                        hidden.contains(id)
                            ? (List.of(hidden)..remove(id))
                            : [...hidden, id],
                      );
                    },
                  ),
                ),
              ),
              if (recent.isNotEmpty && !_editing) ...[
                SliverToBoxAdapter(
                  child: OngakuSectionTitle(title: strings.libRecentlyAdded),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: margin),
                  sliver: _grid(context, recent, phoneColumns: 2),
                ),
              ],
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    List<Map> items, {
    required int phoneColumns,
    bool pinned = false,
  }) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final columns = wide ? phoneColumns + 2 : phoneColumns;
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: pinned ? 12 : 16,
        // Square artwork plus one or two lines of text.
        childAspectRatio: pinned ? 0.78 : 0.74,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final artist = isArtistPlaylist(item);
        final tile = OngakuSquareTile(
          artwork: artist
              ? ClipOval(child: OngakuCoverImage(item['image']?.toString()))
              : OngakuCoverImage(item['image']?.toString()),
          title: item['title']?.toString() ?? '',
          subtitle: pinned ? null : _subtitle(context, item),
          onTap: _editing ? null : () => ongakuOpenCollection(context, item),
        );
        if (!pinned) return tile;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            tile,
            Positioned(
              top: -6,
              left: -6,
              child: AnimatedScale(
                scale: _editing ? 1 : 0,
                duration: OngakuMotion.quick,
                child: _UnpinBadge(
                  onTap: () => togglePinnedPlaylist(
                    item['ytid']?.toString() ?? '',
                    context,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String? _subtitle(BuildContext context, Map item) {
    final l10n = context.l10n!;
    if (isArtistPlaylist(item)) return l10n.artist;
    if (item['isAlbum'] == true) {
      return item['artist']?.toString() ?? l10n.album;
    }
    return l10n.playlist;
  }

  String _label(BuildContext context, String id) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);
    return switch (id) {
      'playlists' => l10n.playlists,
      'artists' => l10n.artists,
      'albums' => l10n.albums,
      'songs' => strings.libSongs,
      'liked' => strings.libLiked,
      'downloaded' => strings.libDownloaded,
      'localFiles' => strings.localFiles,
      'recents' => strings.recentlyPlayed,
      _ => strings.libRadio,
    };
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.index,
    required this.category,
    required this.label,
    required this.editing,
    required this.shown,
    required this.last,
    required this.onToggle,
  });

  final int index;
  final OngakuLibraryCategory category;
  final String label;
  final bool editing;
  final bool shown;
  final bool last;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final faint = colorScheme.onSurface.withValues(alpha: 0.18);

    return InkWell(
      onTap: editing ? onToggle : () => context.go(category.path),
      child: SizedBox(
        height: 54,
        child: Row(
          // Full height, so each divider sits at the bottom of its row.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: OngakuMotion.quick,
              child: editing
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        shown
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 24,
                        color: shown ? colorScheme.primary : faint,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            SizedBox(
              width: 40,
              child: Icon(category.icon, size: 26, color: colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(bottom: BorderSide(color: faint, width: 0.5)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(right: margin),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            color: colorScheme.onSurface.withValues(
                              alpha: editing && !shown ? 0.4 : 1,
                            ),
                          ),
                        ),
                      ),
                      if (editing)
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              size: 26,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 24,
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnpinBadge extends StatelessWidget {
  const _UnpinBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.surfaceContainerHighest,
          border: Border.all(color: colorScheme.surface, width: 2),
        ),
        child: Icon(
          Icons.remove_rounded,
          size: 18,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Library > Artists, or Library > Albums: the liked ones in a grid.
class OngakuCollectionPage extends StatelessWidget {
  const OngakuCollectionPage({super.key, required this.artists});

  final bool artists;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([userLikedPlaylists, offlineMode]),
        builder: (context, _) {
          final items = artists
              ? getLikedArtistItems(offlineOnly: offlineMode.value)
              : getLikedPlaylistItems()
                    .where((p) => p['isAlbum'] == true)
                    .toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: OngakuLargeTitle(
                  title: artists ? l10n.artists : l10n.albums,
                  showBack: true,
                ),
              ),
              if (items.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(margin, 32, margin, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      artists ? strings.libNoArtists : strings.libNoAlbums,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(margin, 16, margin, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: wide ? 4 : 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: artists ? 0.82 : 0.74,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final cover = OngakuCoverImage(item['image']?.toString());
                      return OngakuSquareTile(
                        artwork: artists ? ClipOval(child: cover) : cover,
                        title: item['title']?.toString() ?? '',
                        subtitle: artists ? null : item['artist']?.toString(),
                        onTap: () => ongakuOpenCollection(context, item),
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
