import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_code_mask.dart';
import '../support/slop_pattern_scan.dart';
import '../support/slop_ratchet.dart';

// #515 AI 슬롭 디자인 패턴 증가 차단 가드.
//
// 규칙: 기준선(slop_pattern_baseline.json)보다 늘리지 않는다. 기준선이 없는 범주와 파일은 0이다.
// 줄이면 기준선도 같은 PR에서 내린다:
//   flutter test test/guards/slop_pattern_guard_test.dart --dart-define=TIGHTEN_SLOP_BASELINE=true
// 이 명령은 기준선을 내리기만 한다. 올리려면 JSON을 손으로 고치고 PR에서 이유를 적는다.

const _testPath = 'test/guards/slop_pattern_guard_test.dart';
const _baselinePath = 'test/guards/slop_pattern_baseline.json';
const _tighten = bool.fromEnvironment('TIGHTEN_SLOP_BASELINE');
const _bs = r'\';

List<int> _lines(String source, String ruleId, {String path = 'lib/a.dart'}) =>
    [
      for (final hit in scanSlopSource(source, path: path))
        if (hit.ruleId == ruleId) hit.line,
    ];

int _count(String source, String ruleId, {String path = 'lib/a.dart'}) =>
    _lines(source, ruleId, path: path).length;

