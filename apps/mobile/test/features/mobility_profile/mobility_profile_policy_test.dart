import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 제품 정책에서 고정한 consumer snapshot과 Dart 상수가 어긋나지 않게 한다.
  test('Dart 프리셋 상수는 release policy JSON과 동기화된다', () {
    final json =
        jsonDecode(
              File(
                'test/fixtures/contracts/product/mobility-profile-policy.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(json['schemaVersion'], 1);
    expect(json['artifactKind'], 'mobility-profile-policy');
    expect(
      (json['anchorWalkSpeedMps'] as num).toDouble(),
      MobilityProfilePolicy.anchorWalkSpeedMps,
    );

    final presets = json['presets'] as Map<String, dynamic>;
    final expectedFactorByKey = <String, MobilityPreset>{
      'STANDARD': MobilityPreset.standard,
      'SLOW': MobilityPreset.slow,
      'NO_STAIRS': MobilityPreset.noStairs,
      'STEP_FREE': MobilityPreset.stepFree,
    };

    for (final entry in expectedFactorByKey.entries) {
      final jsonPreset = presets[entry.key] as Map<String, dynamic>;
      final spec = MobilityProfilePolicy.presets[entry.value]!;
      expect(
        (jsonPreset['speedFactor'] as num).toDouble(),
        spec.speedFactor,
        reason: '${entry.key} speedFactor mismatch',
      );
    }

    // 시설 제약 매핑.
    expect(
      MobilityProfilePolicy
          .presets[MobilityPreset.standard]!
          .facilityConstraint,
      FacilityConstraint.none,
    );
    expect(
      MobilityProfilePolicy.presets[MobilityPreset.slow]!.facilityConstraint,
      FacilityConstraint.none,
    );
    expect(
      MobilityProfilePolicy
          .presets[MobilityPreset.noStairs]!
          .facilityConstraint,
      FacilityConstraint.noStairs,
    );
    expect(
      MobilityProfilePolicy
          .presets[MobilityPreset.stepFree]!
          .facilityConstraint,
      FacilityConstraint.elevatorOnly,
    );

    // STEP_FREE 승강기 대기 초.
    expect(
      (presets['STEP_FREE'] as Map<String, dynamic>)['elevatorWaitSeconds'],
      MobilityProfilePolicy.stepFreeElevatorWaitSeconds,
    );
    expect(
      MobilityProfilePolicy
          .presets[MobilityPreset.stepFree]!
          .elevatorWaitSeconds,
      60,
    );
  });

  test('Dart 이동 유형 매핑은 release policy JSON과 동기화된다', () {
    final json =
        jsonDecode(
              File(
                'test/fixtures/contracts/product/mobility-profile-policy.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final mapping = json['mobilityTypeMapping'] as Map<String, dynamic>;

    final expectedTypeByKey = <String, MobilityType>{
      'SENIOR': MobilityType.senior,
      'PREGNANT': MobilityType.pregnant,
      'TEMPORARY_INJURY': MobilityType.temporaryInjury,
      'LUGGAGE': MobilityType.luggage,
      'STROLLER': MobilityType.stroller,
      'WHEELCHAIR': MobilityType.wheelchair,
    };
    final presetByKey = <String, MobilityPreset>{
      'STANDARD': MobilityPreset.standard,
      'SLOW': MobilityPreset.slow,
      'NO_STAIRS': MobilityPreset.noStairs,
      'STEP_FREE': MobilityPreset.stepFree,
    };

    expect(mapping.length, expectedTypeByKey.length);
    expect(
      MobilityProfilePolicy.mobilityTypeMapping.length,
      expectedTypeByKey.length,
    );
    for (final entry in expectedTypeByKey.entries) {
      expect(
        MobilityProfilePolicy.mobilityTypeMapping[entry.value],
        presetByKey[mapping[entry.key] as String],
        reason: '${entry.key} mapping mismatch',
      );
    }
  });
}
