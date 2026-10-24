import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/screens/ongaku_sound_page.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/ongaku/sound/sound_math.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('ongaku_sound_page');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  testWidgets('a sound layer can be chosen', (tester) async {
    tester.view.physicalSize = const Size(390, 2400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    OngakuSoundEngine.supported.value = true;
    await tester.pumpWidget(const MaterialApp(home: OngakuSoundPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(soundLayer.value, SoundLayer.rock);
    await tester.tap(find.text('Jazz'));
    await tester.pumpAndSettle();
    expect(soundLayer.value, SoundLayer.jazz);
  });
}
