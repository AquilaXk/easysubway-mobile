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
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/attribution/presentation/data_source_attribution_screen.dart';
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
  // 추정·미지원 표현과 "~와 다를 수 있어요" 면책(#443 리뷰 F4).
  '다를 수 있', '추정', '미지원',
];

/// 화면에 보이지 않는 문자열만 예외로 둔다(파일 경로 접미사, 리터럴 전문, 사유).
/// 리터럴 전문이 정확히 같아야 통과한다. 보간식(`${...}`)은 뺀 형태로 적는다.
const _allowlist = <_Allowed>[
  _Allowed(
    'lib/app/app_endpoints.dart',
    'production 빌드에 이동 정보 서명 공개키가 주입되지 않아 업데이트를 시작하지 않았습니다.',
    '업데이트 중단 진단 로그. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/app/app_endpoints.dart',
    'production 빌드의 이동 정보 서명 공개키 형식이 올바르지 않아 업데이트를 시작하지 않았습니다.',
    '업데이트 중단 진단 로그. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/core/database/catalog/catalog_schema_diagnostics.dart',
    r'설치 팩 무결성 대조 실패로 재활성화하지 않고 강등함: pack=$artifact expected= actual=',
    '로컬 DB 진단 로그. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    '서버 시간표 조회 실패',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    r'서버에 연결할 수 없어 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    '서버 일자별 시간표 조회 실패',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    r'서버에 연결할 수 없어 일자별 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    '서버 다음 열차 시간표 조회 실패',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    r'서버에 연결할 수 없어 다음 열차 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/composite_station_timetable_repository.dart',
    r'서버 시간표를 불러올 수 없습니다: $stationId ($lineId)',
    '예외 메시지. 화면은 예외 종류만 보고 별도 쉬운 문구를 쓴다.',
  ),
  _Allowed(
    'lib/features/stations/data/station_api_repository.dart',
    '역 정보 API 요청 처리 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/data/station_api_repository.dart',
    '즐겨찾기 역 API 요청 처리 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/favorites/favorite_facility.dart',
    '즐겨찾기 시설 API 요청 처리 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/account/user_data_deletion.dart',
    '사용자 정보 삭제 API 응답 처리 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/notifications/notification_settings.dart',
    '알림 설정 API 요청 처리 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/service_notice/data/notice_repository.dart',
    '운행 공지 캐시를 읽는 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/service_notice/data/notice_repository.dart',
    '운행 공지 캐시를 저장하는 중 예외가 발생했습니다.',
    '오류 보고 context. 화면에 표시하지 않는다.',
  ),
  _Allowed(
    'lib/features/stations/presentation/station_detail_body.dart',
    '게이트 안',
    '시설 원문에서 안/밖을 가려내는 매칭 키. 화면에는 개찰구 안/밖으로 표시한다.',
  ),
  _Allowed(
    'lib/features/stations/presentation/station_detail_body.dart',
    '게이트 밖',
    '시설 원문에서 안/밖을 가려내는 매칭 키. 화면에는 개찰구 안/밖으로 표시한다.',
  ),
  _Allowed(
    'lib/features/stations/presentation/station_facility_card.dart',
    '게이트 안',
    '시설 원문에서 안/밖을 가려내는 매칭 키. 화면에는 표시하지 않는다.',
  ),
];

class _Allowed {
  const _Allowed(this.file, this.literal, this.reason);
  final String file;
  final String literal;
  final String reason;
}

class _Literal {
  const _Literal(this.line, this.text, [this.context = '']);
  final int line;
  final String text;

  /// 리터럴 바로 앞 코드 조각. 한글 없는 리터럴이 화면에 쓰이는지 가릴 때 쓴다.
  final String context;
}

/// 주석을 건너뛰며 Dart 문자열 리터럴 본문을 뽑는다.
/// - `${...}` 보간식 안의 리터럴은 별도 리터럴로 뽑는다.
/// - 사이에 쉼표 등 없이 붙어 있는 리터럴(`'계단' '회피'`)은 하나로 잇는다.
List<_Literal> _extractStringLiterals(String source) {
  final scanner = _Scanner(source);
  scanner.scanCode(untilCloseBrace: false);
  return scanner.out;
}

class _Scanner {
  _Scanner(this.s);

