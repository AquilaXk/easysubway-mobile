import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/notifications/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryNotificationSettingsRepository
    implements NotificationSettingsRepository {
  NotificationSettings settings = const NotificationSettings(
    userId: 'test-user',
    favoriteStationFacilityAlerts: true,
    favoriteRouteFacilityAlerts: false,
    reportStatusAlerts: true,
    dataQualityAlerts: false,
    updatedAt: '2026-09-24T00:00:00',
  );
  final List<NotificationSettings> savedHistory = [];

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    return settings;
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings next,
  ) async {
    savedHistory.add(next);
    settings = next.copyWith(updatedAt: '2026-09-24T00:01:00');
    return settings;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: EasySubwayAccessibleColors.primary,
      ),
    ),
    home: child,
  );
}

void main() {
  testWidgets('알림 설정 화면은 상용 표준 구조(마스터 토글, 2개 그룹, 소제목)를 올바르게 렌더한다', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = _InMemoryNotificationSettingsRepository();

    try {
      await tester.pumpWidget(
        _wrap(NotificationSettingsScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      // 마스터 토글
      expect(find.text('푸시 알림 받기'), findsOneWidget);
      expect(find.text('앱의 주요 상태 및 소식 알림을 받아요'), findsOneWidget);
      expect(
        find.byKey(const Key('notificationSwitch-masterPushAlerts')),
        findsOneWidget,
      );

      // 섹션 1: 이용 및 시설 알림
      expect(find.text('이용 및 시설 알림'), findsOneWidget);
      expect(find.text('역 시설 알림'), findsOneWidget);
      expect(find.text('즐겨찾는 역의 승강기·리프트 고장 및 점검 소식'), findsOneWidget);
      expect(
        find.byKey(
          const Key('notificationSwitch-favoriteStationFacilityAlerts'),
        ),
        findsOneWidget,
      );
      expect(find.text('경로 시설 알림'), findsOneWidget);
      expect(find.text('저장한 이동 경로의 환승 편의시설 운행 상태 안내'), findsOneWidget);
      expect(
        find.byKey(const Key('notificationSwitch-favoriteRouteFacilityAlerts')),
        findsOneWidget,
      );

      // 섹션 2: 공지 및 서비스 안내
      expect(find.text('공지 및 서비스 안내'), findsOneWidget);
      expect(find.text('제보 진행 알림'), findsNothing);
      expect(find.text('내가 등록한 시설 제보의 검토 및 처리 결과'), findsNothing);
      expect(
        find.byKey(const Key('notificationSwitch-reportStatusAlerts')),
        findsNothing,
      );
      expect(find.text('최신 안내 알림'), findsOneWidget);
      expect(find.text('서비스 점검 및 중요한 지하철 운행 공지 안내'), findsOneWidget);
      expect(
        find.byKey(const Key('notificationSwitch-dataQualityAlerts')),
        findsOneWidget,
      );

      // 저장 버튼
      expect(
        find.byKey(const Key('notificationSettingsSaveButton')),
        findsOneWidget,
      );

      // 시맨틱 레이블 호환성 확인
      expect(find.bySemanticsLabel('푸시 알림 받기 켜짐'), findsOneWidget);
      expect(find.bySemanticsLabel('역 시설 알림 켜짐'), findsOneWidget);
      expect(find.bySemanticsLabel('경로 시설 알림 꺼짐'), findsOneWidget);
      expect(find.bySemanticsLabel('제보 진행 알림 켜짐'), findsNothing);
      expect(find.bySemanticsLabel('최신 안내 알림 꺼짐'), findsOneWidget);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('마스터 토글을 끄면 하위 항목이 비활성화되며 저장 시 전체 해제 반영된다', (tester) async {
    final repository = _InMemoryNotificationSettingsRepository();

    await tester.pumpWidget(
      _wrap(NotificationSettingsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    // 마스터 토글 끄기
    await tester.tap(
      find.byKey(const Key('notificationSwitch-masterPushAlerts')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('푸시 알림 받기 꺼짐'), findsOneWidget);

    // 하위 스위치들이 비활성화(disabled)되었는지 확인
    final stationTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(
          const Key('notificationSwitch-favoriteStationFacilityAlerts'),
        ),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(stationTile.onChanged, isNull);

    final routeTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(
          const Key('notificationSwitch-favoriteRouteFacilityAlerts'),
        ),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(routeTile.onChanged, isNull);

    // 비활성화 상태에서 저장
    await tester.tap(find.byKey(const Key('notificationSettingsSaveButton')));
    await tester.pumpAndSettle();

    expect(repository.savedHistory, isNotEmpty);
    expect(repository.savedHistory.last.favoriteStationFacilityAlerts, isFalse);
    expect(repository.savedHistory.last.favoriteRouteFacilityAlerts, isFalse);
    expect(repository.savedHistory.last.reportStatusAlerts, isTrue);
    expect(repository.savedHistory.last.dataQualityAlerts, isFalse);
    expect(find.text('변경 시 자동으로 저장됩니다'), findsOneWidget);

    // 마스터 토글을 다시 켜면 활성화 복원
    await tester.tap(
      find.byKey(const Key('notificationSwitch-masterPushAlerts')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('푸시 알림 받기 켜짐'), findsOneWidget);
    final restoredStationTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(
          const Key('notificationSwitch-favoriteStationFacilityAlerts'),
        ),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(restoredStationTile.onChanged, isNotNull);
  });
}
