import 'package:easysubway_mobile/features/facility_report/data/facility_report_api_repository.dart';
import 'package:easysubway_mobile/features/facility_report/data/facility_report_result_projection.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_exception.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_receipt.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_result.dart';
import 'package:easysubway_mobile/core/network/api_client.dart';
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

  test('API repository는 실패 receipt와 공개 번호 없는 결과를 투영한다', () async {
    final receipts = [
      FacilityReportReceipt(
        receiptId: 'receipt-failed',
        reportId: 'report-failed',
        publicReceiptCode: 'LOCAL-FAILED',
        status: 'RECEIVED',
        receiptToken: 'failed-token',
        createdAt: DateTime.utc(2026, 8, 11),
      ),
      FacilityReportReceipt(
        receiptId: 'receipt-blank',
        reportId: 'report-blank',
        status: 'RECEIVED',
        receiptToken: 'blank-token',
        createdAt: DateTime.utc(2026, 8, 12),
      ),
    ];
    final store = _ProjectionReceiptStore(receipts);
    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('https://example.invalid'),
      receiptStore: store,
      apiClient: _ProjectionApiClient({
        '/api/v1/reports/report-failed': const ApiResponse(
          statusCode: 500,
          jsonBody: null,
        ),
        '/api/v1/reports/report-blank': const ApiResponse(
          statusCode: 200,
          jsonBody: {
            'success': true,
            'data': {
              'id': 'report-blank',
              'stationId': 'station-1',
              'facilityId': 'facility-1',
              'reportType': 'ELEVATOR',
              'description': '설명',
              'status': 'ACCEPTED',
              'createdAt': '2026-08-12T00:00:00Z',
            },
          },
        ),
      }),
    );

    final results = await repository.listMyReports();

    expect(results.first.id, 'report-failed');
    expect(results.first.stationId, isEmpty);
    expect(results.first.publicReceiptCode, 'LOCAL-FAILED');
    expect(results.last.id, 'report-blank');
    expect(results.last.publicReceiptCode, isEmpty);
    expect(store.saved.single.reportId, 'report-blank');
    expect(store.saved.single.publicReceiptCode, isNull);
  });
}

class _ProjectionApiClient extends ApiClient {
  _ProjectionApiClient(this.responses)
    : super(baseUri: Uri.parse('https://example.invalid'));

  final Map<String, ApiResponse> responses;

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    return responses[path]!;
  }
}

class _ProjectionReceiptStore implements FacilityReportReceiptStore {
  _ProjectionReceiptStore(this.receipts);

  final List<FacilityReportReceipt> receipts;
  final List<FacilityReportReceipt> saved = [];

  @override
  Future<List<FacilityReportReceipt>> listReceipts() async => receipts;

  @override
  Future<String?> receiptTokenForReport(String reportId) async {
    return receipts
        .singleWhere((receipt) => receipt.reportId == reportId)
        .receiptToken;
  }

  @override
  Future<void> saveReceipt(FacilityReportReceipt receipt) async {
    saved.add(receipt);
  }
}
