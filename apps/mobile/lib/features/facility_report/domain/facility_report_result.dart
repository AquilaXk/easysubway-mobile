class FacilityReportResult {
  const FacilityReportResult({
    required this.id,
    required this.stationId,
    required this.facilityId,
    required this.reportType,
    required this.description,
    required this.status,
    required this.createdAt,
    this.receiptToken,
    this.publicReceiptCode,
  });

  factory FacilityReportResult.fromJson(Map<String, Object?> json) {
    return FacilityReportResult(
      id: _requiredReportString(json, 'id'),
      stationId: _requiredReportString(json, 'stationId'),
      facilityId: _requiredReportString(json, 'facilityId'),
      reportType: _requiredReportString(json, 'reportType'),
      description: _optionalReportString(json, 'description'),
      status: _requiredReportString(json, 'status'),
      createdAt: _requiredReportString(json, 'createdAt'),
      receiptToken: _optionalReportString(json, 'receiptToken'),
      publicReceiptCode: _optionalReportString(json, 'publicReceiptCode'),
    );
  }

  final String id;
  final String stationId;
  final String facilityId;
  final String reportType;
  final String description;
  final String status;
  final String createdAt;
  final String? receiptToken;
  final String? publicReceiptCode;
}

String _requiredReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required report field: $key');
}

String _optionalReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  return '';
}
