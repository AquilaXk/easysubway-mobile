import 'package:easysubway_mobile/core/format/date_time_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatListDateTime', () {
    final now = DateTime(2026, 10, 18, 14, 30);
    final cases = <({String name, DateTime value, DateTime now, String want})>[
      (
        name: '올해 날짜는 월일과 시각',
        value: DateTime(2026, 10, 18, 14, 5),
        now: now,
        want: '10월 18일 14:05',
      ),
      (
        name: '올해 1월 한 자리 월일',
        value: DateTime(2026, 1, 3, 9, 0),
        now: now,
        want: '1월 3일 09:00',
      ),
      (
        name: '다른 해 날짜는 연월일만',
        value: DateTime(2025, 10, 18, 14, 5),
        now: now,
        want: '2025년 10월 18일',
      ),
      (
        name: '자정 직후 올해 첫 순간은 올해 표현',
        value: DateTime(2026, 1, 1, 0, 0),
        now: DateTime(2026, 1, 1, 0, 1),
        want: '1월 1일 00:00',
      ),
      (
        name: '자정 직전 작년 마지막 순간은 연도 표현',
        value: DateTime(2025, 12, 31, 23, 59),
        now: DateTime(2026, 1, 1, 0, 0),
        want: '2025년 12월 31일',
      ),
      (
        name: 'UTC 값은 기기 로컬 시각으로 바꿔 표시',
        value: DateTime.utc(2026, 10, 18, 14, 5).toLocal(),
        now: now,
        want:
            '${DateTime.utc(2026, 10, 18, 14, 5).toLocal().month}월 '
            '${DateTime.utc(2026, 10, 18, 14, 5).toLocal().day}일 '
            '${DateTime.utc(2026, 10, 18, 14, 5).toLocal().hour.toString().padLeft(2, '0')}:05',
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(formatListDateTime(c.value, now: c.now), c.want);
      });
    }

    test('UTC 입력도 로컬로 환산한다', () {
      final utc = DateTime.utc(2026, 10, 18, 14, 5);
      final local = utc.toLocal();
      expect(
        formatListDateTime(utc, now: now),
        formatListDateTime(local, now: now),
      );
    });
  });

  group('tryFormatListDateTime', () {
    final now = DateTime(2026, 10, 18, 14, 30);
    final cases = <({String name, String raw, String? want})>[
      (name: 'offset 없는 ISO', raw: '2026-06-13T10:00:00', want: '6월 13일 10:00'),
      (name: '다른 해', raw: '2025-12-31T23:59:00', want: '2025년 12월 31일'),
      (name: '해석 불가 값은 null', raw: '__CREATED_AT__', want: null),
      (name: '빈 문자열은 null', raw: '', want: null),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(tryFormatListDateTime(c.raw, now: now), c.want);
      });
    }
  });
}
