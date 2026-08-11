import 'package:flutter/material.dart';

import '../domain/facility_report_type.dart';

extension FacilityReportTypeOptionLabel on FacilityReportTypeOption {
  String get label {
    return switch (this) {
      FacilityReportTypeOption.broken => '고장',
      FacilityReportTypeOption.underConstruction => '공사 중',
      FacilityReportTypeOption.closed => '폐쇄',
      FacilityReportTypeOption.routeBlocked => '경로가 막혔어요',
      FacilityReportTypeOption.elevatorUnavailable => '엘리베이터 이용 불가',
      FacilityReportTypeOption.stairsPresent => '계단이 있어요',
      FacilityReportTypeOption.etaInaccurate => '도착 시간이 달라요',
      FacilityReportTypeOption.transferImpossible => '환승이 어려워요',
      FacilityReportTypeOption.locationWrong => '위치가 달라요',
      FacilityReportTypeOption.informationWrong => '정보가 달라요',
      FacilityReportTypeOption.recovered => '다시 정상',
    };
  }

  IconData get icon {
    return switch (this) {
      FacilityReportTypeOption.broken => Icons.warning_amber_rounded,
      FacilityReportTypeOption.underConstruction => Icons.construction,
      FacilityReportTypeOption.closed => Icons.block,
      FacilityReportTypeOption.routeBlocked => Icons.route,
      FacilityReportTypeOption.elevatorUnavailable => Icons.elevator,
      FacilityReportTypeOption.stairsPresent => Icons.stairs,
      FacilityReportTypeOption.etaInaccurate => Icons.schedule,
      FacilityReportTypeOption.transferImpossible =>
        Icons.transfer_within_a_station,
      FacilityReportTypeOption.locationWrong => Icons.wrong_location_outlined,
      FacilityReportTypeOption.informationWrong => Icons.edit_note,
      FacilityReportTypeOption.recovered => Icons.check_circle_outline,
    };
  }
}

/// 시설 단위 제보에서 노출할 유효 제보 유형을 시설 타입·현재 상태 라벨로 정한다.
///
/// 서버 enum(`FacilityReportTypeOption`)과 API 계약은 그대로 두고 화면 노출만
/// 제한한다. 원칙:
/// - 경로/역 수준 유형(경로가 막혔어요·계단이 있어요·도착 시간이 달라요·환승이
///   어려워요)은 시설 하나로는 일어날 수 없어 항상 제외한다.
/// - '엘리베이터 이용 불가'는 엘리베이터에서만 노출한다.
/// - 현재 상태가 정상이면 '다시 정상'을 숨기고, 이미 '고장'이면 '고장' 대신
///   '다시 정상'을 노출한다.
List<FacilityReportTypeOption> facilityReportTypeOptionsFor({
  required String facilityTypeLabel,
  required String facilityStatusLabel,
}) {
  final base =
      _facilityReportTypeOptionsByTypeLabel[facilityTypeLabel] ??
      _defaultFacilityReportTypeOptions;
  final isNormal = _normalFacilityStatusLabels.contains(facilityStatusLabel);
  final isBroken = facilityStatusLabel == '고장';
  final options = [
    for (final option in base)
      if (switch (option) {
        // 정상 시설에는 '다시 정상'을 숨긴다.
        FacilityReportTypeOption.recovered => !isNormal,
        // 이미 고장으로 표시된 시설에는 '고장'을 중복 노출하지 않는다.
        FacilityReportTypeOption.broken => !isBroken,
        _ => true,
      })
        option,
  ];
  // 현재 매핑상 필터로 목록이 비는 조합은 없지만, 향후 매핑을 확장하더라도
  // initState의 `.first`가 죽지 않도록 기본 세트로 방어한다.
  return options.isEmpty ? _defaultFacilityReportTypeOptions : options;
}

/// 기본(대부분의 시설) 노출 세트. 경로/역 수준 유형은 제외한다.
const _defaultFacilityReportTypeOptions = <FacilityReportTypeOption>[
  FacilityReportTypeOption.broken,
  FacilityReportTypeOption.underConstruction,
  FacilityReportTypeOption.closed,
  FacilityReportTypeOption.locationWrong,
  FacilityReportTypeOption.informationWrong,
  FacilityReportTypeOption.recovered,
];

/// 시설 타입 라벨별 예외 매핑. 정의되지 않은 라벨은 기본 세트를 쓴다.
const _facilityReportTypeOptionsByTypeLabel =
    <String, List<FacilityReportTypeOption>>{
      // 엘리베이터에만 '엘리베이터 이용 불가'를 추가한다.
      '엘리베이터': [
        FacilityReportTypeOption.broken,
        FacilityReportTypeOption.underConstruction,
        FacilityReportTypeOption.closed,
        FacilityReportTypeOption.elevatorUnavailable,
        FacilityReportTypeOption.locationWrong,
        FacilityReportTypeOption.informationWrong,
        FacilityReportTypeOption.recovered,
      ],
    };

/// 정상으로 간주하는 상태 라벨(‘다시 정상’을 숨기는 기준).
const _normalFacilityStatusLabels = <String>{'정상', '확인 완료'};
