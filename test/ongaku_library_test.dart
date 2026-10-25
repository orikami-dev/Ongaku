import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/screens/ongaku_library_page.dart';

void main() {
  test('recently added mixes liked and custom playlists, newest first', () {
    final items = ongakuRecentlyAdded(
      liked: [
        {'ytid': 'L1'},
        {'ytid': 'L2'},
        {'ytid': 'L3'},
      ],
      custom: [
        {'ytid': 'C1', 'createdAt': 10},
        {'ytid': 'C2', 'createdAt': 30},
        {'ytid': 'C3'},
      ],
      limit: 5,
    );
    expect(items.map((p) => p['ytid']), ['L3', 'C2', 'L2', 'C1', 'L1']);
  });

  test('recently added skips duplicates and copes with empty lists', () {
    expect(ongakuRecentlyAdded(liked: [], custom: []), isEmpty);
    final items = ongakuRecentlyAdded(
      liked: [
        {'ytid': 'X'},
      ],
      custom: [
        {'ytid': 'X', 'createdAt': 1},
      ],
    );
    expect(items.map((p) => p['ytid']), ['X']);
  });

  test('every category has its own id', () {
    final ids = ongakuLibraryCategories.map((c) => c.id).toSet();
    expect(ids.length, ongakuLibraryCategories.length);
  });

  test('categories follow the saved order, new ones at the end', () {
    final ids = ongakuOrderedCategories(['radio', 'songs']).map((c) => c.id);
    expect(ids.take(3), ['radio', 'songs', 'playlists']);
    expect(ids.length, ongakuLibraryCategories.length);
  });

  test('moving a visible category keeps hidden ones in place', () {
    final order = ['a', 'b', 'c', 'd'];
    // 'b' is hidden (offline): move 'd' to the top of the visible rows.
    expect(ongakuMoveCategory(order, ['a', 'c', 'd'], 2, 0), [
      'd',
      'a',
      'b',
      'c',
    ]);
    // Move 'a' to the end.
    expect(ongakuMoveCategory(order, ['a', 'c', 'd'], 0, 2), [
      'b',
      'c',
      'd',
      'a',
    ]);
  });
}
