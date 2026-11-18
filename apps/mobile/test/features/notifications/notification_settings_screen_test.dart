import 'dart:async';

import 'package:easysubway_mobile/features/notifications/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('알림 설정 화면은 스위치 변경 시 300ms 디바운스 후 자동 저장하며 저장 중 표시를 노출한다', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    final repository = FakeNotificationSettingsRepository()
      ..saveCompleter = saveCompleter;

    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    // Toggle a switch
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    // Advance 300ms for debounce timer -> triggers unawaited(save())
    await tester.pump(const Duration(milliseconds: 300));
    // Now save() is in flight, isSaving is true -> renders '저장 중...'
    expect(find.text('저장 중...'), findsOneWidget);

    // Complete save
    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('저장 중...'), findsNothing);
    expect(find.text('변경 시 자동으로 저장됩니다'), findsOneWidget);
    expect(repository.savedSettings, hasLength(1));
  });

  testWidgets('알림 설정 화면은 NotificationSettingsException 발생 시 롤백하고 스낵바를 띄운다', (
    tester,
  ) async {
    final repository = FakeNotificationSettingsRepository()
      ..saveError = const NotificationSettingsException('네트워크 연결이 불안정합니다.');

    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('네트워크 연결이 불안정합니다.'), findsWidgets);
  });

  testWidgets('알림 설정 화면은 일반 예외 발생 시 롤백하고 기본 에러 스낵바를 띄운다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('알 수 없는 오류')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    final repository = FakeNotificationSettingsRepository()
      ..saveError = Exception('알 수 없는 오류');

    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('알림 설정을 저장하지 못했어요.'), findsWidgets);
  });
}

class FakeNotificationSettingsRepository
    implements NotificationSettingsRepository {
  NotificationSettings settings = const NotificationSettings(
    userId: 'anonymous-user-1',
    favoriteStationFacilityAlerts: true,
    favoriteRouteFacilityAlerts: false,
    reportStatusAlerts: true,
    dataQualityAlerts: false,
    updatedAt: '2026-06-14T09:00:00',
  );
  final savedSettings = <NotificationSettings>[];
  Completer<void>? saveCompleter;
  Object? saveError;

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    return settings;
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) async {
    if (saveCompleter != null) {
      await saveCompleter!.future;
    }
    final error = saveError;
    if (error != null) {
      if (error is Exception) {
        throw error;
      }
      if (error is Error) {
        throw error;
      }
      throw Exception(error.toString());
    }
    savedSettings.add(settings);
    this.settings = settings.copyWith(updatedAt: '2026-06-14T09:05:00');
    return this.settings;
  }
}
