/// 보행 프리셋의 UI 라벨·서버 문자열·대표 이동 유형 문자열을 한 곳에 모은 헬퍼.
///
/// 정책 상수(`mobility_profile_policy.dart`)는 값 정본이고, 이 파일은 그 프리셋을
/// UI·저장·요청에서 소비하기 위한 순수 데이터/헬퍼(위젯 없음)만 제공한다. 문구는
/// #1703에서 확정된 표시명·부가설명만 사용한다(창작 금지).
library;

import 'package:flutter/material.dart';

import '../../generated/journey_v3/journey_v3_enums.dart';
import 'mobility_profile_policy.dart';

export '../../generated/journey_v3/journey_v3_enums.dart' show WalkingPace;

/// 선택 UI에 노출하는 프리셋 순서(표준 → 천천히 → 계단 없이 → 휠체어).
const List<MobilityPreset> mobilityPresetDisplayOrder = <MobilityPreset>[
  MobilityPreset.standard,
  MobilityPreset.slow,
  MobilityPreset.noStairs,
  MobilityPreset.stepFree,
];

/// 프리셋 → 서버 문자열('STANDARD','SLOW','NO_STAIRS','STEP_FREE').
String mobilityPresetServerString(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.standard:
      return 'STANDARD';
    case MobilityPreset.slow:
      return 'SLOW';
    case MobilityPreset.noStairs:
      return 'NO_STAIRS';
    case MobilityPreset.stepFree:
      return 'STEP_FREE';
  }
}

/// 서버 문자열 → 프리셋(미지 문자열은 null).
MobilityPreset? mobilityPresetFromServerString(String value) {
  switch (value) {
    case 'STANDARD':
      return MobilityPreset.standard;
    case 'SLOW':
      return MobilityPreset.slow;
    case 'NO_STAIRS':
      return MobilityPreset.noStairs;
    case 'STEP_FREE':
      return MobilityPreset.stepFree;
  }
  return null;
}

/// 프리셋 표시명(UI 노출 문구).
String mobilityPresetDisplayName(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.standard:
      return '보통 걸음';
    case MobilityPreset.slow:
      return '천천히';
    case MobilityPreset.noStairs:
      return '계단 없이';
    case MobilityPreset.stepFree:
      return '휠체어 이용';
  }
}

/// 프리셋 부가 설명(UI 노출 문구).
String mobilityPresetDescription(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.standard:
      return '일반적인 걸음 속도로 안내해요.';
    case MobilityPreset.slow:
      return '여유 있는 걸음 속도로 시간을 계산해요.';
    case MobilityPreset.noStairs:
      return '계단 대신 에스컬레이터·엘리베이터로 안내해요.';
    case MobilityPreset.stepFree:
      return '엘리베이터로만 이동하는 길을 안내해요.\n유모차와 함께일 때도 좋아요.';
  }
}

/// 프리셋 → 대표 이동 유형 문자열(요청·저장에 실리는 mobilityType).
String mobilityPresetRepresentativeMobilityType(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.standard:
      return 'STANDARD';
    case MobilityPreset.slow:
      return 'SENIOR';
    case MobilityPreset.noStairs:
      return 'LUGGAGE';
    case MobilityPreset.stepFree:
      return 'WHEELCHAIR';
  }
}

/// 대표 이동 유형 문자열 → 프리셋(미지 문자열은 null).
MobilityPreset? mobilityPresetFromRepresentativeMobilityType(String value) {
  switch (value) {
    case 'STANDARD':
      return MobilityPreset.standard;
    case 'SENIOR':
      return MobilityPreset.slow;
    case 'LUGGAGE':
      return MobilityPreset.noStairs;
    case 'WHEELCHAIR':
      return MobilityPreset.stepFree;
  }
  return null;
}

/// (마이그레이션용) 구 프로필 id 문자열 → 프리셋.
///
/// 구 온보딩은 6종 프로필 id를 저장했다. 프리셋 도입 시 데이터 소실 없이 승계한다.
MobilityPreset? mobilityPresetFromLegacyProfileId(String profileId) {
  switch (profileId) {
    case 'elderly':
      return MobilityPreset.slow;
    case 'pregnant':
      return MobilityPreset.slow;
    case 'injured':
      return MobilityPreset.slow;
    case 'luggage':
      return MobilityPreset.noStairs;
    case 'stroller':
      return MobilityPreset.stepFree;
    case 'wheelchair':
      return MobilityPreset.stepFree;
  }
  return null;
}

