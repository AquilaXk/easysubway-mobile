import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #423: 서버 응답에 없는 값을 추정·상수·채움 문구로 표시하던 흔적이
/// 제품 코드(lib/)에 다시 들어오지 않게 막는다.
void main() {
  test('(14) lib에 추정 정차역·고정 운임(1,400·1400)·채움 방면 문구가 0건이다', () {
    const forbidden = <String>[
      '1,400',
      '1400',
      '/ 2.2',
      '_legStopCount',
      '_estimatedStopCount',
      '행선 방면',
    ];
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final token in forbidden) {
        if (source.contains(token)) hits.add('${entity.path}: $token');
      }
    }

    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
