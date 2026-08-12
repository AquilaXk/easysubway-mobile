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

  return FacilityReportResult.fromJson(data);
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
    createdAt: receipt.createdAt.toIso8601String(),
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
