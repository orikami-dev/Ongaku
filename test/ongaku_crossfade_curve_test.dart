import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/sound/crossfade.dart';

void main() {
  test('the fade curves start and end in the right place', () {
    expect(ongakuFadeOut(0), closeTo(1, 1e-9));
    expect(ongakuFadeOut(1), closeTo(0, 1e-9));
    expect(ongakuFadeIn(0), closeTo(0, 1e-9));
    expect(ongakuFadeIn(1), closeTo(1, 1e-9));
  });

  test('both songs are clearly heard in the middle of the fade', () {
    expect(ongakuFadeOut(0.5), greaterThan(0.6));
    expect(ongakuFadeIn(0.5), greaterThan(0.6));
    // Never louder than one song at full volume, in power.
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      final power =
          ongakuFadeOut(t) * ongakuFadeOut(t) +
          ongakuFadeIn(t) * ongakuFadeIn(t);
      expect(power, lessThan(1.6));
    }
  });
}
