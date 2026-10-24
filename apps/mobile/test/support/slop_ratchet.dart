import 'dart:convert';

import 'slop_pattern_scan.dart';

/// 규칙 id -> 파일 경로 -> 건수. 없는 범주와 파일은 0건이다.
typedef SlopCounts = Map<String, Map<String, int>>;

enum SlopDeltaKind { increase, stale }

class SlopDelta {
  const SlopDelta({
    required this.ruleId,
    required this.path,
    required this.actual,
    required this.baseline,
  });

  final String ruleId;
  final String path;
  final int actual;
  final int baseline;

  SlopDeltaKind get kind =>
      actual > baseline ? SlopDeltaKind.increase : SlopDeltaKind.stale;
}

const _schemaVersion = 1;

int _countOf(SlopCounts counts, String ruleId, String path) =>
    counts[ruleId]?[path] ?? 0;

/// 실제 건수와 기준선이 다른 (규칙, 파일)만 돌려준다. 늘면 증가, 줄면 낡은 기준선이다.
/// 파일 단위로 세므로 코드를 다른 파일로 옮겨도 늘어난 쪽이 새 파일로 잡힌다.
List<SlopDelta> slopRatchetDeltas(SlopCounts actual, SlopCounts baseline) {
  final deltas = <SlopDelta>[];
  final ruleIds = {...actual.keys, ...baseline.keys};
  for (final ruleId in ruleIds) {
    final paths = {...?actual[ruleId]?.keys, ...?baseline[ruleId]?.keys};
    for (final path in paths) {
      final now = _countOf(actual, ruleId, path);
      final limit = _countOf(baseline, ruleId, path);
      if (now != limit) {
        deltas.add(
          SlopDelta(ruleId: ruleId, path: path, actual: now, baseline: limit),
        );
      }
    }
  }
  return deltas;
}

/// 기준선을 내리기만 한다. 새 파일이나 늘어난 건수는 반영하지 않고, 0이 된 항목은 지운다.
SlopCounts tightenSlopBaseline(SlopCounts actual, SlopCounts baseline) => {
  for (final MapEntry(key: ruleId, value: files) in baseline.entries)
    ruleId: {
      for (final MapEntry(key: path, value: limit) in files.entries)
        if (_lowered(_countOf(actual, ruleId, path), limit) > 0)
          path: _lowered(_countOf(actual, ruleId, path), limit),
    },
};

int _lowered(int now, int limit) => now < limit ? now : limit;

SlopCounts parseSlopBaseline(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?> ||
      decoded['schemaVersion'] != _schemaVersion) {
    throw const FormatException('기준선 schemaVersion은 1이어야 한다');
  }
  final rules = decoded['rules'];
  final expected = slopRules.map((rule) => rule.id).toSet();
  if (rules is! Map<String, Object?> ||
      !rules.keys.toSet().containsAll(expected) ||
      !expected.containsAll(rules.keys)) {
    throw FormatException(
      '기준선 rules는 규칙 ${expected.join(', ')}를 모두, 정확히 가져야 한다',
    );
  }
  return {
    for (final MapEntry(key: ruleId, value: files) in rules.entries)
      ruleId: _parseFiles(ruleId, files),
  };
}

Map<String, int> _parseFiles(String ruleId, Object? files) {
  if (files is! Map<String, Object?>) {
    throw FormatException('기준선 $ruleId는 파일별 건수 객체여야 한다');
  }
  return {
    for (final MapEntry(key: path, value: count) in files.entries)
      path: switch (count) {
        final int value when value > 0 => value,
        _ => throw FormatException('기준선 $ruleId $path 건수는 양의 정수여야 한다'),
      },
  };
}

/// 규칙은 [slopRules] 순서, 파일은 경로 순서로 쓴다. 같은 내용은 항상 같은 바이트가 된다.
String encodeSlopBaseline(SlopCounts counts) {
  final rules = <String, Object?>{};
  for (final rule in slopRules) {
    final files = counts[rule.id] ?? const <String, int>{};
    final paths = files.keys.toList()..sort();
    rules[rule.id] = {for (final path in paths) path: files[path]};
  }
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert({'schemaVersion': _schemaVersion, 'rules': rules})}\n';
}

/// 실패 메시지. 어느 파일의 어떤 범주가 얼마나 달라졌고 어떻게 고치는지 말한다.
String describeSlopDelta(SlopDelta delta, {List<int> lines = const []}) {
  final rule = slopRules.where((rule) => rule.id == delta.ruleId).firstOrNull;
  final label = rule?.label ?? delta.ruleId;
  if (delta.kind == SlopDeltaKind.stale) {
    return '${delta.path}: $label ${delta.actual}건으로 줄었다 (기준선 ${delta.baseline})';
  }
  final where = lines.isEmpty ? '' : ', 줄 ${lines.join(', ')}';
  return '${delta.path}: $label ${delta.actual}건 (기준선 ${delta.baseline})$where\n'
      '  세는 대상: ${rule?.counts}\n'
      '  고치는 방법: ${rule?.fix}';
}
