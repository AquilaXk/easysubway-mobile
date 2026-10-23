import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/station_models.dart';

/// 선택한 출구의 정보. 상용 지하철 서비스처럼 제목 없이 주변 시설 문장과 출구와
/// 가까운 하차문을 쓴다. 원천에 없는 값은 줄을 만들지 않고 자리표시 문구로 채우지
/// 않는다.
///
/// 맨 위 한 줄은 교통약자를 위해 우리가 더한 출구 접근성이다. 원천이 확인한 계단
/// 정보만 쓴다. 출구와 엘리베이터의 연결은 데이터팩이 있음·없음·모름을 가르지
/// 못해(`has_elevator_connection`은 기본값 false인 bool) 아직 쓰지 않는다.
class StationExitCard extends StatelessWidget {
  const StationExitCard({required this.exit, super.key});

  final StationExitInfo exit;

  static const _accessStyle = TextStyle(
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.emphasis,
    color: EasySubwayAccessibleColors.text,
    height: 1.4,
  );
  static const _bodyStyle = TextStyle(
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.regular,
    color: EasySubwayAccessibleColors.secondaryText,
    height: 1.5,
  );
  static const _titleStyle = TextStyle(
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.emphasis,
    color: EasySubwayAccessibleColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final access = exit.stairPathLabel;
    final description = exit.description.trim();
    final doorHint = exit.hasNearbyDoorHint
        ? exit.nearbyDoorHint!.trim()
        : null;
    final lines = <Widget>[
      if (access != null) Text(access, style: _accessStyle),
      if (description.isNotEmpty) Text(description, style: _bodyStyle),
      if (doorHint != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('출구와 가까운 하차문', style: _titleStyle),
            const SizedBox(height: EasySubwaySpacing.xs),
            Text(doorHint, style: _bodyStyle),
          ],
        ),
    ];
    return Semantics(
      container: true,
      label: exit.semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, line) in lines.indexed) ...[
              if (index > 0) const SizedBox(height: EasySubwaySpacing.md),
              line,
            ],
          ],
        ),
      ),
    );
  }
}
