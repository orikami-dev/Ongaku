import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/ongaku/widgets/ongaku_ui_scale.dart';

void main() {
  test('the interface fits the screen and its resolution', () {
    // Common phones stay as drawn.
    expect(ongakuUiScale(const Size(392, 850), 2.75), 1);
    expect(ongakuUiScale(const Size(384, 832), 3), 1);
    // Narrow phones shrink, wide ones grow a little.
    expect(ongakuUiScale(const Size(360, 780), 3), 0.92);
    expect(ongakuUiScale(const Size(430, 932), 3), 1.04);
    // Low resolution: smaller, to stay sharp.
    expect(ongakuUiScale(const Size(360, 640), 1.5), 0.92);
    expect(ongakuUiScale(const Size(412, 732), 1.5), 0.94);
    // Landscape phones never grow; tablets and open foldables are left be.
    expect(ongakuUiScale(const Size(932, 430), 3), 1);
    expect(ongakuUiScale(const Size(673, 841), 2.6), 1);
  });

  testWidgets('a scaled app still fills the screen and takes taps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var taps = 0;
    late Size inner;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => OngakuUiScale(child: child!),
        home: Builder(
          builder: (context) {
            inner = MediaQuery.sizeOf(context);
            return Align(
              alignment: Alignment.bottomRight,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('tap'),
              ),
            );
          },
        ),
      ),
    );
    expect(inner.width, closeTo(320 / 0.86, 0.5));
    await tester.tap(find.text('tap'));
    expect(taps, 1);
  });
}
