import 'dart:async';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/notice_controller.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/service_notice_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceNotice _notice(
  String id, {
  NoticeSeverity severity = NoticeSeverity.disruption,
  String? title,
}) {
  return ServiceNotice(
    id: id,
    scope: NoticeScope.all,
    title: title ?? '제목 $id',
    body: '본문 $id',
    severity: severity,
    publishedAt: DateTime(2026, 7, 6, 9, 0, 0),
  );
}

class _FakeRepository implements NoticeRepository {
  _FakeRepository(this.result);
  final ActiveNoticesResult result;
  int calls = 0;
  @override
  Future<ActiveNoticesResult> activeNotices() async {
    calls++;
    return result;
  }
}

class _DeferredRepository implements NoticeRepository {
  _DeferredRepository(this.completer);

  final Completer<ActiveNoticesResult> completer;
  int calls = 0;

  @override
  Future<ActiveNoticesResult> activeNotices() {
    calls++;
    return completer.future;
  }
}

Future<NoticeController> _seed(ActiveNoticesResult result) async {
  final controller = NoticeController(repository: _FakeRepository(result));
  await controller.refresh();
  return controller;
}

Widget _host(NoticeController controller) {
  return MaterialApp(
    home: ServiceNoticeListScreen(
      controller: controller,
      now: () => DateTime(2026, 7, 6, 12, 0, 0),
    ),
  );
}

void main() {
  testWidgets('제목·본문·심각도를 목록으로 노출한다', (tester) async {
    final controller = await _seed(
      ActiveNoticesResult(
        notices: [
          _notice('n1', title: '2호선 지연'),
          _notice('i1', severity: NoticeSeverity.info, title: '역사 안내'),
        ],
        stale: false,
      ),
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('공지사항'), findsOneWidget);
    expect(find.text('운행 공지'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('serviceNoticeAppBar'))).height,
      60,
    );
    expect(
      tester
          .widget<AppBar>(find.byKey(const Key('serviceNoticeAppBar')))
          .backgroundColor,
      EasySubwayAccessibleColors.topBarSurface,
    );

    final divider = tester.widget<SizedBox>(
      find.byKey(const Key('serviceNoticeHeaderDivider')),
    );
    final decoration =
        (divider.child! as DecoratedBox).decoration as BoxDecoration;
    expect(decoration.color, easySubwayHeaderDividerColor);
    // 설정·공지 등 일반 네비는 선만(그림자 없음). 노선도·메뉴만 mapChrome.
    expect(decoration.boxShadow, isNull);
    expect(find.text('2호선 지연'), findsOneWidget);
    expect(find.text('역사 안내'), findsOneWidget);
  });

  testWidgets('공지가 없으면 빈 상태 안내를 노출한다', (tester) async {
    final controller = await _seed(
      const ActiveNoticesResult(notices: [], stale: false),
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('지금은 공지사항이 없어요'), findsOneWidget);
    expect(find.text('지금은 운행 공지가 없어요'), findsNothing);
    expect(find.text('운행 장애나 안내가 생기면 여기에 표시돼요'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
    final imageFinder = find.byKey(const Key('serviceNoticeEmptyImage'));
    expect(tester.getSize(imageFinder), const Size.square(80));
    final image = tester.widget<Image>(imageFinder);
    expect(
      (image.image as AssetImage).assetName,
      'assets/illustrations/empty_notices.png',
    );
    expect(image.color, EasySubwayAccessibleColors.brandSignature);
    expect(image.colorBlendMode, BlendMode.srcIn);
    expect(image.excludeFromSemantics, isTrue);
    final emptyText = tester.widget<Text>(find.text('지금은 공지사항이 없어요'));
    expect(emptyText.style?.fontSize, 22);
    final content = tester.widget<Align>(
      find.byKey(const Key('serviceNoticeEmptyContent')),
    );
    expect(content.alignment, const Alignment(0, -0.28));
    final fill = tester.widget<SliverFillRemaining>(
      find.byKey(const Key('serviceNoticeEmptyFill')),
    );
    expect(fill.hasScrollBody, isFalse);
  });

  testWidgets('unavailable은 빈 상태 대신 다시 시도 카드로 노출한다', (tester) async {
    final repository = _FakeRepository(const ActiveNoticesResult.unavailable());
    final controller = NoticeController(repository: repository);
    await controller.refresh();

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('serviceNoticeUnavailableState')),
      findsOneWidget,
    );
    expect(find.text('공지사항을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('지금은 공지사항이 없어요'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('다시 시도')),
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
  });

  testWidgets('첫 요청 loading 중에는 빈 상태 문구를 보이지 않는다', (tester) async {
    final completer = Completer<ActiveNoticesResult>();
    final controller = NoticeController(
      repository: _DeferredRepository(completer),
    );

    await tester.pumpWidget(_host(controller));
    final refresh = controller.refresh();
    await tester.pump();

    expect(find.byKey(const Key('serviceNoticeLoadingState')), findsOneWidget);
    expect(find.text('지금은 공지사항이 없어요'), findsNothing);

    completer.complete(const ActiveNoticesResult.unavailable());
    await refresh;
  });

  testWidgets('오프라인(stale)이면 "N시간 전 기준" 라벨을 노출한다', (tester) async {
    final controller = await _seed(
      ActiveNoticesResult(
        notices: [_notice('n1')],
        stale: true,
        asOf: DateTime(2026, 7, 6, 9, 0, 0),
      ),
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('3시간 전 기준'), findsOneWidget);
  });
}
