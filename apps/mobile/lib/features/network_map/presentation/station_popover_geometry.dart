import 'dart:ui';

/// 역 말풍선의 설계 크기. 위젯은 이 크기로 그린 뒤 실제 폭에 맞춰 같은 비율로
/// 줄이거나 늘린다. 배치와 카메라 이동이 같은 크기를 보도록 단일 출처로 둔다.
const Size kStationPopoverDesignSize = Size(232, 134);

/// 말풍선 아래 꼬리 끝(설계 좌표). 이 점이 누른 역 노드의 앵커점에 닿게 배치한다.
const Offset kStationPopoverTailTip = Offset(116, 134);

/// 말풍선 몸통 아래 꼬리의 높이와 밑변(설계 좌표).
const double kStationPopoverTailHeight = 9;
const double kStationPopoverTailBase = 18;
