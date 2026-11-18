import 'package:flutter_test/flutter_test.dart';

import 'support/fixed_height_text_scan.dart';

/// 고정 높이 가드의 키 방식을 합성 소스로 고정한다. 실제 소스에 의존하지 않아
/// 허용 목록이 바뀌어도 이 규칙은 그대로 검증된다.
const _path = 'lib/a.dart';

const _base = """
class Row extends StatelessWidget {
  Widget build(BuildContext context) {
    return SizedBox(height: 46, child: Text('-'));
  }

  Widget buildOther(BuildContext context) {
    return Container(
      height: 40,
      child: Column(children: [Text('a')]),
    );
  }
}
""";

List<String> _keys(String source) => [
  for (final box in scanFixedHeightTextBoxes({_path: source}).boxes) box.key,
];

void main() {
  test('키는 파일, 둘러싼 클래스.함수, 표현식 전체다', () {
    expect(_keys(_base), [
      'lib/a.dart | Row.build | SizedBox(height: 46',
      'lib/a.dart | Row.buildOther | Container(height: 40',
    ]);
  });

  test('무관한 줄을 앞에 넣어 줄이 밀려도 키가 같다', () {
    final shifted = "// 주석\n// 주석\nconst unrelated = 1;\n$_base";
    expect(_keys(shifted), _keys(_base));
  });

  test('46과 46.5는 다른 키다', () {
    final changed = _base.replaceFirst('height: 46,', 'height: 46.5,');
    expect(
      _keys(changed).first,
      'lib/a.dart | Row.build | SizedBox(height: 46.5',
    );
    expect(_keys(changed).first, isNot(_keys(_base).first));
  });

  test('같은 표현식의 새 박스를 다른 함수 앞에 끼우면 허용되지 않은 새 키가 생긴다', () {
    final inserted = _base.replaceFirst(
      'class Row',
      "class Fresh { Widget build(BuildContext c) => SizedBox(height: 46, child: Text('x')); }\nclass Row",
    );
    expect(
      _keys(inserted),
      contains('lib/a.dart | Fresh | SizedBox(height: 46'),
    );
  });

  test('같은 함수 안에 같은 표현식이 둘이면 모호하다고 보고한다', () {
    final duplicated = _base.replaceFirst(
      "return SizedBox(height: 46, child: Text('-'));",
      "return Column(children: [SizedBox(height: 46, child: Text('-')), SizedBox(height: 46, child: Text('+'))]);",
    );
    final scan = scanFixedHeightTextBoxes({_path: duplicated});
    expect(scan.ambiguousKeys, {
      'lib/a.dart | Row.build | SizedBox(height: 46',
    });
  });

  test('문자열 안의 중괄호와 클로저에 속지 않는다', () {
    const source = r"""
class Row {
  Widget build(BuildContext context) {
    final label = '{ 열린 중괄호';
    return Builder(builder: (context) {
      return SizedBox(height: 30, child: Text('$label'));
    });
  }
}
""";
    expect(_keys(source), ['lib/a.dart | Row.build | SizedBox(height: 30']);
  });

  test('24 미만이거나 텍스트가 없는 박스는 대상이 아니다', () {
    const source = """
class Row {
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(height: 16, child: Text('작음')),
      SizedBox(height: 40, child: Icon(Icons.add)),
    ]);
  }
}
""";
    expect(_keys(source), isEmpty);
  });
}
