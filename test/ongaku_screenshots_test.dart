// Renders the Ongaku screens to PNG files, without a device or emulator.
//
//   flutter test test/ongaku_screenshots_test.dart \
//     --dart-define=ONGAKU_SHOTS=1 --dart-define=ONGAKU_SHOTS_DIR=/tmp/shots
//
// Skipped in a normal `flutter test` run. Seeds a temporary library (local
// songs with generated artwork and lyrics, playlists, history) so every
// screen has something to show.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/ongaku/screens/ongaku_now_playing_page.dart';
import 'package:musify/ongaku/screens/ongaku_shell.dart';
import 'package:musify/ongaku/theme/ongaku_theme.dart';
import 'package:musify/screens/search_page.dart' show searchHistoryNotifier;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/theme/app_themes.dart' as themes;
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/bottom_sheet_bar.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';

const _enabled = bool.fromEnvironment('ONGAKU_SHOTS');
const _outDir = String.fromEnvironment(
  'ONGAKU_SHOTS_DIR',
  defaultValue: '/tmp/ongaku-shots',
);

final _rootKey = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<Map<String, dynamic>> songs;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('ongaku_shots');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
    await _loadFonts();
    languageSetting = const Locale('fr');
    themes.themeMode = ThemeMode.dark;
    themes.brightness = Brightness.dark;
    _mockJustAudio();
    _mockPathProvider(directory.path);
    NavigationManager.instance;
    audioHandler = MusifyAudioHandler();
    songs = await _seedLibrary(directory.path);
    await Directory(_outDir).create(recursive: true);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> shots(
    WidgetTester tester, {
    required String prefix,
    required Size size,
    required EdgeInsets padding,
    required ThemeMode mode,
    required List<String> routes,
    bool player = true,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding(
      top: padding.top * 3,
      bottom: padding.bottom * 3,
      left: padding.left * 3,
      right: padding.right * 3,
    );
    addTearDown(tester.view.reset);
    themes.themeMode = mode;
    themes.brightness = mode == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light;

    // One real-time zone for the whole run: timers started by the player
    // and the pages are then real timers, not fake ones the test framework
    // would flag as pending at the end.
    await tester.runAsync(() async {
      // A song playing, so the mini player and the player have content.
      await audioHandler.addPlaylistToQueue(songs, replace: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      audioHandler.mediaItem.add(mapToMediaItem(songs.first));

      await tester.pumpWidget(_App(key: _rootKey, mode: mode));
      await _settle(tester);

      for (final route in routes) {
        NavigationManager.router.go(route);
        await _settle(tester);
        await _capture(tester, '$prefix-${_slug(route)}');
        if (route == '/home/you') {
          for (var i = 1; i <= 2; i++) {
            await tester.drag(
              find.byType(CustomScrollView).last,
              Offset(0, -size.height * 0.7),
            );
            await _settle(tester);
            await _capture(tester, '$prefix-you-$i');
          }
        }
        if (route == '/home') {
          // The rest of the home page, one screen at a time.
          for (var i = 1; i <= 4; i++) {
            await tester.drag(
              find.byType(CustomScrollView).first,
              Offset(0, -size.height * 0.8),
            );
            await _settle(tester);
            await _capture(tester, '$prefix-home-$i');
          }
        }
      }

      if (player) {
        NavigationManager.router.go('/home');
        await _settle(tester);
        final context = tester.element(find.byType(OngakuShell));
        // ignore: unawaited_futures
        openOngakuNowPlaying(context);
        await _settle(tester, frames: 20);
        await _capture(tester, '$prefix-player');

        await tester.tap(find.byIcon(Icons.format_quote_rounded).first);
        await _settle(tester, frames: 25);
        await _capture(tester, '$prefix-player-lyrics');

        await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded).first);
        await _settle(tester, frames: 15);
        await _capture(tester, '$prefix-player-queue');

        Navigator.of(context, rootNavigator: true).pop();
        await _settle(tester);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester, frames: 3);
    });
  }

  testWidgets('phone, dark', (tester) async {
    await shots(
      tester,
      prefix: 'phone-dark',
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 44, bottom: 24),
      mode: ThemeMode.dark,
      routes: [
        '/home',
        '/library',
        '/search',
        '/settings',
        '/home/you',
        '/library/localFiles',
        '/library/userSongs/liked',
        '/settings/import-deezer-playlist',
        '/settings/import-apple-music-playlist',
      ],
    );
  }, skip: !_enabled);

  testWidgets('phone, light', (tester) async {
    await shots(
      tester,
      prefix: 'phone-light',
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 44, bottom: 24),
      mode: ThemeMode.light,
      routes: [
        '/home',
        '/library',
        '/settings',
        '/settings/import-apple-music-playlist',
      ],
      player: false,
    );
  }, skip: !_enabled);

  testWidgets('open foldable, dark', (tester) async {
    await shots(
      tester,
      prefix: 'fold-dark',
      size: const Size(673, 841),
      padding: const EdgeInsets.only(top: 32, bottom: 20),
      mode: ThemeMode.dark,
      routes: ['/home', '/library', '/settings'],
    );
  }, skip: !_enabled);

  testWidgets('theme mode picker (real app widget)', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.runAsync(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel('receive_sharing_intent/events-text'),
            _NoEvents(),
          );
      shouldWeCheckUpdates.value = false;
      await tester.pumpWidget(const RepaintBoundary(child: Musify()));
      await _settle(tester);
      NavigationManager.router.go('/settings');
      await _settle(tester);
      await _capture(tester, 'theme-start');
      for (final mode in ['Clair', 'Système', 'Sombre']) {
        tester
            .widgetList<CustomBar>(find.byType(CustomBar))
            .firstWhere((b) => b.tileName == 'Mode de thème')
            .onTap!();
        await _settle(tester);
        await _capture(tester, 'theme-sheet-$mode');
        tester
            .widgetList<BottomSheetBar>(find.byType(BottomSheetBar))
            .firstWhere((b) => b.title == mode)
            .onTap();
        await _settle(tester);
        await _capture(tester, 'theme-$mode');
      }
      // The Couleur picker as on Android, with the dynamic colour switch.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester
          .widgetList<CustomBar>(find.byType(CustomBar))
          .firstWhere((b) => b.tileName == 'Couleur')
          .onTap!();
      await _settle(tester);
      await _capture(tester, 'accent-sheet');
      Navigator.of(
        tester.element(find.byType(CustomBar).first),
        rootNavigator: true,
      ).pop();
      await _settle(tester);
      debugDefaultTargetPlatformOverride = null;
      // The sponsor section at the bottom of the settings.
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -6000),
      );
      await _settle(tester);
      await _capture(tester, 'settings-bottom');
      NavigationManager.router.go('/settings/about');
      await _settle(tester);
      await _capture(tester, 'about');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await _settle(tester);
      await _capture(tester, 'about-bottom');
      NavigationManager.router.go('/settings');
      await _settle(tester);
      for (final dangerous in [true, false]) {
        final context = tester.element(find.byType(CustomBar).first);
        // ignore: unawaited_futures
        showDialog<void>(
          context: context,
          builder: (_) => ConfirmationDialog(
            confirmationMessage:
                "Êtes-vous sûr de vouloir effacer l'historique de recherche ?",
            submitMessage: 'Confirmer',
            isDangerous: dangerous,
            onCancel: () {},
            onSubmit: () {},
          ),
        );
        await _settle(tester);
        await _capture(tester, 'confirm-${dangerous ? 'danger' : 'normal'}');
        Navigator.of(context, rootNavigator: true).pop();
        await _settle(tester);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester, frames: 3);
    });
    FlutterError.onError = old;
    for (final e in errors) {
      // ignore: avoid_print
      print('ERROR: ${e.exceptionAsString()}\n${e.stack}');
    }
    expect(errors, isEmpty);
  }, skip: !_enabled);
}

