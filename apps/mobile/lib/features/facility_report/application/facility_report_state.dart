import '../domain/facility_report_result.dart';

enum FacilityReportViewStatus { idle, loading, success, failure }

class FacilityReportState {
  const FacilityReportState({
    required this.status,
    this.message = '',
    this.result,
  });

  const FacilityReportState.idle()
    : status = FacilityReportViewStatus.idle,
      message = '',
      result = null;

  final FacilityReportViewStatus status;
  final String message;
  final FacilityReportResult? result;
}
