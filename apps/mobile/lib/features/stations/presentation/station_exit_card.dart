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
                  if (doorHint != null) ...[
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

/// 공식 출구 연계 하차문 (카-도어) 안내 문구 반환.
///
/// 공식 데이터([exit.nearbyDoorHint])가 존재하는 경우에만 노출하며,
/// 임의의 모듈로 산술이나 역 이름 하드코딩 분기는 일체 배제한다.
String? fastExitDoorHint({
  required StationDetail station,
  required StationExitInfo exit,
  String? previousStation,
  String? nextStation,
}) {
  final hint = exit.nearbyDoorHint?.trim();
  if (hint == null || hint.isEmpty) {
    return null;
  }
  return hint;
}
