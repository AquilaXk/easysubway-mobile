import 'dart_code_mask.dart';

/// AI 슬롭 디자인 패턴 규칙표와 소스 스캐너(#515).
///
/// 규칙은 검증된 두 목록의 동작을 Flutter 위젯 이름으로 옮긴 것이다(둘 다 Apache-2.0, 코드는 가져오지 않았다).
/// 확인한 커밋은 pixelslop 45cd615d, impeccable 93686754다.
/// - pixelslop AI Slop Pattern Catalog(gabelul/pixelslop, dist/skill/resources/ai-slop-patterns.md)
///   #2·S2 glassmorphism과 backdrop-filter, #5·S1 gradient, #10·S6 shadow,
///   #13 bounce·elastic, #15 one-sided accent border.
/// - impeccable(pbakaus/impeccable, crates/detect/src/regex_matchers.rs)의 `side-tab`(굵기 3 이상)과
///   `bounce-easing`(cubic-bezier의 y1·y2가 -0.1 미만이거나 1.1 초과, bounce·elastic·spring 이름).
/// BoxDecoration, Icons, 원시 반경과 색은 이 레포의 토큰 정책(design_guard_test.dart)에서 왔다.
class SlopHit {
  const SlopHit(this.ruleId, this.line);

  final String ruleId;
  final int line;
}

class SlopSource {
  SlopSource(this.masked) : _lineStarts = _lineStartsOf(masked.code);

  final MaskedDart masked;
  final List<int> _lineStarts;

  String get code => masked.code;

  /// 여는 괄호 위치 -> 짝이 맞는 닫는 괄호 위치. 한 번에 훑어 선형 시간에 만든다.
  late final Map<int, int> parenPairs = _parenPairsOf(masked.code);

  /// [offset]이 있는 1부터 시작하는 줄 번호.
  int lineAt(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low + 1;
  }

  static Map<int, int> _parenPairsOf(String code) {
    final pairs = <int, int>{};
    final open = <int>[];
    for (var i = 0; i < code.length; i++) {
      final char = code[i];
      if (char == '(') {
        open.add(i);
      } else if (char == ')' && open.isNotEmpty) {
        pairs[open.removeLast()] = i;
      }
    }
    return pairs;
  }

  static List<int> _lineStartsOf(String code) => [
    0,
    for (var i = 0; i < code.length; i++)
      if (code.codeUnitAt(i) == 0x0A) i + 1,
  ];
}

typedef SlopFinder = List<int> Function(SlopSource source);

class SlopRule {
  const SlopRule({
    required this.id,
    required this.label,
    required this.counts,
    required this.fix,
    required this.find,
    this.excludedPaths = const {},
  });

  final String id;
  final String label;

  /// 기준선 숫자가 세는 대상.
  final String counts;

  /// 실패 메시지에 붙는 고치는 방법.
  final String fix;
  final SlopFinder find;

  /// 이 규칙을 적용하지 않는 파일. 토큰을 정의하는 파일이다.
  final Set<String> excludedPaths;
}

const _tokenFiles = {'lib/design_tokens.dart', 'lib/accessible_design.dart'};

SlopFinder _codePattern(RegExp pattern, {bool Function(Match)? accept}) =>
    (source) => [
      for (final match in pattern.allMatches(source.code))
        if (accept?.call(match) ?? true) source.lineAt(match.start),
    ];

SlopFinder _literalPattern(RegExp pattern) =>
    (source) => [
      for (final literal in source.masked.literals)
        for (final _ in pattern.allMatches(literal.text)) literal.line,
    ];

SlopFinder _anyOf(List<SlopFinder> finders) =>
    (source) => [for (final finder in finders) ...finder(source)];

const _number = r'(-?(?:\d+\.?\d*|\.\d+))';