class _App extends StatelessWidget {
  const _App({super.key, required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    // Android look (page transitions, platform rows) without touching the
    // global platform override, which tests must leave alone.
    final theme = getOngakuTheme(getOngakuColorScheme(null, null))
        .copyWith(platform: TargetPlatform.android);
    return RepaintBoundary(
      child: MaterialApp.router(
        themeMode: mode,
        theme: theme,
        darkTheme: theme,
        scrollBehavior: const OngakuScrollBehavior(),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: languageSetting,
        routerConfig: NavigationManager.router,
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
}

String _slug(String route) =>
    route.replaceAll('/', '-').replaceAll(RegExp('^-'), '');

/// Answers just_audio's platform calls so queueing works without a device.
void _mockJustAudio() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.ryanheise.just_audio.methods'),
    (call) async {
      if (call.method == 'init') {
        final id = (call.arguments as Map)['id'] as String;
        // The player reports itself ready, so songs load without waiting
        // for the 30 s transition timeout.
        messenger
          ..setMockMethodCallHandler(
            MethodChannel('com.ryanheise.just_audio.methods.$id'),
            (c) async => c.method == 'load'
                ? {'duration': 200 * 1000 * 1000}
                : <String, dynamic>{},
          )
          ..setMockStreamHandler(
            EventChannel('com.ryanheise.just_audio.events.$id'),
            _ReadyEvents(),
          )
          ..setMockStreamHandler(
            EventChannel('com.ryanheise.just_audio.data.$id'),
            _NoEvents(),
          );
      }
      return <String, dynamic>{};
    },
  );
}

void _mockPathProvider(String dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir,
      );
}

class _NoEvents extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}

  @override
  void onCancel(Object? arguments) {}
}

