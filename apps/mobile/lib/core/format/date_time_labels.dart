/// 목록·내역 화면이 공유하는 날짜·시각 표현.
///
/// 올해는 "10월 18일 14:05", 다른 해는 "2025년 10월 18일"로 쓴다. 발행 시각처럼
/// 시각 자체가 정보인 화면은 [alwaysShowTime]으로 다른 해에도 "2025년 10월 18일
/// 14:05"를 쓴다. 기준 시각 [now]는 호출자가 주입해 테스트에서 고정할 수 있게
/// 하며, 값과 기준 시각 모두 기기 로컬 시각으로 환산해 비교한다.
String formatListDateTime(
  DateTime value, {
  required DateTime now,
  bool alwaysShowTime = false,
}) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute';
  if (local.year == now.toLocal().year) {
    return '${local.month}월 ${local.day}일 $time';
  }
  final date = '${local.year}년 ${local.month}월 ${local.day}일';
  return alwaysShowTime ? '$date $time' : date;
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