void main() {
  group('Dart 소스 마스킹', () {
    test('주석 본문은 코드 뷰에서 지워지고 줄 위치는 유지된다', () {
      const source = '''
// BoxDecoration 주석
/// 문서 주석 Icons.close
/* 블록 /* 중첩 */ 아직 주석 */
final a = 1;
''';
      final masked = maskDartSource(source);
      expect(masked.code, isNot(contains('BoxDecoration')));
      expect(masked.code, isNot(contains('Icons')));
      expect(masked.code, isNot(contains('중첩')));
      expect(masked.code, isNot(contains('아직')));
      expect(masked.code.length, source.length);
      expect(masked.code.split('\n').length, source.split('\n').length);
      expect(masked.code, contains('final a = 1;'));
    });

    test('문자열 본문은 지워지고 보간식 안의 코드는 남는다', () {
      final masked = maskDartSource(
        r"final a = 'Icons.close ${BoxDecoration()} 끝';",
      );
      expect(masked.code, contains('BoxDecoration()'));
      expect(masked.code, isNot(contains('Icons.close')));
      expect(masked.literals.single.text, 'Icons.close  끝');
    });

    test('주석 속 따옴표가 문자열을 열지 않는다', () {
      final masked = maskDartSource("// don't\nfinal a = Icons.close;\n");
      expect(masked.code, contains('Icons.close'));
      expect(masked.literals, isEmpty);
    });

    test('raw 문자열은 이스케이프와 보간을 해석하지 않는다', () {
      final masked = maskDartSource(
        r"final a = r'\u{2014} ${x}'; final b = Icons.add;",
      );
      expect(masked.literals.first.text, r'\u{2014} ${x}');
      expect(masked.code, contains('Icons.add'));
    });

    test('삼중 따옴표 문자열은 줄을 넘어도 줄 번호를 유지한다', () {
      const source = "final a = '''\n첫째\n둘째\n''';\nfinal b = Icons.add;\n";
      final masked = maskDartSource(source);
      expect(masked.literals.single.line, 1);
      expect(masked.code.split('\n')[4], contains('Icons.add'));
    });

    test('유니코드 이스케이프는 실제 문자로 풀리고 이중 역슬래시는 풀리지 않는다', () {
      final masked = maskDartSource(
        "final a = '${_bs}u2014'; final b = '${_bs}u{1F680}'; final c = '$_bs${_bs}u2014';",
      );
      expect(masked.literals[0].text, '\u{2014}');
      expect(masked.literals[1].text, '\u{1F680}');
      expect(masked.literals[2].text, '${_bs}u2014');
    });

    test('쉼표 없이 붙어 있는 문자열은 하나의 리터럴로 잇고 쉼표로 나뉜 문자열은 따로 둔다', () {
      const source =
          "final a = '가' // 줄 끝 주석\n    /* 블록 */ '나' \"다\";\n"
          "final b = ['라', '마'];\n";
      final masked = maskDartSource(source);
      expect(masked.literals.map((literal) => literal.text), ['가나다', '라', '마']);
      expect(masked.literals.first.line, 1);
      expect(masked.literals.first.start, source.indexOf("'가'"));
    });

    test('코드 한 글자라도 끼면 붙은 문자열이 아니고, 보간식 안에서도 붙은 문자열을 잇는다', () {
      final apart = maskDartSource("final a = 'x' + 'y';");
      expect(apart.literals.map((literal) => literal.text), ['x', 'y']);
      final nested = maskDartSource(r"final a = '바깥 ${f('안' '쪽')} 끝' '뒤';");
      expect(nested.literals.map((literal) => literal.text), ['안쪽', '바깥  끝뒤']);
    });

    test('블록 주석은 중첩되어 안쪽 */ 뒤의 따옴표가 문자열을 열지 않는다', () {
      final masked = maskDartSource(
        "/* a /* b */ it's */ final y = '계단'; final z = Icons.add;",
      );
      expect(masked.literals.map((literal) => literal.text), ['계단']);
      expect(masked.code, contains('Icons.add'));
    });

    test('줄바꿈과 탭 이스케이프는 실제 문자로 풀리고 나머지 이스케이프는 문자 그대로 남는다', () {
      final masked = maskDartSource(
        "final a = 'x${_bs}ny${_bs}tz$_bs'w$_bs\$v';",
      );
      expect(masked.literals.single.text, "x\ny\tz'w\$v");
    });

    test('보간식 안의 중첩 문자열과 중괄호도 코드로 읽고 바깥 문자열 본문은 지운다', () {
      final masked = maskDartSource(
        r"final a = '그림 ${f({'k': Icons.add})} 끝'; final b = Icons.close;",
      );
      expect(masked.code, contains('Icons.add'));
      expect(masked.code, contains('Icons.close'));
      expect(masked.code, isNot(contains('그림')));
      expect(masked.literals.map((literal) => literal.text), ['k', '그림  끝']);
    });

    test('닫히지 않은 문자열과 괄호도 멈추고 세지 않는다', () {
      expect(
        () => scanSlopSource("final a = 'abc", path: 'lib/a.dart'),
        returnsNormally,
      );
      expect(
        () => scanSlopSource(r"final a = '${Icons.add", path: 'lib/a.dart'),
        returnsNormally,
      );
      expect(_count('Border(left: BorderSide(width: 4', 'side_border'), 0);
      expect(
        _count('Border(left: BorderSide(width: 4), ' * 2000, 'side_border'),
        0,
      );
    });
  });

  group('범주 규칙', () {
    const rulesWithCases = <String, ({List<String> hits, List<String> clean})>{
      'gradient': (
        hits: [
          'final a = const LinearGradient(colors: []);',
          'final a = RadialGradient(colors: []);',
          'final a = ui.Gradient.linear(a, b, c, d);',
        ],
        clean: [
          '// LinearGradient 설명',
          "final a = 'LinearGradient';",
          'final a = MyGradientHelper();',
        ],
      ),
      'blur': (
        hits: [
          'BackdropFilter(filter: f)',
          'final f = ImageFilter.blur(sigmaX: 2);',
          'ImageFiltered(imageFilter: f)',
          'final p = MaskFilter.blur(BlurStyle.normal, 2);',
        ],
        clean: [
          'final f = ImageFilter.matrix(m);',
          '// BackdropFilter 는 쓰지 않는다',
          'final r = blurRadius;',
        ],
      ),
      'shadow': (
        hits: [
          'const BoxShadow(blurRadius: 4)',
          'final s = Shadow(blurRadius: 2);',
          'Material(shadowColor: c)',
          'Material(elevation: 2)',
          'Material(elevation: 0.5)',
        ],
        clean: [
          'Material(elevation: 0)',
          'Material(elevation: 0.0)',
          'Material(elevation: tokenElevation)',
          "final s = 'shadowColor: c';",
          'final s = ShadowedBox();',
        ],
      ),
      'bounce': (
        hits: [
          'curve: Curves.bounceOut',
          'curve: Curves.elasticInOut',
          'curve: Curves.easeOutBack',
          'curve: ElasticOutCurve()',
          'curve: Cubic(0.68, -0.55, 0.265, 1.55)',
          'SpringDescription(mass: 1, stiffness: 1, damping: 1)',
        ],
        clean: [
          'curve: Curves.easeOut',
          'curve: Curves.easeInOutCubic',
          'curve: Curves.fastOutSlowIn',
          'curve: Cubic(0.4, 0.0, 0.2, 1.0)',
          'curve: Cubic(0.2, 0, 0, 1.1)',
          '// Curves.bounceOut 금지',
        ],
      ),
      'side_border': (
        hits: [
          'Border(left: BorderSide(color: c, width: 4))',
          'Border(top: BorderSide(width: 3.0, color: c))',
          'BorderDirectional(start: BorderSide(width: 4))',
          'Border(left: BorderSide(width: 4), bottom: BorderSide(width: 1))',
          'Border(\n  right: BorderSide(\n    color: c,\n    width: 5,\n  ),\n)',
        ],
        clean: [
          'Border(bottom: BorderSide(color: c))',
          'Border(top: BorderSide(width: 1))',
          'Border.all(width: 4)',
          'Border(left: BorderSide(width: 3), right: BorderSide(width: 3))',
          'Border(top: BorderSide(width: 2))',
          'Border(left: BorderSide(width: EasySubwayStroke.thick))',
          'Border(left: someSide)',
          'RoundedRectangleBorder(side: BorderSide(width: 4))',
          '// Border(left: BorderSide(width: 4))',
        ],
      ),
      'emoji': (
        hits: [
          "final a = '✨ 새 기능';",
          "final a = '🚇 지하철';",
          r"final a = '\u{1F680}';",
          "final a = '${_bs}u2728';",
          "final a = '\u{2B50}';",
        ],
        clean: [
          '// ✨ 주석은 화면에 보이지 않는다',
          "final a = '가까운 역';",
          "final a = '→ 다음';",
          "final a = '© 2026';",
          "final a = '·';",
        ],
      ),
      'long_dash': (
        hits: [
          "final a = '가 — 나';",
          "final a = '9–10';",
          "final a = '${_bs}u2014';",
        ],
        clean: [
          '// 주석 — 설명',
          '/// 문서 — 설명',
          "final a = '가-나';",
          "final a = 'a -- b';",
          r"final a = '\\u2014';",
        ],
      ),
      'raw_radius': (
        hits: [
          'BorderRadius.circular(8)',
          'BorderRadius.circular( 12.0 )',
          'Radius.circular(4)',
          'BorderRadius.all(Radius.circular(4))',
        ],
        clean: [
          'BorderRadius.circular(EasySubwayRadius.control)',
          'Radius.circular(radius)',
          'BorderRadius.zero',
          '// BorderRadius.circular(8)',
        ],
      ),
      'raw_color': (
        hits: [
          'final c = Colors.red;',
          'final c = Colors.white;',
          'final c = Color(0xFF112233);',
          'final c = Color.fromARGB(255, 0, 0, 0);',
          'final c = Color.fromRGBO(0, 0, 0, 0.5);',
        ],
        clean: [
          'final c = Colors.transparent;',
          'final c = EasySubwayColors.ink;',
          'final c = MyColors.red;',
          'final c = Color(value);',
          '// Colors.red',
        ],
      ),
      'box_decoration': (
        hits: [
          'Container(decoration: BoxDecoration(color: c))',
          'const BoxDecoration()',
        ],
        clean: [
          'ShapeDecoration(shape: s)',
          'DecoratedBox(decoration: d)',
          '// BoxDecoration',
          "final a = 'BoxDecoration(';",
        ],
      ),
      'icon': (
        hits: ['Icon(Icons.close)', 'final i = Icons.arrow_back_ios_new;'],
        clean: [
          'Icon(CupertinoIcons.back)',
          'final i = MyIcons.close;',
          "final i = 'Icons.close';",
          '// Icons.close',
        ],
      ),
    };

    test('모든 규칙이 사례표에 있고 사례표의 규칙이 모두 존재한다', () {
      expect(
        slopRules.map((rule) => rule.id).toSet(),
        rulesWithCases.keys.toSet(),
      );
    });

    for (final entry in rulesWithCases.entries) {
      test('${entry.key}: 슬롭 코드는 걸리고 닮은 정상 코드는 걸리지 않는다', () {
        for (final source in entry.value.hits) {
          expect(
            _count(source, entry.key),
            greaterThanOrEqualTo(1),
            reason: '걸려야 한다: $source',
          );
        }
        for (final source in entry.value.clean) {
          expect(_count(source, entry.key), 0, reason: '걸리면 안 된다: $source');
        }
      });
    }

    test('토큰 정의 파일은 원시 반경과 원시 색을 센다고 막지 않는다', () {
      for (final path in [
        'lib/design_tokens.dart',
        'lib/accessible_design.dart',
      ]) {
        expect(_count('BorderRadius.circular(8)', 'raw_radius', path: path), 0);
        expect(
          _count('final c = Color(0xFF112233);', 'raw_color', path: path),
          0,
        );
      }
      expect(
        _count(
          'BoxDecoration()',
          'box_decoration',
          path: 'lib/design_tokens.dart',
        ),
        1,
      );
    });

    test('생성 코드는 검사하지 않는다', () {
      expect(_count('Icons.close', 'icon', path: 'lib/a.g.dart'), 0);
      expect(
        _count('Icons.close', 'icon', path: 'lib/generated/journey_v3/x.dart'),
        0,
      );
    });

    test('같은 줄에 여러 번 나오면 모두 센다', () {
      expect(_count('final a = [Icons.add, Icons.close];', 'icon'), 2);
    });

    test('히트는 1부터 시작하는 줄 번호를 돌려준다', () {
      expect(_lines('final a = 1;\n\nfinal b = Icons.add;\n', 'icon'), [3]);
      expect(_lines("final a = '''\n✨\n''';", 'emoji'), [1]);
    });
  });

  group('기준선 ratchet', () {
    SlopCounts counts(Map<String, Map<String, int>> value) => value;

    test('같으면 통과하고 1 늘면 증가로 잡는다', () {
      final baseline = counts({
        'icon': {'lib/a.dart': 2},
      });
      expect(slopRatchetDeltas(baseline, baseline), isEmpty);
      final deltas = slopRatchetDeltas(
        counts({
          'icon': {'lib/a.dart': 3},
        }),
        baseline,
      );
      expect(deltas, hasLength(1));
      expect(deltas.single.kind, SlopDeltaKind.increase);
      expect(deltas.single.path, 'lib/a.dart');
      expect(deltas.single.ruleId, 'icon');
      expect([deltas.single.actual, deltas.single.baseline], [3, 2]);
    });

    test('기준선에 없는 파일과 0건 범주의 위반은 기준선 0 대비 증가다', () {
      final deltas = slopRatchetDeltas(
        counts({
          'icon': {'lib/new.dart': 1},
          'gradient': {'lib/a.dart': 1},
        }),
        counts({
          'icon': {'lib/a.dart': 2},
        }),
      );
      final increases = deltas
          .where((delta) => delta.kind == SlopDeltaKind.increase)
          .map((delta) => '${delta.ruleId} ${delta.path} ${delta.baseline}')
          .toSet();
      expect(increases, {'icon lib/new.dart 0', 'gradient lib/a.dart 0'});
    });

    test('줄었는데 기준선이 그대로면 낡은 기준선으로 잡는다', () {
      final deltas = slopRatchetDeltas(
        counts({
          'icon': {'lib/a.dart': 1},
        }),
        counts({
          'icon': {'lib/a.dart': 2},
          'box_decoration': {'lib/gone.dart': 4},
        }),
      );
      expect(deltas.map((delta) => delta.kind).toSet(), {SlopDeltaKind.stale});
      expect(
        deltas.map(
          (delta) => '${delta.path} ${delta.actual}<${delta.baseline}',
        ),
        unorderedEquals(['lib/a.dart 1<2', 'lib/gone.dart 0<4']),
      );
    });

    test('tighten은 내리기만 하고 0이 된 항목을 지운다', () {
      final tightened = tightenSlopBaseline(
        counts({
          'icon': {'lib/a.dart': 1, 'lib/b.dart': 9, 'lib/new.dart': 1},
          'gradient': {'lib/x.dart': 1},
        }),
        counts({
          'icon': {'lib/a.dart': 3, 'lib/b.dart': 2, 'lib/gone.dart': 1},
        }),
      );
      expect(tightened, {
        'icon': {'lib/a.dart': 1, 'lib/b.dart': 2},
      });
    });

    test('기준선을 파싱하고 다시 인코딩하면 정렬된 같은 내용이 나온다', () {
      final text = encodeSlopBaseline({
        for (final rule in slopRules) rule.id: <String, int>{},
        'icon': {'lib/b.dart': 2, 'lib/a.dart': 1},
      });
      final parsed = parseSlopBaseline(text);
      expect(parsed['icon'], {'lib/a.dart': 1, 'lib/b.dart': 2});
      expect(encodeSlopBaseline(parsed), text);
      expect(text.indexOf('lib/a.dart'), lessThan(text.indexOf('lib/b.dart')));
    });

    test('범주가 빠졌거나 모르는 범주거나 건수가 양수가 아니면 기준선을 거부한다', () {
      Map<String, Object?> valid() => {
        'schemaVersion': 1,
        'rules': {for (final rule in slopRules) rule.id: <String, Object?>{}},
      };
      expect(() => parseSlopBaseline(jsonEncode(valid())), returnsNormally);

      final missing = valid();
      (missing['rules']! as Map<String, Object?>).remove('icon');
      expect(
        () => parseSlopBaseline(jsonEncode(missing)),
        throwsFormatException,
      );

      final unknown = valid();
      (unknown['rules']! as Map<String, Object?>)['made_up'] =
          <String, Object?>{};
      expect(
        () => parseSlopBaseline(jsonEncode(unknown)),
        throwsFormatException,
      );

      final zero = valid();
      ((zero['rules']! as Map<String, Object?>)['icon']!
              as Map<String, Object?>)['lib/a.dart'] =
          0;
      expect(() => parseSlopBaseline(jsonEncode(zero)), throwsFormatException);
    });

    test('실패 메시지는 파일, 범주, 건수 대 기준선, 줄, 고치는 방법을 말한다', () {
      final rule = slopRules.firstWhere((rule) => rule.id == 'raw_radius');
      final message = describeSlopDelta(
        const SlopDelta(
          ruleId: 'raw_radius',
          path: 'lib/a.dart',
          actual: 3,
          baseline: 2,
        ),
        lines: [10, 44, 90],
      );
      expect(message, contains('lib/a.dart'));
      expect(message, contains(rule.label));
      expect(message, contains('3'));
      expect(message, contains('기준선 2'));
      expect(message, contains('10, 44, 90'));
      expect(message, contains(rule.fix));
    });
  });

  group('현재 lib', () {
    test('슬롭 패턴이 기준선보다 늘지 않았다', () {
      final scan = _scanLib();
      final baselineFile = File(_baselinePath);
      final baseline = parseSlopBaseline(baselineFile.readAsStringSync());

      if (_tighten) {
        baselineFile.writeAsStringSync(
          encodeSlopBaseline(tightenSlopBaseline(scan.counts, baseline)),
        );
        return;
      }

      final deltas = slopRatchetDeltas(scan.counts, baseline);
      final increases = [
        for (final delta in deltas)
          if (delta.kind == SlopDeltaKind.increase)
            describeSlopDelta(
              delta,
              lines: scan.lines[delta.ruleId]?[delta.path] ?? const [],
            ),
      ];
      final stale = [
        for (final delta in deltas)
          if (delta.kind == SlopDeltaKind.stale) describeSlopDelta(delta),
      ];
      if (increases.isNotEmpty) {
        fail(
          'AI 슬롭 패턴이 기준선보다 늘었다. 기준선을 올리지 말고 안내대로 고쳐라.\n'
          '${increases.join('\n')}',
        );
      }
      if (stale.isNotEmpty) {
        fail(
          '줄어든 만큼 기준선을 내려라. 아래 명령은 기준선을 내리기만 한다.\n'
          'flutter test $_testPath --dart-define=TIGHTEN_SLOP_BASELINE=true\n'
          '${stale.join('\n')}',
        );
      }
    });
  });
}

({SlopCounts counts, Map<String, Map<String, List<int>>> lines}) _scanLib() {
  final counts = <String, Map<String, int>>{
    for (final rule in slopRules) rule.id: <String, int>{},
  };
  final lines = <String, Map<String, List<int>>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final path = entity.path.replaceAll(r'\', '/');
    for (final hit in scanSlopSource(entity.readAsStringSync(), path: path)) {
      counts[hit.ruleId]![path] = (counts[hit.ruleId]![path] ?? 0) + 1;
      (lines[hit.ruleId] ??= {}).putIfAbsent(path, () => []).add(hit.line);
    }
  }
  return (counts: counts, lines: lines);
}
