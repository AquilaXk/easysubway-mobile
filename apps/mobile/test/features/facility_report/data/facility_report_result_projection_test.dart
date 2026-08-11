import 'package:easysubway_mobile/features/facility_report/data/facility_report_result_projection.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_exception.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_receipt.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success/data envelope에서 시설 제보 결과를 해석한다', () {
    final result = facilityReportResultFromJsonEnvelope({
      'success': true,
      'data': {
        'id': 'report-1',
        'stationId': 'station-1',
        'facilityId': 'facility-1',
        'reportType': 'ELEVATOR',
        'description': '문이 닫히지 않아요.',
        'status': 'RECEIVED',
        'createdAt': '2026-08-12T00:00:00Z',
        'receiptToken': 'receipt-token',
        'publicReceiptCode': 'PUBLIC-1',
      },
    }, errorMessage: '응답 오류');

    expect(result.id, 'report-1');
    expect(result.publicReceiptCode, 'PUBLIC-1');
  });

  test('잘못된 envelope와 data는 caller 오류 문구로 실패한다', () {
    for (final decoded in <Object?>[
      {'success': false},
      {'success': true, 'data': 'invalid'},
    ]) {
      expect(
        () => facilityReportResultFromJsonEnvelope(
          decoded,
          errorMessage: '진행 상황 응답 오류',
        ),
        throwsA(
          isA<FacilityReportException>().having(
            (error) => error.message,
            'message',
            '진행 상황 응답 오류',
          ),
        ),
      );
    }
  });

  test('receipt를 실패 표시용 결과로 그대로 투영한다', () {
    final receipt = FacilityReportReceipt(
      receiptId: 'receipt-1',
      reportId: 'report-1',
      publicReceiptCode: 'PUBLIC-1',
      status: 'RECEIVED',
      receiptToken: 'receipt-token',
      createdAt: DateTime.utc(2026, 8, 12),
    );

    final result = facilityReportResultFromReceipt(receipt);

    expect(result.id, 'report-1');
    expect(result.stationId, isEmpty);
    expect(result.facilityId, isEmpty);
    expect(result.reportType, isEmpty);
    expect(result.description, isEmpty);
    expect(result.status, 'RECEIVED');
    expect(result.createdAt, '2026-08-12T00:00:00.000Z');
    expect(result.receiptToken, 'receipt-token');
    expect(result.publicReceiptCode, 'PUBLIC-1');
  });

  test('server 공개 번호가 비었을 때만 receipt 공개 번호를 사용한다', () {
    const serverResult = FacilityReportResult(
      id: 'report-1',
      stationId: 'station-1',
      facilityId: 'facility-1',
      reportType: 'ELEVATOR',
      description: '설명',
      status: 'RECEIVED',
      createdAt: '2026-08-12T00:00:00Z',
      publicReceiptCode: '   ',
    );
    final receipt = FacilityReportReceipt(
      receiptId: 'receipt-1',
      reportId: 'report-1',
      publicReceiptCode: 'PUBLIC-1',
      status: 'RECEIVED',
      receiptToken: 'receipt-token',
      createdAt: DateTime.utc(2026, 8, 12),
    );

    final fallback = facilityReportResultWithReceiptCodeFallback(
      serverResult,
      receipt,
    );
    const authoritative = FacilityReportResult(
      id: 'report-1',
      stationId: 'station-1',
      facilityId: 'facility-1',
      reportType: 'ELEVATOR',
      description: '설명',
      status: 'RECEIVED',
      createdAt: '2026-08-12T00:00:00Z',
      publicReceiptCode: 'SERVER-1',
    );

    expect(fallback.publicReceiptCode, 'PUBLIC-1');
    expect(
      facilityReportResultWithReceiptCodeFallback(authoritative, receipt),
      same(authoritative),
    );
    expect(nonBlankFacilityReportString('  '), isNull);
    expect(nonBlankFacilityReportString(' value '), 'value');
  });
}
