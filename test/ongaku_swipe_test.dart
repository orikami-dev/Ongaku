import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/widgets/swipe_to_skip.dart';

void main() {
  test('a long or fast swipe changes song, a short one does not', () {
    expect(swipeSkipDirection(-150, 0, 300), 1);
    expect(swipeSkipDirection(150, 0, 300), -1);
    expect(swipeSkipDirection(-40, 0, 300), 0);
    expect(swipeSkipDirection(-20, -900, 300), 1);
    expect(swipeSkipDirection(20, 900, 300), -1);
  });
}
