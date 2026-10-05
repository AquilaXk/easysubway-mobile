// #443: 사용자에게 보이는 문구에 개발·내부 용어가 들어오지 못하게 막는 회귀 검사.
//
// lib/ 의 Dart 문자열 리터럴(주석 제외, 생성 코드 제외) 가운데 한글이 들어간
// 것을 모두 검사한다. 한글 리터럴은 화면 문구·스크린리더 라벨·스낵바·오류
// 안내가 되기 쉬우므로, 금지어가 들어 있으면 실패한다.
//
// 화면에 보이지 않는 문자열(로그·예외 진단·원천 데이터 매칭 키)은
// [_allowlist]에 파일·부분 문자열·사유를 적어 예외로 둔다. 사용자에게 보이는
// 문구는 여기에 넣지 말고 쉬운 말로 고친다. 예외가 더 이상 쓰이지 않으면 이
// 테스트가 실패해 목록에서 지우게 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 금지어. 한글이 포함된 리터럴에서만 찾는다. 영문은 대소문자를 구분하지 않는다.
const _bannedTerms = <String>[
  // 이동 조건·경로 내부 분류
  '계단회피', '무단차', '미확정', 'STEP_FREE', 'UNDETERMINED',
  // 데이터 품질·거버넌스
  '데이터 품질', 'Level', 'pilot', '파일럿', '검증', '게이트', '구간만 구현',
  // 데이터·시스템 구현 용어
  'asset', '근거', '원천', '스냅샷', '데이터팩', '무결성', '서명', '판정',
  '서버', 'API', '캐시', 'payload', 'action', 'Last Connection',
  // 면책·불확실성 안내(#443 QA): 상용 지하철 서비스는 확인되지 않은 것에 대해
  // 말하지 않고, 고장·점검이 확인된 시설만 사실로 표시한다.
  '반영하지 못', '반영되지 않', '정확하지 않', '확인되지 않았', '확인되지 않은', '보장하지 않',
];

/// 화면에 보이지 않는 문자열만 예외로 둔다(파일 경로 접미사, 부분 문자열, 사유).
const _allowlist = <_Allowed>[
  _Allowed(
    'lib/features/account/user_data_deletion.dart',
    'API 응답',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/notifications/notification_settings.dart',
    'API 요청',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/app/app_endpoints.dart',
    '서명 공개키',
    '업데이트 중단 진단 로그. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/core/database/catalog/catalog_schema_diagnostics.dart',
    '무결성 대조',
    '로컬 DB 진단 로그. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    '서버',
    '오류 보고 context와 예외 메시지. 화면에는 별도 쉬운 문구를 쓴다.',
  ),
  _Allowed(
    'lib/features/stations/data/station_api_repository.dart',
    'API 요청',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/favorites/favorite_facility.dart',
    'API 요청',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/service_notice/data/notice_repository.dart',
    '캐시',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/presentation/station_detail_body.dart',
    '게이트',
    '시설 원문에서 안/밖을 가려내는 매칭 키. 화면에는 개찰구 안/밖으로 표시한다.',
  ),
  _Allowed(
    'lib/features/stations/presentation/station_facility_card.dart',
    '게이트',
    '시설 원문에서 안/밖을 가려내는 매칭 키. 화면에는 표시하지 않는다.',
  ),
];

class _Allowed {
  const _Allowed(this.file, this.contains, this.reason);
  final String file;
  final String contains;
  final String reason;
}

class _Literal {
  const _Literal(this.line, this.text);
  final int line;
  final String text;
}

