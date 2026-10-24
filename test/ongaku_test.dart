import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/layout/adaptive.dart';
import 'package:musify/ongaku/local/local_ids.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/ongaku/lyrics/synced_lyrics.dart';

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

  group('synced lyrics', () {
    test('parses LRC tags, offsets and repeated lines', () {
      final lyrics = parseLrc(
        '[offset:500]\n[00:10.00]first\n[00:05.5][01:00]chorus\n',
      );
      expect(lyrics, isNotNull);
      expect(lyrics!.lines.map((l) => l.text), ['chorus', 'first', 'chorus']);
      expect(lyrics.lines.first.time, const Duration(seconds: 5));
      expect(lyrics.synced, isTrue);
    });

    test('finds the line being sung', () {
      final lyrics = parseLrc('[00:01.00]a\n[00:05.00]b\n[00:09.00]c')!;
      expect(lyrics.indexAt(Duration.zero), -1);
      expect(lyrics.indexAt(const Duration(seconds: 5)), 1);
      expect(lyrics.indexAt(const Duration(seconds: 8)), 1);
      expect(lyrics.indexAt(const Duration(seconds: 99)), 2);
    });

    test('plain lyrics are spread over the song', () {
      final lyrics = spreadPlainLyrics(
        'one\ntwo\n\nthree',
        const Duration(minutes: 3),
      );
      expect(lyrics.synced, isFalse);
      expect(lyrics.lines, hasLength(3));
      expect(lyrics.lines.last.time, lessThan(const Duration(minutes: 3)));
    });

    test(
      'text without time tags is not LRC',
      () => expect(parseLrc('hello'), isNull),
    );
  });
}