/// 프리셋 행 아이콘(4개 시각 구분).
IconData mobilityPresetIcon(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.standard:
      return Icons.directions_walk_rounded;
    case MobilityPreset.slow:
      return Icons.nordic_walking_rounded;
    case MobilityPreset.noStairs:
      return Icons.elevator_rounded;
    case MobilityPreset.stepFree:
      return Icons.accessible_forward_rounded;
  }
}

/// 프리셋 → 기본 보행 속도.
WalkingPace walkingPaceFromPreset(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.slow:
      return WalkingPace.slow;
    case MobilityPreset.standard:
    case MobilityPreset.noStairs:
    case MobilityPreset.stepFree:
      return WalkingPace.standard;
  }
}

/// 프리셋 → 시설 제약.
FacilityConstraint facilityConstraintFromPreset(MobilityPreset preset) {
  switch (preset) {
    case MobilityPreset.standard:
    case MobilityPreset.slow:
      return FacilityConstraint.none;
    case MobilityPreset.noStairs:
      return FacilityConstraint.noStairs;
    case MobilityPreset.stepFree:
      return FacilityConstraint.elevatorOnly;
  }
}

/// 2차원(보행 속도, 시설 제약) → 가장 가까운 MobilityPreset으로 매핑.
MobilityPreset presetFromDimensions(
  WalkingPace pace,
  FacilityConstraint constraint,
) {
  switch (constraint) {
    case FacilityConstraint.elevatorOnly:
      return MobilityPreset.stepFree;
    case FacilityConstraint.noStairs:
      return MobilityPreset.noStairs;
    case FacilityConstraint.none:
      if (pace == WalkingPace.slow) {
        return MobilityPreset.slow;
      }
      return MobilityPreset.standard;
  }
}

/// 보행 속도 표시명.
String walkingPaceDisplayName(WalkingPace pace) {
  switch (pace) {
    case WalkingPace.slow:
      return '느린 걸음';
    case WalkingPace.standard:
      return '보통 걸음';
    case WalkingPace.fast:
      return '빠른 걸음';
  }
}

/// 보행 속도 수치 라벨.
String walkingPaceSpeedLabel(WalkingPace pace) {
  switch (pace) {
    case WalkingPace.slow:
      return '3.5km/h';
    case WalkingPace.standard:
      return '4.5km/h';
    case WalkingPace.fast:
      return '6.0km/h';
  }
}

/// 보행 속도 아이콘.
IconData walkingPaceIcon(WalkingPace pace) {
  switch (pace) {
    case WalkingPace.slow:
      return Icons.nordic_walking_rounded;
    case WalkingPace.standard:
      return Icons.directions_walk_rounded;
    case WalkingPace.fast:
      return Icons.directions_run_rounded;
  }
}

/// 시설 제약 표시명.
String facilityConstraintDisplayName(FacilityConstraint constraint) {
  switch (constraint) {
    case FacilityConstraint.none:
      return '일반';
    case FacilityConstraint.noStairs:
      return '계단 없이';
    case FacilityConstraint.elevatorOnly:
      return '휠체어·유모차';
  }
}

/// 시설 제약 부가설명.
String facilityConstraintDescription(FacilityConstraint constraint) {
  switch (constraint) {
    case FacilityConstraint.none:
      return '계단 포함';
    case FacilityConstraint.noStairs:
      return '에스컬레이터·승강기';
    case FacilityConstraint.elevatorOnly:
      return '승강기 전용';
  }
}

/// 시설 제약 아이콘.
IconData facilityConstraintIcon(FacilityConstraint constraint) {
  switch (constraint) {
    case FacilityConstraint.none:
      return Icons.directions_walk_rounded;
    case FacilityConstraint.noStairs:
      return Icons.elevator_rounded;
    case FacilityConstraint.elevatorOnly:
      return Icons.accessible_forward_rounded;
  }
}
