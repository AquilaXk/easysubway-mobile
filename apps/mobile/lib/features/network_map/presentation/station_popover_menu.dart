import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/ui/line_mark.dart';
import '../../../design_tokens.dart';
import '../../route_draft/domain/route_draft.dart';

/// 역 말풍선의 설계 크기. 위젯은 이 크기로 그린 뒤 실제 폭에 맞춰 같은 비율로
/// 줄이거나 늘린다. 배치와 카메라 이동이 같은 크기를 보도록 단일 출처로 둔다.
const Size kStationPopoverDesignSize = Size(232, 134);

/// 말풍선 아래 꼬리 끝(설계 좌표). 이 점이 누른 역 노드의 앵커점에 닿게 배치한다.
const Offset kStationPopoverTailTip = Offset(116, 134);

/// 말풍선 몸통 아래 꼬리의 높이와 밑변(설계 좌표).
const double kStationPopoverTailHeight = 9;
const double kStationPopoverTailBase = 18;

/// 출발·경유·도착 칸 하나의 표시 정보.
typedef _SlotCopy = ({
  String label,
  String setLabel,
  String clearLabel,
  Color pin,
});

const Map<RouteDraftSlot, _SlotCopy> _slotCopy = {
  RouteDraftSlot.origin: (
    label: '출발',
    setLabel: '출발역으로 설정',
    clearLabel: '출발역 해제',
    pin: EasySubwayPopoverColors.originPin,
  ),
  RouteDraftSlot.waypoint: (
    label: '경유',
    setLabel: '경유지로 추가',
    clearLabel: '경유지 해제',
    pin: EasySubwayPopoverColors.waypointPin,
  ),
  RouteDraftSlot.destination: (
    label: '도착',
    setLabel: '도착역으로 설정',
    clearLabel: '도착역 해제',
    pin: EasySubwayPopoverColors.destinationPin,
  ),
};

const _slotOrder = [
  RouteDraftSlot.origin,
  RouteDraftSlot.waypoint,
  RouteDraftSlot.destination,
];

/// 노선도에서 누른 역 위에 뜨는 어두운 말풍선. 상용 지하철 서비스처럼 윗줄은
/// 출발·경유·도착 핀, 아랫줄은 실시간·전체 시간표다. 이미 정한 칸은 `출발 해제`처럼
/// 쓰고, 누르면 같은 슬롯을 보내 부모가 해제한다. 닫기 칸은 없고, 지도 빈 곳을
/// 누르거나 스크린리더의 닫기 동작([onClose])으로 닫는다.
///
/// [kStationPopoverDesignSize]로 그린 뒤 [width]에 맞춰 같은 비율로 맞춘다. 배치
/// 정책이 같은 크기로 위치를 계산한다. 크기가 정해진 칸이라 글자 배율은 노선 마크와
/// 같은 상한([lineMarkFixedChromeMaxTextScale])까지 따르고, 넘치는 라벨은 줄여 맞춘다.
class StationPopoverMenu extends StatelessWidget {
  const StationPopoverMenu({
    required this.width,
    required this.selectedSlots,
    required this.disabledSlots,
    required this.onAction,
    required this.onClose,
    this.onRealtime,
    this.onTimetable,
    this.stationName,
    super.key,
  });

  final double width;
  final Set<RouteDraftSlot> selectedSlots;
  final Set<RouteDraftSlot> disabledSlots;
  final ValueChanged<RouteDraftSlot> onAction;
  final VoidCallback onClose;
  final VoidCallback? onRealtime;
  final VoidCallback? onTimetable;

  /// 화면에는 그리지 않고 스크린리더 그룹 라벨로만 쓴다. `서울역`처럼 역으로 끝나는
  /// 표시명을 넘긴다.
  final String? stationName;

  static const _stationActionsHeight = 52.0;
  static const _labelStyle = TextStyle(
    color: EasySubwayPopoverColors.onSurface,
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.regular,
  );

  @override
  Widget build(BuildContext context) {
    final design = kStationPopoverDesignSize;
    final name = stationName?.trim();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: (name == null || name.isEmpty) ? null : '$name 메뉴',
      onDismiss: onClose,
      child: SizedBox(
        width: width,
        height: width * design.height / design.width,
        child: FittedBox(
          child: SizedBox.fromSize(
            size: design,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: lineMarkFixedChromeMaxTextScale,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    Expanded(child: _body()),
                    CustomPaint(
                      size: const Size(
                        double.infinity,
                        kStationPopoverTailHeight,
                      ),
                      painter: _TailPainter(EasySubwayPopoverColors.surface),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final realtime = onRealtime;
    final timetable = onTimetable;
    return ClipRRect(
      borderRadius: BorderRadius.circular(EasySubwayRadius.card),
      child: ColoredBox(
        color: EasySubwayPopoverColors.surface,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final slot in _slotOrder)
                    Expanded(child: _slotButton(slot)),
                ],
              ),
            ),
            if (realtime != null || timetable != null)
              SizedBox(
                height: _stationActionsHeight,
                child: Row(
                  children: [
                    if (realtime != null)
                      Expanded(child: _actionButton('실시간', realtime)),
                    if (realtime != null && timetable != null)
                      const SizedBox(width: 2),
                    if (timetable != null)
                      Expanded(child: _actionButton('전체 시간표', timetable)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slotButton(RouteDraftSlot slot) {
    final copy = _slotCopy[slot]!;
    final selected = selectedSlots.contains(slot);
    final enabled = !disabledSlots.contains(slot);
    final onTap = enabled ? () => onAction(slot) : null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: selected ? copy.clearLabel : copy.setLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : EasySubwayFanMenuColors.disabledOpacity,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, size: 26, color: copy.pin),
              const SizedBox(height: 2),
              _fittedLabel(selected ? '${copy.label} 해제' : copy.label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: EasySubwayPopoverColors.actionSurface,
        child: InkWell(
          onTap: onTap,
          child: Center(child: _fittedLabel(label)),
        ),
      ),
    );
  }

  Widget _fittedLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EasySubwaySpacing.xs),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, style: _labelStyle),
      ),
    );
  }
}

/// 몸통 아래 가운데에서 역을 가리키는 꼬리.
class _TailPainter extends CustomPainter {
  _TailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    const halfBase = kStationPopoverTailBase / 2;
    final path = Path()
      ..moveTo(center - halfBase, 0)
      ..lineTo(center + halfBase, 0)
      ..lineTo(center, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => oldDelegate.color != color;
}
