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
    throw const FacilityReportException('제보를 보내지 못했어요.');
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) async {
    throw const FacilityReportException('제보 진행 상황을 확인하지 못했어요.');
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    throw const FacilityReportException('제보 내역을 불러오지 못했어요.');
  }
}