/// impeccable `bounce-easing`: y1 또는 y2가 [-0.1, 1.1]을 벗어나는 곡선은 목표를 지나쳤다 돌아온다.
bool _overshoots(Match match) {
  final y1 = double.parse(match.group(2)!);
  final y2 = double.parse(match.group(4)!);
  return y1 < -0.1 || y1 > 1.1 || y2 < -0.1 || y2 > 1.1;
}

final _sideKey = RegExp(
  r'\b(left|right|top|bottom|start|end)\s*:\s*(?:const\s+)?',
);
final _noBorderSide = RegExp(r'BorderSide\.none\b');
final _borderCall = RegExp(r'\b(?:Border|BorderDirectional)\(');
final _widthKey = RegExp(r'\bwidth\s*:');
final _width = RegExp(r'\bwidth\s*:\s*(-?(?:\d+\.?\d*|\.\d+))');
const _thickBorderWidth = 3.0;
const _thinBorderWidth = 2.0;
const _borderSideCount = 4;
const _minThinSides = 2;
const _defaultBorderSideWidth = 1.0;

const _borderSideConstructor = 'BorderSide(';

/// `BorderSide(...)` 인자 구간의 폭. 폭을 적지 않으면 Flutter 기본값 1이고, 리터럴이 아니면 알 수 없다.
double? _sideWidth(String sideArguments) {
  if (!sideArguments.contains(_widthKey)) {
    return _defaultBorderSideWidth;
  }
  final match = _width.firstMatch(sideArguments);
  return match == null ? null : double.parse(match.group(1)!);
}

typedef _Side = ({double width, int end});

/// [side]에서 시작하는 변 값의 폭과 끝 위치. `BorderSide.none`은 폭 0이다.
/// `BorderSide(` 리터럴이 아니거나 폭을 알 수 없으면 null.
_Side? _sideAt(SlopSource source, int side) {
  final none = _noBorderSide.matchAsPrefix(source.code, side);
  if (none != null) {
    return (width: 0, end: none.end);
  }
  final close = source.parenPairs[side + _borderSideConstructor.length - 1];
  if (!source.code.startsWith(_borderSideConstructor, side) || close == null) {
    return null;
  }
  final width = _sideWidth(
    source.code.substring(side + _borderSideConstructor.length, close),
  );
  return width == null ? null : (width: width, end: close + 1);
}

/// `Border(` 호출의 바깥 인자에 적힌 변 키마다 폭을 읽는다. 변 값 안쪽의 `top:` 같은 이름은 건너뛴다.
/// 변 값이 알 수 없는 형태이면 null.
List<double>? _sideWidths(SlopSource source, int open, int close) {
  final widths = <double>[];
  var cursor = open + 1;
  while (true) {
    final key = _sideKey.allMatches(source.code, cursor).firstOrNull;
    if (key == null || key.start >= close) {
      return widths;
    }
    final side = _sideAt(source, key.end);
    if (side == null) {
      return null;
    }
    widths.add(side.width);
    cursor = side.end;
  }
}

/// pixelslop #15(`thick.length === 1 && thin.length >= 2`): 폭 3 이상인 변이 정확히 하나이고
/// 폭 2 미만인 변이 둘 이상이다. 적지 않은 변은 기본 폭 1이라 얇다.
bool _isAccentBorder(List<double> widths) {
  final thick = widths.where((width) => width >= _thickBorderWidth).length;
  final thin =
      widths.where((width) => width < _thinBorderWidth).length +
      (_borderSideCount - widths.length);
  return thick == 1 && thin >= _minThinSides;
}

List<int> _accentBorders(SlopSource source) {
  final lines = <int>[];
  for (final call in _borderCall.allMatches(source.code)) {
    final open = call.end - 1;
    final close = source.parenPairs[open];
    final widths = close == null ? null : _sideWidths(source, open, close);
    if (widths != null && _isAccentBorder(widths)) {
      lines.add(source.lineAt(call.start));
    }
  }
  return lines;
}

