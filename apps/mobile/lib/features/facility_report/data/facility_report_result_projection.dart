import '../../../core/format/date_time_labels.dart';
import '../../../mobile_error_reporter.dart';
import '../domain/facility_report_exception.dart';
import '../domain/facility_report_receipt.dart';
import '../domain/facility_report_result.dart';

FacilityReportResult facilityReportResultFromJsonEnvelope(
  Object? decoded, {
  required String errorMessage,
}) {
  if (decoded is! Map<String, Object?> || decoded['success'] != true) {
    throw FacilityReportException(errorMessage);
  }

  final data = decoded['data'];
  if (data is! Map<String, Object?>) {
    throw FacilityReportException(errorMessage);
  }

  final result = FacilityReportResult.fromJson(data);
  if (parseServerDateTime(result.createdAt) == null) {
    // 화면은 접수 시각만 생략한다. 서버 형식이 바뀌면 모니터링에서 보이게 한다.
    reportMobileError(
      const FormatException('Unparseable report field: createdAt'),
      StackTrace.current,
      context: '시설 제보 접수 시각을 해석하지 못했습니다.',
    );
  }
  return result;
}

FacilityReportResult facilityReportResultFromReceipt(
  FacilityReportReceipt receipt,
) {
  return FacilityReportResult(
    id: receipt.reportId,
    stationId: '',
    facilityId: '',
    reportType: '',
    description: '',
    status: receipt.status,
    createdAt: receipt.createdAt.toUtc().toIso8601String(),
    receiptToken: receipt.receiptToken,
    publicReceiptCode: receipt.publicReceiptCode,
  );
}

FacilityReportResult facilityReportResultWithReceiptCodeFallback(
  FacilityReportResult report,
  FacilityReportReceipt receipt,
) {
  final publicReceiptCode =
      nonBlankFacilityReportString(report.publicReceiptCode) ??
      nonBlankFacilityReportString(receipt.publicReceiptCode);
  if (publicReceiptCode == null ||
      publicReceiptCode == report.publicReceiptCode) {
    return report;
  }
  return FacilityReportResult(
    id: report.id,
    stationId: report.stationId,
    facilityId: report.facilityId,
    reportType: report.reportType,
    description: report.description,
    status: report.status,
    createdAt: report.createdAt,
    receiptToken: report.receiptToken,
    publicReceiptCode: publicReceiptCode,
  );
}

String? nonBlankFacilityReportString(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
