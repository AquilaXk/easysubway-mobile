import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_result.dart';
import 'package:easysubway_mobile/features/facility_report/presentation/facility_report_form_components.dart';
import 'package:easysubway_mobile/features/facility_report/presentation/facility_report_result_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 제보 진행 상황 패널의 굵기 역할(#503). 상태색 값만 강조, 접수번호는 본문이다.
void main() {
  testWidgets('진행 상황 값은 강조 굵기이고 제보 번호 값은 본문 굵기다', (tester) async {
    const result = FacilityReportResult(
      id: 'report-1',
      publicReceiptCode: 'ES-1001',
      stationId: 'station-sangnoksu',
      facilityId: 'facility-sangnoksu-elevator-1',
      reportType: 'BROKEN',
      description: '문이 열리지 않습니다.',
      status: 'SUBMITTED',
      createdAt: '2026-06-13T10:00:00',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FacilityReportStatusPanel(
            result: result,
            isLoading: false,
            onRefresh: () {},
          ),
        ),
      ),
    );

    FontWeight? weightOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.fontWeight;

    expect(weightOf(result.statusLabel), EasySubwayFontWeight.emphasis);
    expect(weightOf('ES-1001'), EasySubwayFontWeight.regular);
  });
}
