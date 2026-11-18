import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import 'nearby_direction_title.dart';

/// 응답을 기다리는 동안 열차 행 자리에 쓰는 대시와 그 낭독 문장. 응답이 없다고
/// 확정된 뒤의 [NearbyPanelColumn.emptyMessage]와 구분한다.
const nearbyLoadingGlyph = ['-'];
const nearbyLoadingLabel = '불러오는 중';

/// 방면 카드 하나. 열차 행([rows])이 있으면 행을 그리고, 없으면 [emptyMessage]
/// 줄을 가운데에 그린다(상용 지하철 서비스의 "실시간 정보 없음"·"운행종료" 자리).
/// 응답을 기다리는 중이면([loading]) 정보 없음 대신 대시를 그리고 "불러오는 중"으로
/// 읽는다. [rowsLabel]은 행 전체를 스크린리더가 한 번에 읽을 문장이다.
class NearbyPanelColumn {
  const NearbyPanelColumn({
    required this.title,
    this.rows = const <Widget>[],
    this.rowsLabel = '',
    this.emptyMessage = const <String>[],
    this.loading = false,
  });

  final String title;
  final List<Widget> rows;
  final String rowsLabel;
  final List<String> emptyMessage;
  final bool loading;

  bool get hasData => rows.isNotEmpty;

  List<String> get placeholderLines =>
      loading ? nearbyLoadingGlyph : emptyMessage;

  String get _bodyLabel {
    if (hasData) {
      return rowsLabel;
    }
    return loading ? nearbyLoadingLabel : emptyMessage.join(' ');
  }

  String get semanticsLabel =>
      [title, _bodyLabel].where((part) => part.isNotEmpty).join(', ');
}

/// 주변역 패널 열 배치 계획. [dataIndex]가 null이면 인접역에서 유도한 빈 카드다.
class NearbyColumnSlot {
  const NearbyColumnSlot({required this.title, required this.dataIndex});

  final String title;
  final int? dataIndex;
}

/// 열차 정보가 있는 방면 라벨 [dataTitles]과 인접역 이름으로 주변역 패널의 열
/// 구성을 결정한다(오너 스펙 #2200 QA). 열차 정보가 없어도 인접역에서 "○○ 방면"을
/// 유도해 두 열 스켈레톤을 유지하고, 유도할 방면이 하나도 없으면 빈 리스트를
/// 반환한다(호출부가 카드 없는 안내를 그린다).
///
/// - 데이터 방면이 2개 이상: 인접역과 무관하게 기존 두 데이터 열을 유지한다.
/// - 데이터 방면이 1개: 데이터 열 + 인접역 유도 빈 카드. 빈 카드의 인접역은
///   데이터 라벨에 포함되지 않은 쪽을 고르고(판단 불가면 rightName 우선), 노선
///   바와 같은 쪽(왼쪽=이전역)에 배치한다.
/// - 데이터 방면이 0개: 좌(이전역)-우(다음역) 순서의 빈 카드만 만든다.
List<NearbyColumnSlot> resolveNearbyColumnSlots({
  required List<String> dataTitles,
  String? leftName,
  String? rightName,
}) {
  final left = _trimToNull(leftName);
  final right = _trimToNull(rightName);

  if (dataTitles.length >= 2) {
    return [
      NearbyColumnSlot(title: dataTitles[0], dataIndex: 0),
      NearbyColumnSlot(title: dataTitles[1], dataIndex: 1),
    ];
  }

  if (dataTitles.length == 1) {
    final label = dataTitles.first;
    final dataSlot = NearbyColumnSlot(title: label, dataIndex: 0);
    final other = _pickOtherAdjacent(label: label, left: left, right: right);
    if (other == null) {
      return [dataSlot];
    }
    final dashSlot = NearbyColumnSlot(
      title: _directionTitle(other.name),
      dataIndex: null,
    );
    return other.isLeft ? [dashSlot, dataSlot] : [dataSlot, dashSlot];
  }

  return [
    if (left != null)
      NearbyColumnSlot(title: _directionTitle(left), dataIndex: null),
    if (right != null)
      NearbyColumnSlot(title: _directionTitle(right), dataIndex: null),
  ];
}

