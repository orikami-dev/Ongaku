import 'package:flutter_test/flutter_test.dart';
import 'package:musify/ongaku/services/ongaku_updates.dart';

void main() {
  Map<String, Object?> apk({
    String package = 'com.orikami.ongaku',
    List<String> signers = const ['aa'],
    int code = 1340,
    String sha = 'abc',
  }) => {
    'package': package,
    'installedPackage': 'com.orikami.ongaku',
    'signers': signers,
    'installedSigners': ['aa'],
    'versionCode': code,
    'sha256': sha,
  };

  test('a newer Ongaku with the same key can be installed', () {
    expect(ongakuUpdateProblem(apk(), currentCode: 1330), isNull);
    expect(
      ongakuUpdateProblem(apk(), currentCode: 1330, expectedSha256: 'ABC'),
      isNull,
    );
  });

  test('anything else is refused', () {
    expect(
      ongakuUpdateProblem(apk(package: 'other.app'), currentCode: 1330),
      isNotNull,
    );
    expect(
      ongakuUpdateProblem(apk(signers: ['bb']), currentCode: 1330),
      isNotNull,
    );
    expect(ongakuUpdateProblem(apk(signers: []), currentCode: 1330), isNotNull);
    expect(ongakuUpdateProblem(apk(code: 1330), currentCode: 1330), isNotNull);
    expect(
      ongakuUpdateProblem(apk(), currentCode: 1330, expectedSha256: 'def'),
      isNotNull,
    );
  });
}
