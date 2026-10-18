import '../../../core/format/date_time_labels.dart';
import '../domain/facility_report_result.dart';

extension FacilityReportResultLabels on FacilityReportResult {
  /// 접수 시각 표현. 시각을 해석할 수 없으면 null이라 호출자가 그 부분만 생략한다.
  String? createdAtLabel({required DateTime now}) =>
      tryFormatListDateTime(createdAt, now: now);

  String get displayReceiptCode {
    final code = publicReceiptCode?.trim();
    if (code == null || code.isEmpty) {
      return '발급 전';
    }
    return code;
  }

  String get statusLabel {
    return switch (status) {
      'SUBMITTED' => '접수됨',
      'UNDER_REVIEW' => '확인 중',
      'ACCEPTED' => '반영됨',
      'REJECTED' => '반려됨',
      'DUPLICATE' => '중복 제보',
      'RESOLVED' => '확인 완료',
      _ => '접수 상태를 불러오지 못했어요',
    };
  }

  String get reportTypeLabel {
    return switch (reportType) {
      'BROKEN' => '고장',
      'UNDER_CONSTRUCTION' => '공사 중',
      'CLOSED' => '폐쇄',
      'ROUTE_BLOCKED' => '경로가 막혔어요',
      'ELEVATOR_UNAVAILABLE' => '엘리베이터 이용 불가',
      'STAIRS_PRESENT' => '계단이 있어요',
      'ETA_INACCURATE' => '도착 시간이 달라요',
      'TRANSFER_IMPOSSIBLE' => '환승이 어려워요',
      'LOCATION_WRONG' => '위치가 달라요',
      'INFORMATION_WRONG' => '정보가 달라요',
      'RECOVERED' => '다시 정상',
      _ => '시설 제보',
    };
  }
}
