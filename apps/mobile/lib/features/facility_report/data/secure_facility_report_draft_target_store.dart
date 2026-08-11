import '../../../mobile_error_reporter.dart';
import '../../../secure_key_value_storage.dart';
import '../domain/facility_report_target.dart';

const _facilityReportDraftTargetStorageKey =
    'easysubway.facilityReport.draftTarget';

class SecureFacilityReportDraftTargetStore
    implements FacilityReportDraftTargetStore {
  const SecureFacilityReportDraftTargetStore({
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  final SecureKeyValueStorage storage;

  @override
  Future<FacilityReportTarget?> readTarget() async {
    try {
      final value = await storage.read(
        key: _facilityReportDraftTargetStorageKey,
      );
      if (value == null) {
        return null;
      }
      return FacilityReportTarget.decode(value);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '저장된 시설 제보 대상을 읽는 중 예외가 발생했습니다.',
      );
      await _clearTargetAfterReadFailure();
      return null;
    }
  }

  @override
  Future<void> saveTarget(FacilityReportTarget target) async {
    await storage.write(
      key: _facilityReportDraftTargetStorageKey,
      value: target.encode(),
    );
  }

  @override
  Future<void> clearTarget() async {
    await storage.delete(key: _facilityReportDraftTargetStorageKey);
  }

  Future<void> _clearTargetAfterReadFailure() async {
    try {
      await clearTarget();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '손상된 시설 제보 대상을 지우는 중 예외가 발생했습니다.',
      );
    }
  }
}
