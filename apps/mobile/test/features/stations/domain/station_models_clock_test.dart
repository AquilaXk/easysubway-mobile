import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';

void main() {
  group('Station verified clock and relative label', () {
    test('withClock Zone 안에서 relative label이 격리된 시계를 따른다', () {
      final fixedDate = DateTime(2026, 7, 10, 12, 0, 0);
      withClock(Clock.fixed(fixedDate), () {
        expect(stationVerifiedRelativeLabel('2026-07-10'), '오늘');
        expect(stationVerifiedRelativeLabel('2026-07-09'), '어제');
        expect(stationVerifiedRelativeLabel('2026-07-07'), '3일 전');
        expect(stationVerifiedRelativeLabel('2026-06-26'), '2주 전');
        expect(stationVerifiedRelativeLabel('2026-05-01'), '2026-05-01');
      });
    });

    test('선택적 now 매개변수를 직접 지정하면 clock과 무관하게 지정된 시각이 적용된다', () {
      final customNow = DateTime(2026, 8, 1, 9, 0, 0);
      expect(stationVerifiedRelativeLabel('2026-08-01', now: customNow), '오늘');
      expect(stationVerifiedRelativeLabel('2026-07-31', now: customNow), '어제');
      expect(
        stationVerifiedRelativeLabel('2026-07-28', now: customNow),
        '4일 전',
      );
    });

    test('withClock 내부 예외가 발생하더라도 외부 Zone의 기본 클록 상태는 오염되지 않는다', () {
      final anomalyTime = DateTime(2099, 1, 1);
      expect(
        () => withClock(Clock.fixed(anomalyTime), () {
          expect(clock.now(), anomalyTime);
          throw Exception('simulated failure inside withClock');
        }),
        throwsA(isA<Exception>()),
      );
      // withClock 외부에서는 2099년이 아닌 실제 현재 시각으로 자동 복원됨
      expect(clock.now().year, lessThan(2099));
    });

    test('withClock Zone 안에서 CurrentLocation.qualityStatus가 격리된 시계를 따른다', () {
      final fixedNow = DateTime(2026, 7, 10, 12, 0, 0);
      withClock(Clock.fixed(fixedNow), () {
        // 10초 전 측정된 위치: freshPrecise
        final freshSample = CurrentLocation(
          latitude: 37.5,
          longitude: 127.0,
          accuracyMeters: 10.0,
          measuredAt: DateTime(2026, 7, 10, 11, 59, 50),
          permissionPrecision: LocationPermissionPrecision.precise,
        );
        expect(
          freshSample.qualityStatus(),
          CurrentLocationQualityStatus.freshPrecise,
        );
        expect(freshSample.canUseForNearbySearch(), true);
        expect(freshSample.nearbySearchBlockedMessage(), isNull);

        // 10분 전 측정된 위치: stale (_nearbyLocationMaxAge: 5분)
        final staleSample = CurrentLocation(
          latitude: 37.5,
          longitude: 127.0,
          accuracyMeters: 10.0,
          measuredAt: DateTime(2026, 7, 10, 11, 50, 0),
          permissionPrecision: LocationPermissionPrecision.precise,
        );
        expect(staleSample.qualityStatus(), CurrentLocationQualityStatus.stale);
        expect(staleSample.canUseForNearbySearch(), false);
        expect(staleSample.nearbySearchBlockedMessage(), isNotNull);
      });
    });
  });
}
