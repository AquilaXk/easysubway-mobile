import 'facility_report_exception.dart';
import 'facility_report_request.dart';
import 'facility_report_result.dart';

abstract class FacilityReportRepository {
  Future<FacilityReportResult> createReport(FacilityReportRequest request);

  Future<FacilityReportResult> getReport(String reportId);

  Future<List<FacilityReportResult>> listMyReports();
}

class UnavailableFacilityReportRepository implements FacilityReportRepository {
  const UnavailableFacilityReportRepository();

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest request,
  ) async {
    throw const FacilityReportException(facilityReportSubmitFailureMessage);
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) async {
    throw const FacilityReportException(facilityReportStatusFailureMessage);
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    throw const FacilityReportException(facilityReportListFailureMessage);
  }
}
