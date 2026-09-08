import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/notifications/presentation/new_notification_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  ValueNotifier<bool>? disruption,
  required bool hasNotificationItems,
  VoidCallback? onOpenInbox,
}) {
  return MaterialApp(
    home: Scaffold(
      body: NewNotificationBar(
        disruptionChanges: disruption,
        hasDisruption: disruption == null ? null : () => disruption.value,
        hasNotificationItems: hasNotificationItems,
        onOpenInbox: onOpenInbox ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('운행 공지 disruption만 있어도 바를 표시한다', (tester) async {
    final disruption = ValueNotifier(true);
    addTearDown(disruption.dispose);

    await tester.pumpWidget(
      _host(disruption: disruption, hasNotificationItems: false),
    );

    expect(find.byKey(const Key('newNotificationBar')), findsOneWidget);
    expect(find.text('새로운 알림이 있어요'), findsOneWidget);
    expect(find.text('알림 보기'), findsOneWidget);
  });

  testWidgets('알림함 새 항목만 있어도 바를 표시한다', (tester) async {
    await tester.pumpWidget(_host(hasNotificationItems: true));

    expect(find.byKey(const Key('newNotificationBar')), findsOneWidget);
  });

  testWidgets('알림이 없으면 바도 여백도 그리지 않는다', (tester) async {
    final disruption = ValueNotifier(false);
    addTearDown(disruption.dispose);

    await tester.pumpWidget(
      _host(disruption: disruption, hasNotificationItems: false),
    );

    expect(find.byKey(const Key('newNotificationBar')), findsNothing);
    expect(find.text('새로운 알림이 있어요'), findsNothing);
    // 빈 공간 없이 shrink.
    final shrink = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(NewNotificationBar),
        matching: find.byType(SizedBox),
      ),
    );
    expect(shrink.height, 0);
    expect(shrink.width, 0);
  });

  testWidgets('운행 공지 projection 변경을 즉시 반영한다', (tester) async {
    final disruption = ValueNotifier(false);
    addTearDown(disruption.dispose);
    await tester.pumpWidget(
      _host(disruption: disruption, hasNotificationItems: false),
    );

    expect(find.byKey(const Key('newNotificationBar')), findsNothing);
    disruption.value = true;
    await tester.pump();
    expect(find.byKey(const Key('newNotificationBar')), findsOneWidget);
  });

  testWidgets('바를 한 번 탭하면 onOpenInbox가 정확히 1회만 호출된다 (이중 실행 회귀)', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(hasNotificationItems: true, onOpenInbox: () => calls++),
    );

    await tester.tap(find.byKey(const Key('newNotificationBar')));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('바는 radius 0·margin 0·그림자 없음이고 최소 높이 48이다', (tester) async {
    await tester.pumpWidget(_host(hasNotificationItems: true));

    // margin 0: 바가 화면 전체 너비를 차지한다.
    final barSize = tester.getSize(find.byKey(const Key('newNotificationBar')));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(barSize.width, screenWidth);
    expect(barSize.height, greaterThanOrEqualTo(48));

    // 그림자 없음·radius 0: elevation 0, borderRadius 미지정, 표면색은 토큰.
    final material = tester.widget<Material>(
      find.byKey(const Key('newNotificationBar')),
    );
    expect(material.elevation, 0);
    expect(material.borderRadius, isNull);
    expect(material.color, EasySubwayAccessibleColors.noticeBarSurface);
  });
}
