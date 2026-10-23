import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 앱은 글꼴을 번들하지 않고 기기 시스템 서체로 그린다(#503).
// fontFamily를 지정하지 않으면 Flutter가 플랫폼 기본 서체를 쓴다.
// https://docs.flutter.dev/cookbook/design/fonts
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('번들 글꼴 목록에는 Material 아이콘 글꼴만 있다', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final families = manifest
        .map((entry) => (entry as Map<String, dynamic>)['family'])
        .toSet();

    expect(families, {'MaterialIcons'});
  });

  test('lib 코드는 글꼴 family 이름을 직접 지정하지 않는다', () {
    final literalFamily = RegExp(r'''fontFamily:\s*['"]''');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (literalFamily.hasMatch(source) || source.contains('Pretendard')) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