  final String s;
  final out = <_Literal>[];
  int i = 0;
  int line = 1;

  bool _isQuoteAt(int index) {
    if (index >= s.length) return false;
    final c = s[index];
    if (c == "'" || c == '"') return true;
    return c == 'r' &&
        index + 1 < s.length &&
        (s[index + 1] == "'" || s[index + 1] == '"') &&
        (index == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(s[index - 1]));
  }

  void _skipTrivia() {
    while (i < s.length) {
      final c = s[i];
      if (c == '\n') {
        line++;
        i++;
      } else if (c == ' ' || c == '\t' || c == '\r') {
        i++;
      } else if (s.startsWith('//', i)) {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        final stop = end < 0 ? s.length : end + 2;
        line += '\n'.allMatches(s.substring(i, stop)).length;
        i = stop;
      } else {
        break;
      }
    }
  }

  /// 코드 모드로 읽는다. [untilCloseBrace]면 짝이 맞는 `}`에서 멈춘다.
  void scanCode({required bool untilCloseBrace}) {
    var depth = 0;
    while (i < s.length) {
      _skipTrivia();
      if (i >= s.length) return;
      final c = s[i];
      if (_isQuoteAt(i)) {
        _scanLiteralRun();
      } else if (c == '{') {
        depth++;
        i++;
      } else if (c == '}') {
        if (untilCloseBrace && depth == 0) {
          i++;
          return;
        }
        depth--;
        i++;
      } else {
        i++;
      }
    }
  }

  /// 붙어 있는 리터럴 묶음을 읽어 하나로 잇는다.
  void _scanLiteralRun() {
    final startLine = line;
    final context = s
        .substring(i < 60 ? 0 : i - 60, i)
        .replaceAll(RegExp(r'\s+'), ' ');
    final buffer = StringBuffer();
    while (_isQuoteAt(i)) {
      buffer.write(_scanOneLiteral());
      _skipTrivia();
    }
    out.add(_Literal(startLine, buffer.toString(), context));
  }

  String _scanOneLiteral() {
    final raw = s[i] == 'r';
    if (raw) i++;
    final c = s[i];
    final triple = s.startsWith(c * 3, i);
    final quote = triple ? c * 3 : c;
    i += quote.length;
    final buffer = StringBuffer();
    while (i < s.length && !s.startsWith(quote, i)) {
      final ch = s[i];
      if (ch == '\n') line++;
      if (!raw && ch == r'\' && i + 1 < s.length) {
        buffer.write(s.substring(i, i + 2));
        i += 2;
      } else if (!raw && s.startsWith(r'${', i)) {
        i += 2;
        scanCode(untilCloseBrace: true);
      } else {
        buffer.write(ch);
        i++;
      }
    }
    i += quote.length;
    return buffer.toString();
  }
}

final _hangul = RegExp('[가-힣]');

/// 한글 없는 리터럴이 화면에 쓰이는 자리(Text, 스크린리더 라벨, 툴팁 등)인지.
final _visibleArgContext = RegExp(
  r'(Text\(|Text\.rich\(|semanticsLabel:|label:|tooltip:|hint:|hintText:|'
  r'labelText:|title:|subtitle:|message:|content:|value:|helperText:|'
  r'errorText:)\s*(const\s+)?$',
);
final _latin = RegExp('[A-Za-z]');

List<String> _bannedTermsIn(String text, {String context = ''}) {
  // 보간된 변수 이름(`$actionLabel`)은 화면에 찍히는 글자가 아니므로 뺀다.
  final stripped = text.replaceAll(RegExp(r'\$\w+'), '');
  final lower = stripped.toLowerCase();
  if (_hangul.hasMatch(text)) {
    return [
      for (final term in _bannedTerms)
        if (lower.contains(term.toLowerCase())) term,
    ];
  }
  // 한글이 없는 리터럴은 식별자·경로가 대부분이라, 화면에 쓰이는 인자일 때만
  // 영문 금지어를 단어 단위로 찾는다.
  if (!_latin.hasMatch(text) || !_visibleArgContext.hasMatch(context)) {
    return const [];
  }
  return [
    for (final term in _bannedTerms)
      if (_latin.hasMatch(term) &&
          !_hangul.hasMatch(term) &&
          RegExp(
            '(^|[^A-Za-z0-9])${RegExp.escape(term)}(\$|[^A-Za-z0-9])',
            caseSensitive: false,
          ).hasMatch(stripped))
        term,
  ];
}