final slopRules = <SlopRule>[
  SlopRule(
    id: 'gradient',
    label: '그라데이션',
    counts:
        'LinearGradient, RadialGradient, SweepGradient, ui.Gradient 식별자 등장 횟수',
    fix: '그라데이션은 쓰지 않는다. design_tokens.dart의 단색과 구분선, 여백으로 나눈다.',
    find: _codePattern(RegExp(r'\b(?:Linear|Radial|Sweep)?Gradient\b')),
  ),
  SlopRule(
    id: 'blur',
    label: 'blur·글래스 효과',
    counts:
        'BackdropFilter, ImageFiltered, ImageFilter.blur, MaskFilter.blur 등장 횟수',
    fix: 'blur와 반투명 글래스 표면은 쓰지 않는다. 불투명한 표면 토큰을 쓴다.',
    find: _codePattern(
      RegExp(
        r'\b(?:BackdropFilter|ImageFiltered)\b|\b(?:ImageFilter|MaskFilter)\.blur\b',
      ),
    ),
  ),
  SlopRule(
    id: 'shadow',
    label: '그림자·elevation',
    counts:
        'BoxShadow(, Shadow( 생성, shadowColor: 지정, 0보다 큰 elevation: 숫자 리터럴 횟수',
    fix: '그림자는 쓰지 않는다. 구분선이나 배경색 차이로 층을 나눈다.',
    find: _codePattern(
      RegExp(
        r'\bBoxShadow\(|(?<![A-Za-z0-9_])Shadow\(|\bshadowColor\s*:|\belevation\s*:\s*(\d+(?:\.\d+)?)',
      ),
      accept: (match) =>
          match.group(1) == null || double.parse(match.group(1)!) > 0,
    ),
  ),
  SlopRule(
    id: 'bounce',
    label: 'bounce·elastic 곡선',
    counts:
        'Curves.bounce*, Curves.elastic*, Curves.easeIn/Out/InOutBack, Elastic*Curve, '
        'SpringDescription·SpringSimulation, y1 또는 y2가 [-0.1, 1.1]을 벗어나는 Cubic( 횟수',
    fix: '튕기거나 지나쳤다 돌아오는 곡선은 쓰지 않는다. Curves.easeOut 계열만 쓴다.',
    find: _anyOf([
      _codePattern(
        RegExp(
          r'\bCurves\.(?:bounce|elastic)\w*|\bCurves\.ease(?:In|Out|InOut)Back\b|\bElastic(?:In|Out|InOut)Curve\b|\bSpring(?:Description|Simulation)\b',
        ),
      ),
      _codePattern(
        RegExp(
          'Cubic\\(\\s*$_number\\s*,\\s*$_number\\s*,\\s*$_number\\s*,\\s*$_number\\s*,?\\s*\\)',
        ),
        accept: _overshoots,
      ),
    ]),
  ),
  SlopRule(
    id: 'side_border',
    label: '한쪽만 굵은 강조 테두리',
    counts:
        'Border(·BorderDirectional( 중 폭 3 이상인 변이 정확히 하나이고 폭 2 미만인 변이 둘 이상인 호출 횟수. 적지 않은 변과 BorderSide.none은 얇은 변이다. 폭이 리터럴이 아닌 호출은 세지 않는다',
    fix: '한쪽만 굵은 강조 테두리는 쓰지 않는다. 1dp 구분선이나 배경색으로 구분한다.',
    find: _accentBorders,
  ),
  SlopRule(
    id: 'emoji',
    label: '문자열 속 이모지',
    counts:
        '문자열 리터럴(이스케이프를 푼 뒤)의 이모지·딩뱃 문자 U+1F000-1FAFF, U+2600-27BF, U+2B50, U+2B55, 화살표·사각형·재생 기호(U+2B05-2B07, U+2B1B, U+2B1C, U+25FD, U+25FE, U+25B6, U+2139 등), 시계 기호, 변형 선택자 개수. 주석은 세지 않는다',
    fix: '이모지와 장식 기호는 문구에 넣지 않는다. 롤모델이 같은 자리에 아이콘을 쓸 때만 Icon을 쓴다.',
    find: _literalPattern(
      RegExp(
        '[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}\u{2B55}\u{2B05}-\u{2B07}\u{2B1B}\u{2B1C}\u{25FD}\u{25FE}\u{25B6}\u{2139}\u{231A}\u{231B}\u{23E9}-\u{23F3}\u{23F8}-\u{23FA}\u{FE0F}\u{20E3}]',
        unicode: true,
      ),
    ),
  ),
  SlopRule(
    id: 'long_dash',
    label: '문자열 속 긴 대시',
    counts: '문자열 리터럴(이스케이프를 푼 뒤)의 U+2012-U+2015, U+2212 개수. 주석은 세지 않는다',
    fix: '문구에 긴 대시(U+2012-U+2015)와 빼기 기호(U+2212)를 쓰지 않는다. 쉼표나 마침표로 문장을 나눈다.',
    find: _literalPattern(RegExp('[\u{2012}-\u{2015}\u{2212}]')),
  ),
  SlopRule(
    id: 'raw_radius',
    label: '원시 반경 숫자',
    counts:
        'BorderRadius.circular(숫자)와 Radius.circular(숫자) 호출 횟수. 토큰 인자는 세지 않고 토큰 정의 파일은 제외한다',
    fix:
        '원시 숫자 대신 EasySubwayRadius.control, card, sheet 토큰을 쓴다(design_tokens.dart).',
    excludedPaths: _tokenFiles,
    find: _codePattern(
      RegExp(r'\b(?:BorderRadius|Radius)\.circular\(\s*(?:\d|\.\d)'),
    ),
  ),
  SlopRule(
    id: 'raw_color',
    label: '원시 색',
    counts:
        'Colors.이름(transparent 제외), 숫자 리터럴로 만드는 Color(0x...)·Color(4278190080), Color.from(, Color.fromARGB(, Color.fromRGBO( 횟수. 토큰 정의 파일은 제외한다',
    fix: '원시 색 대신 design_tokens.dart와 accessible_design.dart의 색 토큰을 쓴다.',
    excludedPaths: _tokenFiles,
    find: _codePattern(
      RegExp(
        r'\bColors\.(?!transparent\b)[A-Za-z]\w*|\bColor\(\s*\d|\bColor\.from(?:ARGB|RGBO)?\(',
      ),
    ),
  ),
  SlopRule(
    id: 'box_decoration',
    label: '상자(BoxDecoration)',
    counts: 'BoxDecoration( 생성 횟수',
    fix:
        '롤모델이 그 자리에 상자를 쓰는지 먼저 확인한다. 롤모델은 구분선과 여백으로 나눈다. '
        '꼭 필요하면 기준선을 올리는 PR에서 근거를 적는다.',
    find: _codePattern(RegExp(r'\bBoxDecoration\(')),
  ),
  SlopRule(
    id: 'icon',
    label: 'Material 아이콘',
    counts: 'Icons.이름 참조 횟수',
    fix: '롤모델이 같은 자리에 아이콘을 쓸 때만 쓴다. 제목 앞 장식 아이콘은 넣지 않는다.',
    find: _codePattern(RegExp(r'(?<![A-Za-z0-9_])Icons\.[A-Za-z_]\w*')),
  ),
];

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.startsWith('lib/generated/');

/// [source] 한 파일에서 규칙별 히트를 줄 번호와 함께 찾는다. [path]는 `lib/...` 상대 경로다.
List<SlopHit> scanSlopSource(String source, {required String path}) {
  if (_isGenerated(path)) {
    return const [];
  }
  final scanned = SlopSource(maskDartSource(source));
  return [
    for (final rule in slopRules)
      if (!rule.excludedPaths.contains(path))
        for (final line in rule.find(scanned)..sort()) SlopHit(rule.id, line),
  ];
}