String _directionTitle(String name) => '$name 방면';

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class _AdjacentPick {
  const _AdjacentPick(this.name, {required this.isLeft});

  final String name;
  final bool isLeft;
}

_AdjacentPick? _pickOtherAdjacent({
  required String label,
  required String? left,
  required String? right,
}) {
  // rightName 우선 순서로 후보를 만들고, 라벨에 포함되지 않은 쪽을 먼저 고른다.
  final candidates = <_AdjacentPick>[
    if (right != null) _AdjacentPick(right, isLeft: false),
    if (left != null) _AdjacentPick(left, isLeft: true),
  ];
  if (candidates.isEmpty) {
    return null;
  }
  for (final candidate in candidates) {
    if (!label.contains(candidate.name)) {
      return candidate;
    }
  }
  // 판단 불가(모두 라벨에 포함) → rightName 우선(후보 목록의 첫 항목).
  return candidates.first;
}

/// 방면 카드 줄. 상용 지하철 서비스처럼 테두리 카드 두 개를 나란히 두고, 카드마다
/// 검정 강조 제목, 제목 아래 구분선, 본문을 그린다. [onOpenDirection]이 있으면
/// 카드 전체가 그 방면을 여는 버튼이고 제목 오른쪽에 꺽쇠를 둔다.
class NearbyPanelColumns extends StatelessWidget {
  const NearbyPanelColumns({
    required this.columns,
    this.onOpenDirection,
    super.key,
  });

  final List<NearbyPanelColumn> columns;
  final VoidCallback? onOpenDirection;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < columns.length; index++) ...[
            if (index > 0) const SizedBox(width: EasySubwaySpacing.md),
            Expanded(
              child: _NearbyDirectionCard(
                column: columns[index],
                onOpen: onOpenDirection,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NearbyDirectionCard extends StatelessWidget {
  const _NearbyDirectionCard({required this.column, required this.onOpen});

  final NearbyPanelColumn column;
  final VoidCallback? onOpen;

  static const _shape = RoundedRectangleBorder(
    side: BorderSide(color: EasySubwayAccessibleColors.borderSubtle),
    borderRadius: BorderRadius.all(Radius.circular(EasySubwayRadius.control)),
  );

  @override
  Widget build(BuildContext context) {
    final title = column.title;
    final onTap = title.isEmpty ? null : onOpen;
    return Semantics(
      container: true,
      button: onTap != null,
      label: column.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: EasySubwayAccessibleColors.surfaceDefault,
        shape: _shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EasySubwaySpacing.lg,
              EasySubwaySpacing.md,
              EasySubwaySpacing.md,
              EasySubwaySpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title.isNotEmpty) ...[
                  NearbyDirectionTitle(
                    label: title,
                    showChevron: onTap != null,
                  ),
                  const Divider(
                    height: EasySubwaySpacing.lg,
                    color: EasySubwayAccessibleColors.borderSubtle,
                  ),
                ],
                if (column.hasData)
                  ...column.rows
                else
                  Expanded(
                    child: NearbyPanelMessage(lines: column.placeholderLines),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 열차 행 대신 카드 가운데에 쓰는 회색 안내 줄.
class NearbyPanelMessage extends StatelessWidget {
  const NearbyPanelMessage({required this.lines, super.key});

  static const style = TextStyle(
    color: EasySubwayAccessibleColors.contentMuted,
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.regular,
    height: 1.4,
  );

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            Text(line, textAlign: TextAlign.center, style: style),
        ],
      ),
    );
  }
}

/// 방면을 하나도 유도할 수 없을 때 카드 없이 쓰는 안내. 응답을 기다리는 중이면
/// ([loading]) 정보 없음 대신 대시를 그리고 "불러오는 중"으로 읽는다.
class NearbyDataUnavailable extends StatelessWidget {
  const NearbyDataUnavailable({
    required this.lines,
    this.loading = false,
    super.key,
  });

  final List<String> lines;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: loading ? nearbyLoadingLabel : lines.join(' '),
      excludeSemantics: true,
      child: Padding(
        key: const Key('networkMapNearbyDataUnavailable'),
        padding: const EdgeInsets.symmetric(vertical: EasySubwaySpacing.md),
        child: NearbyPanelMessage(lines: loading ? nearbyLoadingGlyph : lines),
      ),
    );
  }
}
