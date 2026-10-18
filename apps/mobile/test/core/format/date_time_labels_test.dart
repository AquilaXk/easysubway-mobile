import 'package:easysubway_mobile/core/format/date_time_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatListDateTime', () {
    final now = DateTime(2026, 10, 18, 14, 30);
    final cases =
        <({String name, DateTime value, DateTime now, bool time, String want})>[
          (
            name: '올해 날짜는 월일과 시각',
            value: DateTime(2026, 10, 18, 14, 5),
            now: now,
            time: false,
            want: '10월 18일 14:05',
          ),
          (
            name: '올해 한 자리 월일',
            value: DateTime(2026, 1, 3, 9, 0),
            now: now,
            time: false,
            want: '1월 3일 09:00',
          ),
          (
            name: '다른 해 날짜는 연월일만',
            value: DateTime(2025, 10, 18, 14, 5),
            now: now,
            time: false,
            want: '2025년 10월 18일',
          ),
          (
            name: '다른 해여도 시각 포함을 요청하면 연월일 시각',
            value: DateTime(2025, 10, 18, 14, 5),
            now: now,
            time: true,
            want: '2025년 10월 18일 14:05',
          ),
          (
            name: '올해는 시각 포함 요청과 무관',
            value: DateTime(2026, 10, 18, 14, 5),
            now: now,
            time: true,
            want: '10월 18일 14:05',
          ),
          (
            name: '자정 직후 올해 첫 순간은 올해 표현',
            value: DateTime(2026, 1, 1, 0, 0),
            now: DateTime(2026, 1, 1, 0, 1),
            time: false,
            want: '1월 1일 00:00',
          ),
          (
            name: '자정 직전 작년 마지막 순간은 연도 표현',
            value: DateTime(2025, 12, 31, 23, 59),
            now: DateTime(2026, 1, 1, 0, 0),
            time: false,
            want: '2025년 12월 31일',
          ),
        ];
    for (final c in cases) {
      test(c.name, () {
        expect(
          formatListDateTime(c.value, now: c.now, alwaysShowTime: c.time),
          c.want,
        );
      });
    }

    test('UTC 기준 시각도 기기 로컬 해로 비교한다', () {
      // 기기 시간대와 무관하게 같은 순간의 값과 기준 시각은 같은 해라 연도가 붙지 않는다.
      final instant = DateTime.utc(2025, 12, 31, 20);
      final nowUtc = DateTime.utc(2025, 12, 31, 20, 30);

      expect(formatListDateTime(instant, now: nowUtc), isNot(contains('년')));
    });
  });

  group('parseServerDateTime', () {
    final cases = <({String name, String raw, DateTime? want})>[
      (
        name: 'offset 없는 값은 UTC',
        raw: '2026-06-13T10:00:00',
        want: DateTime.utc(2026, 6, 13, 10),
      ),
      (
        name: 'Z는 UTC 그대로',
        raw: '2026-06-13T10:00:00Z',
        want: DateTime.utc(2026, 6, 13, 10),
      ),
      (
        name: '+09:00 offset은 같은 순간의 UTC',
        raw: '2026-06-13T10:00:00+09:00',
        want: DateTime.utc(2026, 6, 13, 1),
      ),
      (
        name: '날짜만 있으면 UTC 자정',
        raw: '2026-06-13',
        want: DateTime.utc(2026, 6, 13),
      ),
      (name: '해석 불가 값은 null', raw: '__CREATED_AT__', want: null),
      (name: '빈 문자열은 null', raw: '', want: null),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(parseServerDateTime(c.raw), c.want);
      });
    }
  });

  group('tryFormatServerDateTime', () {
    test('해석 불가 값은 null이라 호출자가 생략한다', () {
      expect(
        tryFormatServerDateTime('__CREATED_AT__', now: DateTime(2026, 10, 18)),
        isNull,
      );
    });

    test('같은 순간은 offset 표기와 무관하게 같은 표현이다', () {
      final now = DateTime(2026, 10, 18, 14, 30);

      expect(
        tryFormatServerDateTime('2026-06-13T01:00:00', now: now),
        tryFormatServerDateTime('2026-06-13T10:00:00+09:00', now: now),
      );
    });
  });
}
