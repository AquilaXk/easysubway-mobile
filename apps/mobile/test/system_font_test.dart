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

  test('lib 코드는 글꼴 family를 지정하지 않는다', () {
    // 문자열 리터럴뿐 아니라 상수·변수로 돌려 넘기는 표기도 fontFamily 식별자로 잡는다.
    // 그려진 결과는 sweep의 renderedTypographyViolations가 다시 본다.
    final familyIdentifier = RegExp(r'\bfontFamily(?:Fallback)?\b|Pretendard');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          entity.path == _fanMenuSource) {
        continue;
      }
      if (familyIdentifier.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });

  test('팬 메뉴는 주변 DefaultTextStyle의 family만 CustomPaint로 넘긴다', () {
    // CustomPaint는 DefaultTextStyle을 상속하지 못해 family를 인자로 받는다.
    final assignments = RegExp(
      r'fontFamily:\s*([^,\n]+)',
    ).allMatches(File(_fanMenuSource).readAsStringSync());

    expect(assignments, isNotEmpty);
    for (final match in assignments) {
      expect(
        match.group(1),
        anyOf('DefaultTextStyle.of(context).style.fontFamily', 'fontFamily'),
      );
    }
  });
}

const _fanMenuSource =
    'lib/features/network_map/presentation/station_fan_menu.dart';
