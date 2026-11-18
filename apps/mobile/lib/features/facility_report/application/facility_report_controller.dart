import 'package:flutter/foundation.dart';

import '../../../mobile_error_reporter.dart';
import '../domain/facility_report_exception.dart';
import '../domain/facility_report_photo.dart';
import '../domain/facility_report_repository.dart';
import '../domain/facility_report_request.dart';
import '../domain/facility_report_target.dart';
import '../domain/facility_report_type.dart';
import 'facility_report_state.dart';

class FacilityReportController extends ChangeNotifier {
  FacilityReportController({required this.repository});

  final FacilityReportRepository repository;

  FacilityReportState _state = const FacilityReportState.idle();
  bool _disposed = false;

  FacilityReportState get state => _state;

  Future<void> submit({
    required FacilityReportTarget target,
    required FacilityReportTypeOption selectedType,
    required String description,
    FacilityReportPhotoAttachment? photoAttachment,
    double? latitude,
    double? longitude,
  }) async {
    if (_disposed || _state.status == FacilityReportViewStatus.loading) {
      return;
    }

    _emitState(
      const FacilityReportState(
        status: FacilityReportViewStatus.loading,
        message: '제보 보내는 중',
      ),
    );

    try {
      final result = await repository.createReport(
        FacilityReportRequest(
          stationId: target.stationId,
          facilityId: target.facilityId,
          reportType: selectedType.reportType,
          description: description,
          photoFileName: photoAttachment?.fileName,
          photoContentType: photoAttachment?.contentType,
          photoDataBase64: photoAttachment?.dataBase64,
          latitude: latitude,
          longitude: longitude,
        ),
      );
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.success,
          message: '제보를 보냈어요.',
          result: result,
        ),
      );
    } on FacilityReportException catch (error) {
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 화면 제출 처리 중 예외가 발생했습니다.',
      );
      _emitState(
        const FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: facilityReportSubmitFailureMessage,
        ),
      );
    }
  }

  Future<void> refreshCurrentReport() async {
    final currentResult = _state.result;
    if (_disposed ||
        _state.status == FacilityReportViewStatus.loading ||
        currentResult == null) {
      return;
    }

    _emitState(
      FacilityReportState(
        status: FacilityReportViewStatus.loading,
        message: '제보 진행 상황 확인 중',
        result: currentResult,
      ),
    );

    try {
      final result = await repository.getReport(currentResult.id);
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.success,
          message: '제보 진행 상황을 확인했어요.',
          result: result,
        ),
      );
    } on FacilityReportException catch (error) {
      // 상태 확인이 실패해도 사용자가 제보 번호를 잃지 않도록 직전 결과는 유지한다.
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: error.message,
          result: currentResult,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 진행 상황 새로고침 중 예외가 발생했습니다.',
      );
      // 알 수 없는 오류도 같은 화면에서 살펴볼 수 있게 접수 결과를 보존한다.
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: '제보 진행 상황을 확인하지 못했어요.',
          result: currentResult,
        ),
      );
    }
  }

  void _emitState(FacilityReportState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
