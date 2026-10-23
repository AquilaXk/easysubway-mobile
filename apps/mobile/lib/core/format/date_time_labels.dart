/// 목록·내역 화면이 공유하는 날짜·시각 표현.
///
/// 올해는 "10월 18일 14:05", 다른 해는 "2025년 10월 18일"로 쓴다. 제보·공지·알림이
/// 같은 규칙을 쓴다. 기준 시각 [now]는 호출자가 주입해 테스트에서 고정할 수 있게
/// 하며, 값과 기준 시각 모두 기기 로컬 시각으로 환산해 비교한다.
String formatListDateTime(DateTime value, {required DateTime now}) {
  final local = value.toLocal();
  if (local.year != now.toLocal().year) {
    return '${local.year}년 ${local.month}월 ${local.day}일';
  }
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}월 ${local.day}일 $hour:$minute';
}

final _offsetPattern = RegExp(r'(?:[zZ]|[+-]\d{2}(?::?\d{2})?)$');

/// 서버가 내려준 시각 문자열을 해석한다. 날짜만 있으면 그 날 UTC 자정이다. 백엔드는 UTC 시계의 LocalDateTime을
/// offset 없이 직렬화하므로 offset이 없으면 UTC로 읽고, 기기 로컬 시각으로 먼저
/// 해석하면 DST 결손 구간이 보정되므로 처음부터 UTC로 파싱한다. 해석할 수 없으면
/// null이다.
DateTime? parseServerDateTime(String raw) {
  final timeIndex = raw.indexOf('T');
  if (timeIndex == -1) {
    return DateTime.tryParse('${raw}T00:00:00Z');
  }
  final hasOffset = _offsetPattern.hasMatch(raw.substring(timeIndex));
  return DateTime.tryParse(hasOffset ? raw : '${raw}Z');
}

/// 서버 시각 문자열을 [formatListDateTime]으로 표시한다. 해석할 수 없으면 null이라
/// 호출자가 그 부분만 생략한다.
String? tryFormatServerDateTime(String raw, {required DateTime now}) {
  final parsed = parseServerDateTime(raw);
  return parsed == null ? null : formatListDateTime(parsed, now: now);
}

DateTime _kst(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

/// 서울 표준시(KST) `HH:mm`.
String kstTime(DateTime instant) {
  final value = _kst(instant);
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

const _hoursPerHalfDay = 12;

(String, int) _halfDayHour(DateTime instant) {
  final hour = _kst(instant).hour;
  final twelve = hour % _hoursPerHalfDay == 0
      ? _hoursPerHalfDay
      : hour % _hoursPerHalfDay;
  return (hour < _hoursPerHalfDay ? '오전' : '오후', twelve);
}

/// 서울 표준시 12시간제 `오전 5:11`. 자정 시는 `오전 12:36`이다.
String kstClock(DateTime instant) {
  final (half, hour) = _halfDayHour(instant);
  return '$half $hour:${_kst(instant).minute.toString().padLeft(2, '0')}';
}

/// 스크린리더용 `오전 5시 11분`.
String kstSpokenClock(DateTime instant) {
  final (half, hour) = _halfDayHour(instant);
  return '$half $hour시 ${_kst(instant).minute}분';
}

/// 목록 행 끝의 짧은 날짜. 올해는 `10. 24.`, 다른 해는 `2025. 12. 31.`이다.
String formatShortDate(DateTime value, {required DateTime now}) {
  final local = value.toLocal();
  final monthDay = '${local.month}. ${local.day}.';
  return local.year == now.toLocal().year
      ? monthDay
      : '${local.year}. $monthDay';
}

/// [formatShortDate]의 스크린리더 표현. 올해는 `10월 24일`, 다른 해는
/// `2025년 12월 31일`이다.
String formatSpokenDate(DateTime value, {required DateTime now}) {
  final local = value.toLocal();
  final monthDay = '${local.month}월 ${local.day}일';
  return local.year == now.toLocal().year
      ? monthDay
      : '${local.year}년 $monthDay';
}
