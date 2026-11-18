const facilityReportSubmitFailureMessage = '제보를 보내지 못했어요.';
const facilityReportStatusFailureMessage = '제보 진행 상황을 확인하지 못했어요.';
const facilityReportListFailureMessage = '제보 내역을 불러오지 못했어요.';

class FacilityReportException implements Exception {
  const FacilityReportException(this.message);

  final String message;

  @override
  String toString() => message;
}