bool _matchesAllowed(_Allowed allowed, String file, String text) =>
    file.endsWith(allowed.file) && text == allowed.literal;

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

    test('허용 목록은 리터럴 전문이 같을 때만 통과시킨다', () {
      const entry = _Allowed('lib/a/card.dart', '게이트 안', '테스트용 매칭 키');
      expect(_matchesAllowed(entry, 'lib/a/card.dart', '게이트 안'), isTrue);
      // 허용 문자열을 일부로 품은 다른 문구(우회 시도)는 통과하지 못한다.
      expect(
        _matchesAllowed(entry, 'lib/a/card.dart', '엘리베이터 게이트 안 정보를 반영하지 못했어요'),
        isFalse,
      );
      expect(_matchesAllowed(entry, 'lib/b/other.dart', '게이트 안'), isFalse);
    });

    test('보간식 안의 리터럴도 별도 리터럴로 찾는다', () {
      const source = r'''
final a = '${flag ? '무단차 경로' : ''}';
final b = '$label ${isAvailable ? '있음' : '없음'}';
''';
      final texts = _extractStringLiterals(source).map((l) => l.text).toList();
      expect(texts, containsAll(['무단차 경로', '있음', '없음']));
      expect(texts.where((t) => _bannedTermsIn(t).isNotEmpty), ['무단차 경로']);
    });

    test('붙어 있는 리터럴은 하나로 이어 검사한다', () {
      const source = r'''
final a = Text('계단' '회피 경로');
final b = const [
  '정보를 ' // 줄 끝 주석
  '반영하지 못했어요',
];
''';
      final texts = _extractStringLiterals(source).map((l) => l.text).toList();
      expect(texts, ['계단회피 경로', '정보를 반영하지 못했어요']);
      expect(_bannedTermsIn(texts.first), ['계단회피']);
      expect(_bannedTermsIn(texts.last), ['반영하지 못']);
    });

    test('한글 없는 리터럴도 화면에 쓰이는 자리면 영문 금지어를 찾는다', () {
      const source = r'''
final a = Text('Last Connection');
final b = Semantics(label: 'Level 2', child: x);
final c = const Text('payload');
final d = 'STEP_FREE';
final e = Text('OK');
final f = Tooltip(message: 'asset', child: x);
''';
      final flagged = <String>[
        for (final l in _extractStringLiterals(source))
          if (_bannedTermsIn(l.text, context: l.context).isNotEmpty) l.text,
      ];
      expect(flagged, ['Last Connection', 'Level 2', 'payload', 'asset']);
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
        final terms = _bannedTermsIn(literal.text, context: literal.context);
        if (terms.isEmpty) continue;
        final allowed = _allowlist.where(
          (a) => file.path.endsWith(a.file) && literal.text.contains(a.literal),
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
      unused.map((a) => '${a.file} "${a.literal}"'),
      isEmpty,
      reason: '더 이상 쓰이지 않는 허용 목록 항목은 지우세요.',
    );
    // 허용 목록 사유는 반드시 적는다.
    expect(_allowlist.every((a) => a.reason.trim().isNotEmpty), isTrue);
  });

  test('출처 화면에 보일 자료 이름에 내부 꼬리표나 금지어가 남지 않는다', () {
    final inventory =
        jsonDecode(
              File('assets/datapacks/source-inventory.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final internalTag = RegExp(
      r'membership|admission|canary|route_map|_positions|\(KRIC|snapshot|검증',
      caseSensitive: false,
    );
    final problems = <String>[];
    var checked = 0;
    for (final source
        in (inventory['sources']! as List).cast<Map<String, Object?>>()) {
      if (!isListedDataSource(source)) continue;
      checked++;
      final name = userFacingSourceName('${source['displayName']}');
      if (internalTag.hasMatch(name) || _bannedTermsIn(name).isNotEmpty) {
        problems.add('${source['id']}: $name');
      }
    }
    expect(checked, greaterThan(50));
    expect(problems, isEmpty);
  });
}
