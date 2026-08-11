import 'package:drift/drift.dart' show OrderingTerm, Value;

import '../../../core/database/user/user_database.dart' as user_db;
import '../../../secure_key_value_storage.dart';
import '../domain/facility_report_receipt.dart';

class DriftFacilityReportReceiptStore implements FacilityReportReceiptStore {
  const DriftFacilityReportReceiptStore({
    required this.userDatabase,
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  final user_db.UserDatabase userDatabase;
  final SecureKeyValueStorage storage;

  @override
  Future<void> saveReceipt(FacilityReportReceipt receipt) async {
    final secureKey = 'easysubway.facilityReport.receipt.${receipt.receiptId}';
    await storage.write(key: secureKey, value: receipt.receiptToken);
    await userDatabase
        .into(userDatabase.reportReceipts)
        .insertOnConflictUpdate(
          user_db.ReportReceiptsCompanion.insert(
            receiptId: receipt.receiptId,
            reportId: Value(receipt.reportId),
            publicReceiptCode: Value(receipt.publicReceiptCode),
            status: receipt.status,
            createdAt: receipt.createdAt,
          ),
        );
  }

  @override
  Future<String?> receiptTokenForReport(String reportId) async {
    final trimmedReportId = reportId.trim();
    if (trimmedReportId.isEmpty) {
      return null;
    }
    final directToken = await storage.read(
      key: 'easysubway.facilityReport.receipt.$trimmedReportId',
    );
    if (directToken != null && directToken.isNotEmpty) {
      return directToken;
    }
    final receipt = await (userDatabase.select(
      userDatabase.reportReceipts,
    )..where((row) => row.reportId.equals(trimmedReportId))).getSingleOrNull();
    if (receipt == null) {
      return null;
    }
    return storage.read(
      key: 'easysubway.facilityReport.receipt.${receipt.receiptId}',
    );
  }

  @override
  Future<List<FacilityReportReceipt>> listReceipts() async {
    final receipts = await (userDatabase.select(
      userDatabase.reportReceipts,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    final results = <FacilityReportReceipt>[];
    for (final receipt in receipts) {
      final reportId = receipt.reportId?.trim();
      if (reportId == null || reportId.isEmpty) {
        continue;
      }
      final receiptToken = await storage.read(
        key: 'easysubway.facilityReport.receipt.${receipt.receiptId}',
      );
      if (receiptToken == null || receiptToken.isEmpty) {
        continue;
      }
      results.add(
        FacilityReportReceipt(
          receiptId: receipt.receiptId,
          reportId: reportId,
          publicReceiptCode: receipt.publicReceiptCode,
          status: receipt.status,
          receiptToken: receiptToken,
          createdAt: receipt.createdAt,
        ),
      );
    }
    return results;
  }
}
