/// Dart 소스를 코드 뷰와 문자열 리터럴로 나눈다(#515).
///
/// 코드 뷰는 원본과 길이와 줄 위치가 같다. 주석 본문과 문자열 본문은 공백으로 지우고
/// (줄바꿈은 둔다) `${...}` 보간식 안의 코드는 그대로 둔다. 그래서 정규식 가드가 주석이나
/// 문자열 속 단어를 코드로 잘못 세지 않는다. 문자열 본문은 따로 모아 두어 문구 검사에 쓴다.
///
/// Dart는 쉼표 없이 붙어 있는 문자열(`'가' '나'`)을 하나의 리터럴로 이으므로 여기서도 하나로 센다.
/// 사이에는 공백과 주석만 올 수 있다.
class DartStringLiteral {
  const DartStringLiteral({
    required this.line,
    required this.text,
    required this.start,
  });

  /// 리터럴이 시작하는 1부터 시작하는 줄 번호.
  final int line;

  /// 첫 따옴표(raw 접두사 `r` 포함)의 원본 오프셋.
  final int start;

  /// 보간식을 뺀 본문. `\n`, `\u2014`, `\u{1F680}`, `\x41` 이스케이프는 실제 문자로 풀려 있다.
  final String text;
}

class MaskedDart {
  const MaskedDart({required this.code, required this.literals});

  final String code;
  final List<DartStringLiteral> literals;
}

MaskedDart maskDartSource(String source) => _DartMasker(source).run();

final _identifierChar = RegExp(r'[A-Za-z0-9_$]');
final _escape = RegExp(
  r'\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|[\s\S])',
);
const _maxCodePoint = 0x10FFFF;
const _simpleEscapes = {
  'n': '\n',
  'r': '\r',
  't': '\t',
  'f': '\f',
  'b': '\b',
  'v': '\v',
};

/// 왼쪽부터 이스케이프를 한 개씩 소비한다. 그래서 `\\u2014`(역슬래시 + u2014)는 풀리지 않는다.
String _decodeEscapes(String text) => text.replaceAllMapped(_escape, (match) {
  final body = match.group(1)!;
  final isCodePoint = body.length > 1 && (body[0] == 'u' || body[0] == 'x');
  if (!isCodePoint) {
    return _simpleEscapes[body] ?? body;
  }
  final digits = body.replaceAll(RegExp(r'[ux{}]'), '');
  final codePoint = int.parse(digits, radix: 16);
  return codePoint > _maxCodePoint ? '' : String.fromCharCode(codePoint);
});

class _DartMasker {
  _DartMasker(this._source);

  final String _source;
  final _code = StringBuffer();
  final _literals = <DartStringLiteral>[];
  int _i = 0;
  int _line = 1;

  MaskedDart run() {
    _readCode(untilCloseBrace: false);
    return MaskedDart(code: _code.toString(), literals: _literals);
  }

  bool _startsWith(String pattern) => _source.startsWith(pattern, _i);

  bool _isIdentifierChar(int index) =>
      index >= 0 && _identifierChar.hasMatch(_source[index]);

  bool get _atStringStart {
    final char = _source[_i];
    if (char == "'" || char == '"') {
      return true;
    }
    return char == 'r' &&
        _i + 1 < _source.length &&
        (_source[_i + 1] == "'" || _source[_i + 1] == '"') &&
        !_isIdentifierChar(_i - 1);
  }

  void _copy() {
    final char = _source[_i++];
    _code.write(char);
    if (char == '\n') {
      _line++;
    }
  }

  void _blank(int length) {
    for (var n = 0; n < length && _i < _source.length; n++) {
      final isNewline = _source[_i] == '\n';
      _code.write(isNewline ? '\n' : ' ');
      if (isNewline) {
        _line++;
      }
      _i++;
    }
  }

  void _readCode({required bool untilCloseBrace}) {
    var depth = 0;
    int? adjacentRun;
    while (_i < _source.length) {
      if (_startsWith('//')) {
        _skipLineComment();
      } else if (_startsWith('/*')) {
        _skipBlockComment();
      } else if (_atStringStart) {
        adjacentRun = _addLiteral(adjacentRun, _readString());
      } else if (_source[_i] == '}' && untilCloseBrace && depth == 0) {
        _blank(1);
        return;
      } else {
        if (_source[_i].trim().isNotEmpty) {
          adjacentRun = null;
        }
        depth += _braceDelta(_source[_i]);
        _copy();
      }
    }
  }

  /// [adjacentRun]이 있으면 그 리터럴에 [piece]를 잇고, 없으면 새 리터럴로 더한다. 리터럴의 위치를 돌려준다.
  int _addLiteral(int? adjacentRun, DartStringLiteral piece) {
    if (adjacentRun == null) {
      _literals.add(piece);
      return _literals.length - 1;
    }
    final run = _literals[adjacentRun];
    _literals[adjacentRun] = DartStringLiteral(
      line: run.line,
      text: run.text + piece.text,
      start: run.start,
    );
    return adjacentRun;
  }

  int _braceDelta(String char) => switch (char) {
    '{' => 1,
    '}' => -1,
    _ => 0,
  };

  void _skipLineComment() {
    while (_i < _source.length && _source[_i] != '\n') {
      _blank(1);
    }
  }

  /// Dart 블록 주석은 중첩된다.
  void _skipBlockComment() {
    var depth = 0;
    while (_i < _source.length) {
      if (_startsWith('/*')) {
        depth++;
        _blank(2);
      } else if (_startsWith('*/')) {
        depth--;
        _blank(2);
        if (depth == 0) {
          return;
        }
      } else {
        _blank(1);
      }
    }
  }

  DartStringLiteral _readString() {
    final start = _i;
    final raw = _source[_i] == 'r';
    if (raw) {
      _copy();
    }
    final quote = _source[_i];
    final delimiter = _startsWith(quote * 3) ? quote * 3 : quote;
    _code.write(delimiter);
    _i += delimiter.length;
    final startLine = _line;
    final text = StringBuffer();
    while (_i < _source.length && !_startsWith(delimiter)) {
      _readStringPiece(raw: raw, text: text);
    }
    if (_i < _source.length) {
      _code.write(delimiter);
      _i += delimiter.length;
    }
    return DartStringLiteral(
      line: startLine,
      text: raw ? text.toString() : _decodeEscapes(text.toString()),
      start: start,
    );
  }

  void _readStringPiece({required bool raw, required StringBuffer text}) {
    if (!raw && _source[_i] == r'\' && _i + 1 < _source.length) {
      text.write(_source.substring(_i, _i + 2));
      _blank(2);
    } else if (!raw && _startsWith(r'${')) {
      _blank(2);
      _readCode(untilCloseBrace: true);
    } else {
      text.write(_source[_i]);
      _blank(1);
    }
  }
}
