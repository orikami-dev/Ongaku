import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/layout/adaptive.dart';
import 'package:musify/ongaku/local/local_ids.dart';
import 'package:musify/ongaku/local/local_library.dart';

void main() {
  group('window size classes', () {
    test('phones, foldables, tablets and desktops', () {
      expect(windowSizeForWidth(360), WindowSize.compact);
      expect(windowSizeForWidth(599), WindowSize.compact);
      expect(windowSizeForWidth(673), WindowSize.medium); // unfolded Fold
      expect(windowSizeForWidth(900), WindowSize.expanded);
      expect(windowSizeForWidth(1400), WindowSize.large);
    });
  });

  group('fold detection', () {
    const screen = Size(1000, 800);

    test('no features means no split', () {
      expect(foldSplitFrom(const [], screen), isNull);
    });

    test('a vertical hinge splits side by side', () {
      final split = foldSplitFrom(const [
        DisplayFeature(
          bounds: Rect.fromLTWH(490, 0, 20, 800),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ], screen);
      expect(split?.isSideBySide, isTrue);
    });

    test('a half-opened horizontal fold stacks the panes', () {
      final split = foldSplitFrom(const [
        DisplayFeature(
          bounds: Rect.fromLTWH(0, 400, 1000, 0),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ], screen);
      expect(split?.axis.name, 'vertical');
    });

    test('a flat, seamless fold is ignored', () {
      expect(
        foldSplitFrom(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(500, 0, 0, 800),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ], screen),
        isNull,
      );
    });
  });

  group('local songs', () {
    test('ids are stable and recognised', () {
      final a = localSongIdForPath('/music/a.mp3');
      expect(a, localSongIdForPath('/music/a.mp3'));
      expect(a, isNot(localSongIdForPath('/music/b.mp3')));
      expect(isLocalSongId(a), isTrue);
      expect(isLocalSongId('dQw4w9WgXcQ'), isFalse);
      expect(isLocalSongId(null), isFalse);
    });
  });
}
