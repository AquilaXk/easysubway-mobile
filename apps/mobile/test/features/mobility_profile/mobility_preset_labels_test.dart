import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_labels.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('프리셋 서버 문자열', () {
    test('프리셋 → 서버 문자열이 계약 값과 일치한다', () {
      expect(mobilityPresetServerString(MobilityPreset.standard), 'STANDARD');
      expect(mobilityPresetServerString(MobilityPreset.slow), 'SLOW');
      expect(mobilityPresetServerString(MobilityPreset.noStairs), 'NO_STAIRS');
      expect(mobilityPresetServerString(MobilityPreset.stepFree), 'STEP_FREE');
    });

    test('서버 문자열 → 프리셋 역파싱', () {
      expect(
        mobilityPresetFromServerString('STANDARD'),
        MobilityPreset.standard,
      );
      expect(mobilityPresetFromServerString('SLOW'), MobilityPreset.slow);
      expect(
        mobilityPresetFromServerString('NO_STAIRS'),
        MobilityPreset.noStairs,
      );
      expect(
        mobilityPresetFromServerString('STEP_FREE'),
        MobilityPreset.stepFree,
      );
      expect(mobilityPresetFromServerString('UNKNOWN'), isNull);
    });

    test('서버 문자열 왕복이 안정적이다', () {
      for (final preset in MobilityPreset.values) {
        expect(
          mobilityPresetFromServerString(mobilityPresetServerString(preset)),
          preset,
        );
      }
    });
  });

  group('대표 이동 유형 문자열', () {
    test('프리셋 → 대표 이동 유형이 계약 값과 일치한다', () {
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.standard),
        'STANDARD',
      );
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.slow),
        'SENIOR',
      );
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.noStairs),
        'LUGGAGE',
      );
      expect(
        mobilityPresetRepresentativeMobilityType(MobilityPreset.stepFree),
        'WHEELCHAIR',
      );
    });

    test('대표 이동 유형 → 프리셋 역산', () {
      expect(
        mobilityPresetFromRepresentativeMobilityType('STANDARD'),
        MobilityPreset.standard,
      );
      expect(
        mobilityPresetFromRepresentativeMobilityType('SENIOR'),
        MobilityPreset.slow,
      );
      expect(
        mobilityPresetFromRepresentativeMobilityType('LUGGAGE'),
        MobilityPreset.noStairs,
      );
      expect(
        mobilityPresetFromRepresentativeMobilityType('WHEELCHAIR'),
        MobilityPreset.stepFree,
      );
      expect(mobilityPresetFromRepresentativeMobilityType('PREGNANT'), isNull);
    });
  });

  group('구 profileId 마이그레이션', () {
    test('6종 구 프로필 id를 데이터 소실 없이 프리셋으로 승계한다', () {
      expect(mobilityPresetFromLegacyProfileId('elderly'), MobilityPreset.slow);
      expect(
        mobilityPresetFromLegacyProfileId('pregnant'),
        MobilityPreset.slow,
      );
      expect(mobilityPresetFromLegacyProfileId('injured'), MobilityPreset.slow);
      expect(
        mobilityPresetFromLegacyProfileId('luggage'),
        MobilityPreset.noStairs,
      );
      expect(
        mobilityPresetFromLegacyProfileId('stroller'),
        MobilityPreset.stepFree,
      );
      expect(
        mobilityPresetFromLegacyProfileId('wheelchair'),
        MobilityPreset.stepFree,
      );
      expect(mobilityPresetFromLegacyProfileId('unknown'), isNull);
    });
  });

  group('표시 문구', () {
    test('표시명이 확정 문구와 일치한다', () {
      expect(mobilityPresetDisplayName(MobilityPreset.standard), '보통 걸음');
      expect(mobilityPresetDisplayName(MobilityPreset.slow), '천천히');
      expect(mobilityPresetDisplayName(MobilityPreset.noStairs), '계단 없이');
      expect(mobilityPresetDisplayName(MobilityPreset.stepFree), '휠체어 이용');
    });

    test('부가설명이 확정 문구와 일치한다', () {
      expect(
        mobilityPresetDescription(MobilityPreset.standard),
        '일반적인 걸음 속도로 안내해요.',
      );
      expect(
        mobilityPresetDescription(MobilityPreset.slow),
        '여유 있는 걸음 속도로 시간을 계산해요.',
      );
      expect(
        mobilityPresetDescription(MobilityPreset.noStairs),
        '계단 대신 에스컬레이터·엘리베이터로 안내해요.',
      );
      expect(
        mobilityPresetDescription(MobilityPreset.stepFree),
        '엘리베이터로만 이동하는 길을 안내해요.\n유모차와 함께일 때도 좋아요.',
      );
    });
  });

  group('2차원 차원 헬퍼 (보행 속도 및 시설 제약)', () {
    test('walkingPaceFromPreset이 프리셋별 기본 속도를 정확히 반환한다', () {
      expect(walkingPaceFromPreset(MobilityPreset.slow), WalkingPace.slow);
      expect(walkingPaceFromPreset(MobilityPreset.standard), WalkingPace.standard);
      expect(walkingPaceFromPreset(MobilityPreset.noStairs), WalkingPace.standard);
      expect(walkingPaceFromPreset(MobilityPreset.stepFree), WalkingPace.standard);
    });

    test('facilityConstraintFromPreset이 프리셋별 시설 제약을 정확히 반환한다', () {
      expect(
        facilityConstraintFromPreset(MobilityPreset.standard),
        FacilityConstraint.none,
      );
      expect(
        facilityConstraintFromPreset(MobilityPreset.slow),
        FacilityConstraint.none,
      );
      expect(
        facilityConstraintFromPreset(MobilityPreset.noStairs),
        FacilityConstraint.noStairs,
      );
      expect(
        facilityConstraintFromPreset(MobilityPreset.stepFree),
        FacilityConstraint.elevatorOnly,
      );
    });

    test('presetFromDimensions가 2차원 조합을 가장 가까운 프리셋으로 매핑한다', () {
      // 일반 시설 제약: 속도에 따라 분기
      expect(
        presetFromDimensions(WalkingPace.slow, FacilityConstraint.none),
        MobilityPreset.slow,
      );
      expect(
        presetFromDimensions(WalkingPace.standard, FacilityConstraint.none),
        MobilityPreset.standard,
      );
      expect(
        presetFromDimensions(WalkingPace.fast, FacilityConstraint.none),
        MobilityPreset.standard,
      );

      // 계단 없이
      expect(
        presetFromDimensions(WalkingPace.slow, FacilityConstraint.noStairs),
        MobilityPreset.noStairs,
      );
      expect(
        presetFromDimensions(WalkingPace.standard, FacilityConstraint.noStairs),
        MobilityPreset.noStairs,
      );
      expect(
        presetFromDimensions(WalkingPace.fast, FacilityConstraint.noStairs),
        MobilityPreset.noStairs,
      );

      // 승강기 전용 (휠체어·유모차)
      expect(
        presetFromDimensions(WalkingPace.slow, FacilityConstraint.elevatorOnly),
        MobilityPreset.stepFree,
      );
      expect(
        presetFromDimensions(WalkingPace.standard, FacilityConstraint.elevatorOnly),
        MobilityPreset.stepFree,
      );
      expect(
        presetFromDimensions(WalkingPace.fast, FacilityConstraint.elevatorOnly),
        MobilityPreset.stepFree,
      );
    });

    test('보행 속도 라벨 및 수치', () {
      expect(walkingPaceDisplayName(WalkingPace.slow), '느린 걸음');
      expect(walkingPaceDisplayName(WalkingPace.standard), '보통 걸음');
      expect(walkingPaceDisplayName(WalkingPace.fast), '빠른 걸음');

      expect(walkingPaceSpeedLabel(WalkingPace.slow), '3.5km/h');
      expect(walkingPaceSpeedLabel(WalkingPace.standard), '4.5km/h');
      expect(walkingPaceSpeedLabel(WalkingPace.fast), '6.0km/h');
    });

    test('시설 제약 라벨 및 부가설명', () {
      expect(facilityConstraintDisplayName(FacilityConstraint.none), '일반');
      expect(facilityConstraintDisplayName(FacilityConstraint.noStairs), '계단 없이');
      expect(facilityConstraintDisplayName(FacilityConstraint.elevatorOnly), '휠체어·유모차');

      expect(facilityConstraintDescription(FacilityConstraint.none), '계단 포함');
      expect(facilityConstraintDescription(FacilityConstraint.noStairs), '에스컬레이터·승강기');
      expect(facilityConstraintDescription(FacilityConstraint.elevatorOnly), '승강기 전용');
    });
  });
}
