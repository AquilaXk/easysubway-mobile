import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

  test('pubspec.yaml은 커스텀 번들 글꼴 섹션이나 Pretendard 자산을 선언하지 않는다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final activeLines = pubspec
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'#.*$'), '').trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n');

    expect(
      RegExp(r'^\s*fonts\s*:', multiLine: true).hasMatch(activeLines),
      isFalse,
    );
    expect(
      RegExp(
        r'Pretendard|\.(?:ttf|otf)\b',
        caseSensitive: false,
      ).hasMatch(activeLines),
      isFalse,
    );
  });

  test('lib 코드는 글꼴 family나 Pretendard를 지정하지 않는다', () {
    // 문자열 리터럴뿐 아니라 상수·변수로 돌려 넘기는 표기도 fontFamily 식별자로 잡는다.
    // 그려진 결과는 sweep의 renderedTypographyViolations가 다시 본다.
    final familyIdentifier = RegExp(
      r'\bfontFamily(?:Fallback)?\b|Pretendard',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (familyIdentifier.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });

  test('test 디렉터리(이 파일 제외)에도 Pretendard 잔존 참조가 없다', () {
    final pretendardPattern = RegExp(r'Pretendard', caseSensitive: false);
    final offenders = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll(r'\', '/');
      if (normalizedPath == 'test/system_font_test.dart') {
        continue;
      }
      if (!normalizedPath.endsWith('.dart') &&
          !normalizedPath.endsWith('.json')) {
        continue;
      }
      if (pretendardPattern.hasMatch(entity.readAsStringSync())) {
        offenders.add(normalizedPath);
      }
    }

    expect(offenders, isEmpty);
  });

  testWidgets('200% 큰 글자(320x640)에서 한·영 문구가 시스템 기본 서체로 오버플로 없이 그려진다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('강남역 · Gangnam Station'),
                  SizedBox(height: 8),
                  Text('경로를 찾지 못했어요. Please try again shortly.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final textElement = tester.element(find.text('강남역 · Gangnam Station'));
    final defaultStyle = DefaultTextStyle.of(textElement).style;
    expect(
      defaultStyle.fontFamily == null ||
          !defaultStyle.fontFamily!.toLowerCase().contains('pretendard'),
      isTrue,
    );
  });
}
