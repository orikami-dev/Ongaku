import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/ongaku/services/ongaku_auto_browser.dart';
import 'package:musify/services/audio_service_android_auto.dart';
import 'package:musify/services/common_services.dart';

void main() {
  late Directory directory;
  late _Host host;
  late OngakuAutoBrowser browser;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('ongaku_auto_test');
    Hive.init(directory.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  setUp(() {
    host = _Host();
    browser = OngakuAutoBrowser(host);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('the car shows the app tabs, Home first', () async {
    final tabs = await browser.children(AudioService.browsableRootId);
    expect(tabs.map((t) => t.id), [
      'ongaku_home',
      'ongaku_library',
      'playlists',
      'current_queue',
    ]);
    final library = await browser.children('ongaku_library');
    expect(library.first.id, 'ongaku_all');
  });

  test('All Songs: Shuffle first, then A to Z under letters', () async {
    userLikedSongsList.value = [
      {'ytid': 'b', 'title': 'Washi Dreams', 'artist': 'X'},
      {'ytid': 'a', 'title': 'Aoi Sora', 'artist': 'Y'},
    ];
    final items = await browser.children('ongaku_all');
    expect(items.map((i) => i.id), [
      'ongaku_shuffle:ongaku_all',
      'ongaku_all:0',
      'ongaku_all:1',
    ]);
    expect(items[1].title, 'Aoi Sora');
    expect(
      items[2].extras?['android.media.browse.CONTENT_STYLE_GROUP_TITLE'],
      'W',
    );

    await browser.playFromMediaId('ongaku_all:1');
    expect(host.played?.map((s) => s['ytid']), ['a', 'b']);
    expect(host.playedIndex, 1);
  });
}

class _Host implements AndroidAutoHost {
  List<Map>? played;
  int? playedIndex;

  @override
  List<Map> get browserQueue => const [];

  @override
  Stream<List<MediaItem>> get browserQueueStream => const Stream.empty();

  @override
  Map? latestResumableSong() => null;

  @override
  Map<String, dynamic>? normaliseResumableSong(Map song) => null;

  @override
  Future<void> playResumableSong(Map song) async {}

  @override
  String ensureBrowserQueueEntryId(Map song) => 'entry-1';

  @override
  void logBrowserError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  Future<void> resumeAudio() async {}

  @override
  Future<void> skipToQueueItem(int index) async {}

  @override
  Future<void> playBrowserPlaylist(
    List<Map> songs, {
    required int songIndex,
  }) async {
    played = songs;
    playedIndex = songIndex;
  }

  @override
  void publishPreparedBrowserItem(MediaItem item) {}
}
