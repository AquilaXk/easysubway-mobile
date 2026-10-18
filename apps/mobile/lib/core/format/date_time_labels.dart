/// 목록·내역 화면이 공유하는 날짜·시각 표현.
///
/// 올해는 "10월 18일 14:05", 다른 해는 "2025년 10월 18일"로 쓴다. 기준 시각
/// [now]는 호출자가 주입해 테스트에서 고정할 수 있게 한다. 값과 기준 시각은
/// 모두 기기 로컬 시각으로 환산해 비교한다.
String formatListDateTime(DateTime value, {required DateTime now}) {
  final local = value.toLocal();
  if (local.year != now.toLocal().year) {
    return '${local.year}년 ${local.month}월 ${local.day}일';
  }
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}월 ${local.day}일 $hour:$minute';
}

/// ISO 8601 문자열을 [formatListDateTime]으로 표시한다. 해석할 수 없으면 null이라
/// 호출자가 그 부분만 생략한다.
String? tryFormatListDateTime(String raw, {required DateTime now}) {
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? null : formatListDateTime(parsed, now: now);
}
