import 'package:easysubway_mobile/features/facility_report/domain/facility_report_request.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_result.dart';
import 'package:easysubway_mobile/features/facility_report/presentation/my_facility_reports_screens.dart';
import 'package:easysubway_mobile/features/notifications/presentation/notification_inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FacilityReportResult _report(String createdAt) => FacilityReportResult(
  id: 'report-1',
  publicReceiptCode: 'ES-1001',
  stationId: 'station-1',
  facilityId: 'facility-1',
  reportType: 'CLOSED',
  description: '출입문이 막혀 있습니다.',
  status: 'ACCEPTED',
  createdAt: createdAt,
);

class _Repository implements FacilityReportRepository {
  _Repository(this.reports);

  final List<FacilityReportResult> reports;

  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) =>
      throw UnimplementedError();

  @override
  Future<FacilityReportResult> getReport(String reportId) =>
      throw UnimplementedError();

  @override
  Future<List<FacilityReportResult>> listMyReports() async => reports;
}

final _now = DateTime(2026, 10, 18, 14, 30);

Future<void> _pumpInbox(WidgetTester tester, FacilityReportResult report) =>
    tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxScreen(
          favoriteFacilityRepository: null,
          reportRepository: _Repository([report]),
          notificationRepository: null,
          notificationPermissionProvider: null,
          onOpenReport: (_) {},
          now: () => _now,
        ),
      ),
    );

Future<void> _pumpMyReports(WidgetTester tester, FacilityReportResult report) =>
    tester.pumpWidget(
      MaterialApp(
        home: MyFacilityReportListScreen(
          repository: _Repository([report]),
          now: () => _now,
        ),
      ),
    );

String _semanticsLabelOf(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).label;

void main() {
  const cases = <({String name, String createdAt, String shown})>[
    (name: '올해', createdAt: '2026-10-18T14:05:00', shown: '10월 18일 14:05'),
    (name: '다른 해', createdAt: '2025-10-18T14:05:00', shown: '2025년 10월 18일'),
  ];

  for (final c in cases) {
    group('접수 시각 표현 (${c.name})', () {
      testWidgets('알림함은 접수 시각을 semantics 라벨에 쓴다', (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpInbox(tester, _report(c.createdAt));
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('제보 반영됨, 제보 번호 ES-1001, ${c.shown} 접수'),
          findsOneWidget,
        );
        handle.dispose();
      });

      testWidgets('내 제보는 목록 글자와 semantics 라벨에 같은 표현을 쓴다', (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpMyReports(tester, _report(c.createdAt));
        await tester.pumpAndSettle();

        expect(find.text('제보 번호 ES-1001\n${c.shown} 접수'), findsOneWidget);
        expect(
          _semanticsLabelOf(tester, find.byKey(const Key('myReport-report-1'))),
          contains('${c.shown} 접수'),
        );
        handle.dispose();
      });

      testWidgets('내 제보 상세는 같은 표현을 접수 행에 쓴다', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MyFacilityReportDetailScreen(
              report: _report(c.createdAt),
              now: () => _now,
            ),
          ),
        );

        expect(find.text('접수'), findsOneWidget);
        expect(find.text(c.shown), findsOneWidget);
      });
    });
  }

  testWidgets('해석할 수 없는 접수 시각은 그 부분만 생략한다', (tester) async {
    await _pumpMyReports(tester, _report('__CREATED_AT__'));
    await tester.pumpAndSettle();

    expect(find.text('제보 번호 ES-1001'), findsOneWidget);
    expect(find.textContaining(RegExp(r' 접수$')), findsNothing);
  });
}
