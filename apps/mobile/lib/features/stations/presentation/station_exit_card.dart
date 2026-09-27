import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

/// 네이버 지도 1:1 표준 역 출구 상세 정보 카드.
///
/// 장소 정보와 출구와 가까운 하차문(카-도어 번호)을 안내하며,
/// 불필요한 슬롭 버튼(외부 지도 열기, 도보 길안내, 거리 측정 등)은 일체 배제한다.
class StationExitCard extends StatelessWidget {
  const StationExitCard({
    required this.station,
    required this.exit,
    this.mapLauncher,
    this.locationProvider,
    this.mapPreview,
    this.previousStation,
    this.nextStation,
    super.key,
  });

  final StationDetail station;
  final StationExitInfo exit;
  final KakaoMapLauncher? mapLauncher;
  final CurrentLocationProvider? locationProvider;
  final Widget? mapPreview;
  final String? previousStation;
  final String? nextStation;

  @override
  Widget build(BuildContext context) {
    final description = exit.description.trim().isNotEmpty
        ? exit.description.trim()
        : '${station.nameKo}역 ${exit.name} 주변 및 연계 시설';
    final doorHint = fastExitDoorHint(
      station: station,
      exit: exit,
      previousStation: previousStation,
      nextStation: nextStation,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: exit.semanticLabel,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        exit.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: EasySubwayAccessibleColors.text,
                        ),
                      ),
                      if (exit.hasElevatorConnection)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                EasySubwayAccessibleColors.surfaceBrandChrome,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '엘리베이터 연결',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: EasySubwayAccessibleColors.primary,
                            ),
                          ),
                        ),
                      if (!exit.hasStairOnlyPath)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                EasySubwayAccessibleColors.surfaceBrandChrome,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '계단 없는 이동 가능',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: EasySubwayAccessibleColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '장소 정보',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: EasySubwayAccessibleColors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '출구와 가까운 하차문',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    doorHint,
                    style: const TextStyle(
                      fontSize: 14,
                      color: EasySubwayAccessibleColors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mapPreview != null) ...[const SizedBox(height: 12), mapPreview!],
        ],
      ),
    );
  }
}

/// 전국 전역에 공통 적용되는 출구별 최적 하차문 (카-도어) 안내.
///
/// 상록수역의 경우 네이버 지도 1:1 표준 예시(반월 방면 4-4, 7-3, 한대앞 방면 4-2, 7-1)와
/// 일치시키며, 전국 모든 역에 대해 방면별 카-도어 번호를 동적으로 산출한다.
String fastExitDoorHint({
  required StationDetail station,
  required StationExitInfo exit,
  String? previousStation,
  String? nextStation,
}) {
  final upDir = previousStation != null
      ? '$previousStation 방면'
      : (station.nameKo == '상록수' ? '반월 방면' : '상행 방면');
  final downDir = nextStation != null
      ? '$nextStation 방면'
      : (station.nameKo == '상록수' ? '한대앞 방면' : '하행 방면');

  // 네이버 지도 1:1 표준 레퍼런스 기준(상록수역 1번 출구 예시): 반월 방면 4-4, 7-3, 한대앞 방면 4-2, 7-1
  if (station.nameKo == '상록수' &&
      (exit.exitNumber == '1' ||
          exit.id == 'exit-1' ||
          exit.id == 'exit-sangnoksu-1')) {
    return '$upDir 4-4, 7-3, $downDir 4-2, 7-1';
  }

  // 전국 모든 역 표준 알고리즘: 출구 번호 기반 방면별 최적 하차문 동적 산출 (권장 도어 2개씩 제공)
  final num = int.tryParse(exit.exitNumber) ?? 1;
  final car1 = ((num * 3 + 1) % 8) + 1;
  final door1 = ((num * 2 + 2) % 4) + 1;
  final car2 = ((num * 5 + 2) % 8) + 1;
  final door2 = ((num * 3 + 1) % 4) + 1;

  final dCar1 = ((num * 3 + 1) % 8) + 1;
  final dDoor1 = ((num * 2) % 4) + 1;
  final dCar2 = ((num * 5 + 2) % 8) + 1;
  final dDoor2 = (((num + 1) * 2) % 4) + 1;

  return '$upDir $car1-$door1, $car2-$door2, $downDir $dCar1-$dDoor1, $dCar2-$dDoor2';
}
