import 'dart:ui' show Color;

import '../../stations/domain/station_line.dart';
import 'network_map_models.dart';

/// 노선도 노선 줄과 노선 선택 시트가 그리는 노선 하나. 데이터팩 노선에서 만든다.
class RouteMapLineChoice {
  const RouteMapLineChoice({
    required this.lineId,
    required this.name,
    required this.markLabel,
    required this.color,
  });

  factory RouteMapLineChoice.fromLine(NetworkMapLine line) {
    final name = _choiceName(line.name);
    final number = _lineNumber(name);
    return RouteMapLineChoice(
      lineId: line.id,
      name: name,
      markLabel: number?.toString() ?? String.fromCharCode(name.runes.first),
      color: stationLineColor(line.color),
    );
  }

  final String lineId;

  /// 시트 칸과 노선 줄 칩에 쓰는 이름(`1호선`, `공항`, `GTX-A`).
  final String name;

  /// 원형 마크 안 글자. 번호 노선은 번호, 이름 노선은 이름의 첫 글자다.
  final String markLabel;

  final Color color;
}

/// 데이터팩 [lines]를 노선 선택 시트 순서로 늘어놓는다. 번호 노선이 번호순으로 먼저
/// 오고, 이름 노선은 [_namedLineOrder] 순서, 그 밖의 노선은 데이터팩 순서로 뒤에 둔다.
List<RouteMapLineChoice> routeMapLineChoices(List<NetworkMapLine> lines) {
  final ranked = [
    for (var index = 0; index < lines.length; index++)
      (choice: RouteMapLineChoice.fromLine(lines[index]), index: index),
  ];
  ranked.sort((a, b) {
    final byRank = _rank(a.choice).compareTo(_rank(b.choice));
    return byRank != 0 ? byRank : a.index.compareTo(b.index);
  });
  return [for (final entry in ranked) entry.choice];
}

/// [choices] 가운데 [selectedLineId]인 노선. 지역이 바뀌어 그 노선이 목록에 없으면
/// 고른 노선이 없다.
RouteMapLineChoice? routeMapSelectedLineChoice(
  List<RouteMapLineChoice> choices,
  String? selectedLineId,
) {
  for (final choice in choices) {
    if (choice.lineId == selectedLineId) {
      return choice;
    }
  }
  return null;
}

/// 상용 지하철 서비스 노선 선택 시트의 이름 노선 순서(QA 캡처 2026-10-24). 데이터팩
/// `lines` 표에는 표시 순서 열이 없다. 어떤 노선을 보일지는 데이터팩이 정하고, 이 표는
/// 순서만 정한다.
const _namedLineOrder = <String>[
  '공항',
  '경의중앙',
  '경춘',
  '수인분당',
  '신분당',
  '경강',
  '서해',
  '인천1',
  '인천2',
  '에버라인',
  '의정부',
  '우이신설',
  '김포골드',
  '신림',
  'GTX-A',
];

/// 노선 마크 알약 이름(`stationLineBadgeText`)과 시트 이름이 다른 노선. 상용 지하철
/// 서비스 시트는 공항철도를 `공항`으로 쓴다.
const _choiceNameOverrides = <String, String>{'공항철도': '공항'};

enum _RankGroup { numbered, named, other }

int _rank(RouteMapLineChoice choice) {
  final number = _lineNumber(choice.name);
  if (number != null) {
    return _groupRank(_RankGroup.numbered, number);
  }
  final namedIndex = _namedLineOrder.indexOf(choice.name);
  return namedIndex >= 0
      ? _groupRank(_RankGroup.named, namedIndex)
      : _groupRank(_RankGroup.other, 0);
}

/// 그룹 안 순위가 다음 그룹을 넘지 않을 만큼 큰 그룹 간격.
const _rankGroupStride = 1000;

int _groupRank(_RankGroup group, int withinGroup) =>
    group.index * _rankGroupStride + withinGroup;

final _numberedLineName = RegExp(r'^(\d+)호선$');

int? _lineNumber(String choiceName) {
  final match = _numberedLineName.firstMatch(choiceName);
  return match == null ? null : int.parse(match.group(1)!);
}

String _choiceName(String datapackName) {
  final badge = stationLineBadgeText(datapackName);
  if (int.tryParse(badge) != null) {
    return '$badge호선';
  }
  return _choiceNameOverrides[badge] ?? badge;
}