class _ReadyEvents extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    events.success({
      'processingState': 2, // ready
      'updateTime': DateTime.now().millisecondsSinceEpoch,
      'updatePosition': 0,
      'bufferedPosition': 30 * 1000 * 1000,
      'duration': 200 * 1000 * 1000,
      'currentIndex': 0,
      'icyMetadata': null,
      'androidAudioSessionId': null,
    });
  }

  @override
  void onCancel(Object? arguments) {}
}

/// Loads every font of the app (Inter, icons) so the screenshots use them.
Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'));
  for (final font in manifest as List) {
    final loader = FontLoader(font['family'] as String);
    for (final asset in font['fonts'] as List) {
      loader.addFont(rootBundle.load(asset['asset'] as String));
    }
    await loader.load();
  }
}

/// Four local songs with generated artwork and one .lrc, liked songs,
/// history and two playlists.
Future<List<Map<String, dynamic>>> _seedLibrary(String dir) async {
  const titles = [
    ('Sakura Night', 'Hikari Ensemble', [0xFFE91E63, 0xFF3F51B5]),
    ('Paper Cranes', 'Nami', [0xFF00BCD4, 0xFF1A237E]),
    ('Washi Dreams', 'Hikari Ensemble', [0xFFFF9800, 0xFFB71C1C]),
    ('Tokyo Rain', 'Kazu', [0xFF4CAF50, 0xFF004D40]),
  ];
  final songs = <Map<String, dynamic>>[];
  for (var i = 0; i < titles.length; i++) {
    final (title, artist, colors) = titles[i];
    final art = '$dir/art$i.png';
    await File(art).writeAsBytes(await _artwork(colors[0], colors[1]));
    final audio = '$dir/song$i.mp3';
    await File(audio).writeAsString('');
    {
      await File('$dir/song$i.lrc').writeAsString(
        '[00:00.50]Walking through the neon rain\n'
        '[00:04.00]Paper cranes above the train\n'
        '[00:08.00]Every fold a secret name\n'
        '[00:12.00]Light is falling, I remain\n'
        '[00:16.00]Hold the sky and let it go\n'
        '[00:20.00]Colours drifting soft and slow\n'
        '[00:24.00]Sakura night, sakura night\n'
        '[00:28.00]Fold the dark into the light\n',
      );
    }
    songs.add({
      'id': 'local_seed$i',
      'ytid': 'local_seed$i',
      'title': title,
      'artist': artist,
      'album': 'Origami',
      'audioPath': audio,
      'artworkPath': art,
      'highResImage': '',
      'lowResImage': '',
      'isLive': false,
      'isLocal': true,
      'dateAdded': 1700000000000 + i,
      'duration': 200 + i * 17,
    });
  }
  localSongs.value = songs;
  userRecentlyPlayed.value = [...songs.reversed];
  // A few months of listening for the "Vous" page.
  wrappedEnabled.value = true;
  final now = DateTime.now();
  for (var back = 4; back >= 0; back--) {
    final when = DateTime(now.year, now.month - back, 10);
    for (var i = 0; i < songs.length; i++) {
      final plays = (songs.length - i) + back % 3;
      for (var p = 0; p < plays; p++) {
        listeningStatsService.recordListening(
          songs[i],
          Duration(seconds: 150 + 20 * i + 30 * back),
          incrementPlayCount: true,
          listenedAt: when,
        );
      }
    }
  }
  userLikedSongsList.value = songs.take(2).toList();
  userCustomPlaylists.value = [
    {
      'ytid': 'customId-1',
      'title': 'Soirée papier',
      'source': 'user-created',
      'image': '$dir/art1.png',
      'list': songs,
    },
    {
      'ytid': 'customId-2',
      'title': 'Matin calme',
      'source': 'user-created',
      'image': '$dir/art3.png',
      'list': songs.take(2).toList(),
    },
  ];
  userLikedPlaylists.value = [
    {
      'ytid': 'PLseed1',
      'title': 'Lo-fi origami beats',
      'image': '$dir/art2.png',
      'source': 'youtube',
      'list': songs,
    },
  ];
  searchHistoryNotifier.value = ['lofi hip hop', 'city pop', 'joe hisaishi'];
  return songs;
}

Future<Uint8List> _artwork(int from, int to) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(400, 400);
  canvas
    ..drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(400, 400), [
          Color(from),
          Color(to),
        ]),
    )
    ..drawCircle(
      const Offset(260, 150),
      90,
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    )
    ..drawCircle(
      const Offset(120, 290),
      60,
      Paint()..color = Colors.black.withValues(alpha: 0.2),
    );
  final image = await recorder.endRecording().toImage(400, 400);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
