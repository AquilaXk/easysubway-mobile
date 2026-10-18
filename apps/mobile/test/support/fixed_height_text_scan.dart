/// 텍스트를 담은 고정 높이 컨테이너를 소스에서 찾아 줄 번호와 무관한 키를 붙인다(#409).
///
/// 키는 `파일 | 둘러싼 클래스.함수 | 공백을 접은 박스 표현식 전체`다. 높이 숫자를 잘라
/// 쓰지 않아 `46`과 `46.5`는 다른 키가 된다. 같은 함수 안에 같은 표현식이 둘 이상이면
/// 키가 모호하므로 [FixedHeightScan.ambiguousKeys]로 따로 보고한다.
class FixedHeightTextBox {
  const FixedHeightTextBox({
    required this.key,
    required this.widget,
    required this.height,
  });

  final String key;
  final String widget;
  final double height;
}

class FixedHeightScan {
  const FixedHeightScan({required this.boxes, required this.ambiguousKeys});

  final List<FixedHeightTextBox> boxes;
  final Set<String> ambiguousKeys;
}

const _minFixedHeight = 24;
const _scopeLookahead = 700;

final _boxPattern = RegExp(
  r'(SizedBox|Container)\(\s*(?:[^()]*?)height:\s*(\d+(?:\.\d+)?)',
);
final _nextBoxPattern = RegExp(r'\b(?:SizedBox|Container)\(');
final _whitespacePattern = RegExp(r'\s+');

/// [sources](경로 -> 소스)에서 높이 [_minFixedHeight] 이상이고 텍스트를 담은 박스를 찾는다.
FixedHeightScan scanFixedHeightTextBoxes(Map<String, String> sources) {
  final boxes = <FixedHeightTextBox>[];
  final seen = <String>{};
  final ambiguousKeys = <String>{};
  sources.forEach((path, source) {
    for (final match in _boxPattern.allMatches(source)) {
      final height = double.parse(match.group(2)!);
      if (height < _minFixedHeight || !_holdsText(source, match.end)) {
        continue;
      }
      final expression = match
          .group(0)!
          .replaceAll(_whitespacePattern, ' ')
          .replaceAll('( ', '(');
      final key =
          '$path | ${_enclosingSymbol(source, match.start)} | $expression';
      if (!seen.add(key)) {
        ambiguousKeys.add(key);
      }
      boxes.add(
        FixedHeightTextBox(key: key, widget: match.group(1)!, height: height),
      );
    }
  });
  return FixedHeightScan(boxes: boxes, ambiguousKeys: ambiguousKeys);
}

/// 박스 표현식 뒤에서 다음 박스가 나오기 전까지 `Text(`가 있으면 텍스트를 담은 것으로 본다.
bool _holdsText(String source, int boxEnd) {
  final remaining = source.substring(
    boxEnd,
    (boxEnd + _scopeLookahead).clamp(0, source.length),
  );
  final nextBox = _nextBoxPattern.firstMatch(remaining);
  final scope = nextBox == null
      ? remaining
      : remaining.substring(0, nextBox.start);
  return scope.contains('Text(');
}

const _controlKeywords = {
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'else',
  'when',
};
final _typeHeaderPattern = RegExp(
  r'(?:^|\s)(?:class|mixin|extension|enum)\s+(\w+)',
);
final _functionHeaderPattern = RegExp(
  r'(\w+)\s*\((?:[^()]|\([^()]*\))*\)\s*(?:async\*?|sync\*)?\s*$',
);
final _getterHeaderPattern = RegExp(r'\bget\s+(\w+)\s*$');

/// [offset]을 감싼 클래스와 함수 이름을 `Class.method`로 돌려준다. 이름 없는 클로저와
/// 제어문 블록은 건너뛴다. 감싼 이름이 없으면 `<top>`이다.
String _enclosingSymbol(String source, int offset) {
  final names = <String?>[];
  final header = StringBuffer();
  var i = 0;
  while (i < offset) {
    final char = source[i];
    if (source.startsWith('//', i)) {
      i = _skipUntil(source, i, '\n');
    } else if (source.startsWith('/*', i)) {
      i = _skipUntil(source, i, '*/');
    } else if (char == "'" || char == '"') {
      i = _skipString(source, i);
      header.write('""');
    } else if (char == '{') {
      names.add(_symbolName(header.toString()));
      header.clear();
      i++;
    } else if (char == '}') {
      if (names.isNotEmpty) {
        names.removeLast();
      }
      header.clear();
      i++;
    } else if (char == ';') {
      header.clear();
      i++;
    } else {
      header.write(char);
      i++;
    }
  }
  final path = names.whereType<String>().join('.');
  return path.isEmpty ? '<top>' : path;
}

String? _symbolName(String header) {
  final trimmed = header.trim();
  final typeName = _typeHeaderPattern.firstMatch(trimmed)?.group(1);
  if (typeName != null) {
    return typeName;
  }
  final getterName = _getterHeaderPattern.firstMatch(trimmed)?.group(1);
  if (getterName != null) {
    return getterName;
  }
  final functionName = _functionHeaderPattern.firstMatch(trimmed)?.group(1);
  if (functionName != null && !_controlKeywords.contains(functionName)) {
    return functionName;
  }
  return null;
}

int _skipUntil(String source, int from, String terminator) {
  final end = source.indexOf(terminator, from);
  return end == -1 ? source.length : end + terminator.length;
}

/// 따옴표로 시작하는 문자열 리터럴(세 겹 따옴표, 이스케이프 포함)의 끝 다음 위치.
/// 보간식 안의 따옴표는 따로 해석하지 않는다.
int _skipString(String source, int start) {
  final quote = source[start];
  final isTriple = source.startsWith(quote * 3, start);
  final terminator = isTriple ? quote * 3 : quote;
  final raw = start > 0 && source[start - 1] == 'r';
  var i = start + terminator.length;
  while (i < source.length) {
    if (!raw && source[i] == r'\') {
      i += 2;
    } else if (source.startsWith(terminator, i)) {
      return i + terminator.length;
    } else {
      i++;
    }
  }
  return source.length;
}
