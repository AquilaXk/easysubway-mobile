import 'package:flutter/material.dart';

import '../domain/network_map_models.dart';

class NetworkMapStationHitTarget extends StatelessWidget {
  const NetworkMapStationHitTarget({
    required this.station,
    required this.onTap,
    super.key,
  });

  final NetworkMapStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 팬 성능: 축소 상태에서 화면에 잡히는 canonical 역이 수백 개(예: 수도권
    // 축소 시 300~450개)라, 제스처 종료 프레임에서 이 오버레이가 한 번에 재구축
    // 되며 큰 build 스파이크를 만든다. 여기서 GestureDetector를 개별 역마다 두면
    // 그 비용이 배가되는데, 시각(포인터) 탭은 이미 배경 GestureDetector의
    // onTapUp → `_openNearestStation`(`_stationAtViewportPosition` 공간 히트
    // 테스트)이 노드·라벨 폴리곤까지 고려해 전담하므로 개별 GestureDetector는
    // 중복이다. 접근성(스크린리더) 탭만 Semantics onTap 액션으로 남겨 역별
    // 버튼 시맨틱을 유지한다.
    return Semantics(
      button: true,
      label: station.displayName,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}
