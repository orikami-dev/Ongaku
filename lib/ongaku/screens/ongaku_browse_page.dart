/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/ongaku_routes.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/services/playlists_manager.dart';

/// "Nouveautés": Musify's playlist and album catalogue, laid out like the
/// Apple Music New tab. The selection changes every day.
class OngakuBrowsePage extends StatefulWidget {
  const OngakuBrowsePage({super.key});

  @override
  State<OngakuBrowsePage> createState() => _OngakuBrowsePageState();
}

class _OngakuBrowsePageState extends State<OngakuBrowsePage> {
  late final Future<(List<Map>, List<Map>)> _catalogue = _load();

  Future<(List<Map>, List<Map>)> _load() async {
    final now = DateTime.now();
    final random = math.Random(now.year * 1000 + now.month * 40 + now.day);
    final lists = (await getPlaylists(
      type: 'playlist',
    )).whereType<Map>().toList()..shuffle(random);
    final albums = (await getPlaylists(type: 'album')).whereType<Map>().toList()
      ..shuffle(random);
    return (lists, albums);
  }

  void _open(Map playlist) =>
      context.push('$ongakuBrowsePath/playlist/${playlist['ytid']}');

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final margin = ongakuPageMargin(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      body: FutureBuilder<(List<Map>, List<Map>)>(
        future: _catalogue,
        builder: (context, snapshot) {
          final (lists, albums) =
              snapshot.data ?? (const <Map>[], const <Map>[]);
          final featured = lists.take(6).toList();
          final more = lists.skip(6).take(wide ? 24 : 12).toList();

          final bannerWidth = ongakuShelfItemWidth(
            context,
            phone: 1.08,
            wide: 2.1,
          );
          final squareWidth = ongakuShelfItemWidth(
            context,
            phone: 2.3,
            wide: 4.6,
          );

          return CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: OngakuLargeTitle(title: strings.tabNew),
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (featured.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: OngakuSectionTitle(title: strings.featuredPlaylists),
                ),
                SliverToBoxAdapter(
                  child: OngakuShelf(
                    height: bannerWidth * 0.66,
                    itemWidth: bannerWidth,
                    itemCount: featured.length,
                    itemBuilder: (context, index) => OngakuTallCard(
                      image: featured[index]['image']?.toString(),
                      caption: strings.featuredPlaylists,
                      title: featured[index]['title']?.toString() ?? '',
                      onTap: () => _open(featured[index]),
                    ),
                  ),
                ),
              ],
              if (albums.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: OngakuSectionTitle(title: strings.newAlbums),
                ),
                SliverToBoxAdapter(
                  child: OngakuShelf(
                    height: squareWidth + 48,
                    itemWidth: squareWidth,
                    itemCount: math.min(albums.length, 20),
                    itemBuilder: (context, index) => OngakuSquareTile(
                      artwork: OngakuCoverImage(
                        albums[index]['image']?.toString(),
                      ),
                      title: albums[index]['title']?.toString() ?? '',
                      subtitle: albums[index]['artist']?.toString(),
                      onTap: () => _open(albums[index]),
                    ),
                  ),
                ),
              ],
              if (more.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: OngakuSectionTitle(title: strings.moreToExplore),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: margin),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: wide ? 4 : 2,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: more.length,
                    itemBuilder: (context, index) => OngakuSquareTile(
                      artwork: OngakuCoverImage(
                        more[index]['image']?.toString(),
                      ),
                      title: more[index]['title']?.toString() ?? '',
                      onTap: () => _open(more[index]),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}
