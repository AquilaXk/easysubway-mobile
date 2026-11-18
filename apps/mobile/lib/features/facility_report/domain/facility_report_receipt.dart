class FacilityReportReceipt {
  const FacilityReportReceipt({
    required this.receiptId,
    required this.reportId,
    required this.status,
    required this.receiptToken,
    required this.createdAt,
    this.publicReceiptCode,
  });

  final String receiptId;
  final String reportId;
  final String? publicReceiptCode;
  final String status;
  final String receiptToken;
  final DateTime createdAt;
}

abstract interface class FacilityReportReceiptStore {
  Future<void> saveReceipt(FacilityReportReceipt receipt);

  Future<String?> receiptTokenForReport(String reportId);

  Future<List<FacilityReportReceipt>> listReceipts();
}
