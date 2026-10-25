import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/services/ongaku_logs.dart';

void main() {
  test('the scrubber removes what is personal', () {
    final scrubber = OngakuScrubber(
      titles: ['Paper Moons', 'Paper Moons (Live)'],
      artists: ['Nova Lane'],
      albums: ['Night Drive'],
      deviceNames: ['Living room speaker'],
    );
    final out = scrubber.scrub(
      'mail jane.doe@example.com\n'
      'file /storage/emulated/0/Music/song.mp3 ok\n'
      'url https://example.com/watch?v=abc&token=1 end\n'
      'ip 192.168.1.20 mac 3C:22:FB:10:AA:01\n'
      'Paper Moons (Live) by nova lane on Night Drive\n'
      'output Living room speaker\n'
      'play dQw4w9WgXcQ then dQw4w9WgXcQ then PLabcdefghijklmn\n'
      'player: completed exception',
    );
    expect(out, contains('<email>'));
    expect(out, isNot(contains('jane')));
    expect(out, contains('file <fichier> ok'));
    expect(out, contains('https://example.com/watch?<masqué> end'));
    expect(out, contains('ip <ip> mac <mac>'));
    expect(out, contains('<titre> by <artiste> on <album>'));
    expect(out, contains('output <appareil>'));
    expect(out, matches(RegExp(r'play (<id-\d>) then \1 then <id-\d>')));
    expect(out, isNot(contains('dQw4w9WgXcQ')));
    // Ordinary 11-letter words stay.
    expect(out, contains('player: completed exception'));
  });

  test('the journal keeps the last lines only', () {
    for (var i = 0; i < ongakuJournalLines + 20; i++) {
      OngakuJournal.add('line $i');
    }
    final lines = OngakuJournal.text.split('\n');
    expect(lines.length, ongakuJournalLines);
    expect(lines.last, 'line ${ongakuJournalLines + 19}');
  });
}