/// 주석을 건너뛰며 Dart 문자열 리터럴 본문을 뽑는다. `${...}` 보간식 안은 건너뛴다.
List<_Literal> _extractStringLiterals(String source) {
  final result = <_Literal>[];
  var i = 0;
  var line = 1;
  final n = source.length;
  while (i < n) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
    } else if (source.startsWith('//', i)) {
      while (i < n && source[i] != '\n') {
        i++;
      }
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? n : end + 2;
      line += '\n'.allMatches(source.substring(i, stop)).length;
      i = stop;
    } else if (c == "'" || c == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final triple = source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      final startLine = line;
      i += quote.length;
      final buffer = StringBuffer();
      while (i < n && !source.startsWith(quote, i)) {
        final ch = source[i];
        if (ch == '\n') {
          line++;
        }
        if (!raw && ch == r'\' && i + 1 < n) {
          buffer.write(source.substring(i, i + 2));
          i += 2;
        } else if (!raw && source.startsWith(r'${', i)) {
          var depth = 1;
          i += 2;
          while (i < n && depth > 0) {
            if (source[i] == '{') depth++;
            if (source[i] == '}') depth--;
            if (source[i] == '\n') line++;
            i++;
          }
        } else {
          buffer.write(ch);
          i++;
        }
      }
      i += quote.length;
      result.add(_Literal(startLine, buffer.toString()));
    } else {
      i++;
    }
  }
  return result;
}

final _hangul = RegExp('[가-힣]');

List<String> _bannedTermsIn(String text) {
  if (!_hangul.hasMatch(text)) {
    return const [];
  }
  // 보간된 변수 이름(`$actionLabel`)은 화면에 찍히는 글자가 아니므로 뺀다.
  final lower = text.replaceAll(RegExp(r'\$\w+'), '').toLowerCase();
  return [
    for (final term in _bannedTerms)
      if (lower.contains(term.toLowerCase())) term,
  ];
}

bool _isAllowed(String file, String text) => _allowlist.any(
  (allowed) => file.endsWith(allowed.file) && text.contains(allowed.contains),
);

Iterable<File> _libSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path;
    if (path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart') ||
        path.contains('lib/generated/')) {
      continue;
    }
    yield entity;
  }
}

void main() {
  group('검사기 자체', () {
    test('주석은 건너뛰고 문자열 안의 금지어는 찾는다', () {
      const source = '''
// '계단회피' 주석은 무시한다
final a = Text('무단차 경로');
/* '미확정' 블록 주석 */
final b = '일반 문구 \${x.length}개';
''';
      final literals = _extractStringLiterals(source);
      expect(literals.map((l) => l.text), ['무단차 경로', '일반 문구 개']);
      expect(literals.first.line, 2);
      expect(_bannedTermsIn(literals.first.text), ['무단차']);
      expect(_bannedTermsIn(literals.last.text), isEmpty);
    });

    test('한글이 없는 식별자 문자열은 검사하지 않는다', () {
      expect(_bannedTermsIn('STEP_FREE'), isEmpty);
      expect(_bannedTermsIn('assets/datapacks/source-inventory.json'), isEmpty);
    });
  });

  test('사용자 문구에 개발·내부 용어가 없다(허용 목록 외)', () {
    final violations = <String>[];
    final used = <_Allowed>{};
    for (final file in _libSources()) {
      for (final literal in _extractStringLiterals(file.readAsStringSync())) {
        final terms = _bannedTermsIn(literal.text);
        if (terms.isEmpty) continue;
        final allowed = _allowlist.where(
          (a) =>
              file.path.endsWith(a.file) && literal.text.contains(a.contains),
        );
        if (allowed.isNotEmpty) {
          used.addAll(allowed);
          continue;
        }
        violations.add(
          '${file.path}:${literal.line} ${terms.join(', ')} -> "${literal.text}"',
        );
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '사용자에게 보이는 문구는 쉬운 말로 고치고, 화면에 보이지 않는 문자열만 '
          'user_facing_copy_guard_test.dart 의 _allowlist에 사유와 함께 등록하세요.',
    );
    final unused = _allowlist.where((a) => !used.contains(a)).toList();
    expect(
      unused.map((a) => '${a.file} "${a.contains}"'),
      isEmpty,
      reason: '더 이상 쓰이지 않는 허용 목록 항목은 지우세요.',
    );
    // 허용 목록 사유는 반드시 적는다.
    expect(_allowlist.every((a) => a.reason.trim().isNotEmpty), isTrue);
    expect(_isAllowed('x.dart', 'y'), isFalse);
  });
}
