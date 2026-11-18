import 'package:flutter/material.dart';

import '../../accessible_design.dart';

/// 출발·경유·도착 입력 칸 앞의 역할 점. 상용 지하철 서비스의 입력 칸처럼 노선
/// 마크나 역할 글자 없이 색 고리 하나로 역할을 보인다. 역할은 칸의 Semantics
/// 라벨이 읽으므로 점은 장식이다.
class RouteRoleDot extends StatelessWidget {
  const RouteRoleDot({required this.color, super.key});

  final Color color;

  static const _diameter = 14.0;
  static const _ringWidth = 4.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: _diameter,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: EasySubwayAccessibleColors.surface,
            shape: CircleBorder(
              side: BorderSide(color: color, width: _ringWidth),
            ),
          ),
        ),
      ),
    );
  }
}
