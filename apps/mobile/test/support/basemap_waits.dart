import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

/// 바탕 뷰가 지금 그리는 그림. 노선을 골랐고 레이어가 준비됐으면 흐린 바탕, 노선 레이어
/// 순이다. 아직 읽지 못한 층은 null이다.
List<ui.Picture?> paintedBasemapPictures(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(RouteMapBasemapView),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<RouteMapBasemapPainter>()
    .map((painter) => painter.picture)
    .toList();

/// 바탕 뷰가 [count]장의 그림을 모두 그릴 때까지 기다린다. 뷰 하나는 바탕 1장이고, 노선을
/// 골랐으면 흐린 바탕과 노선 레이어 2장이다. 출처 표기만 그리는 painter는 그림이 없어 세지
/// 않는다. 벡터로 그리는 단계에서만 쓴다. 바탕 타일 격자가 서면 벡터 그림이 사라져 그림 수가
/// 0이 되므로, 격자가 선 뒤에는 이 도우미로 기다릴 수 없다.
Future<void> pumpUntilBasemapPainted(WidgetTester tester, {int count = 1}) {
  int painted() =>
      paintedBasemapPictures(tester).whereType<ui.Picture>().length;
  return pumpUntil(
    tester,
    () => painted() == count,
    reason: '바탕 그림 $count장을 그리는 일이 끝나기를 기다렸다',
    observed: () => '그린 그림 ${painted()}장',
  );
}

/// 읽는 일이 없는 상태를 이벤트 루프 이만큼의 바퀴 동안 더 지켜본다. 읽기가 끝난 바로
/// 뒤에 오는 늦은 보고나 다시 읽기를 놓치지 않으려는 값이다.
const int _quietTurns = 3;

/// [assets]에 끝나지 않은 읽기가 없어질 때까지 기다린 뒤, 이벤트 루프를 [_quietTurns]바퀴
/// 더 돌려 읽기가 다시 시작하지 않는지 지켜본다. 다시 시작하면 실패한다. "정확히 한 번"이나
/// "일어나지 않음"을 단언하기 전에 쓴다.
Future<void> pumpUntilQuiet(
  WidgetTester tester,
  RouteMapBasemapAssets assets,
) async {
  await pumpUntil(
    tester,
    () => !assets.hasPendingReads,
    reason: '바탕 자산이 읽는 일을 모두 마치기를 기다렸다',
    observed: () => '끝나지 않은 읽기=${assets.hasPendingReads}',
  );
  for (var turn = 1; turn <= _quietTurns; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    if (assets.hasPendingReads) {
      fail('조용해진 바탕 자산이 $turn번째 바퀴에 읽기를 다시 시작했습니다.');
    }
  }
}

/// [isExpected]인 Flutter 오류가 [errors]에 쌓이고 [assets]가 조용해질 때까지 기다린다. 첫
/// 보고에서 멈추지 않고 조용해질 때까지 기다리므로, 이어 오는 같은 보고와 다른 읽기의
/// 결과를 단언 전에 모두 본다.
Future<void> pumpUntilReported(
  WidgetTester tester,
  RouteMapBasemapAssets assets,
  List<FlutterErrorDetails> errors, {
  required bool Function(FlutterErrorDetails error) isExpected,
}) async {
  await pumpUntil(
    tester,
    () => errors.any(isExpected),
    reason: '기대한 오류를 보고하는 일이 끝나기를 기다렸다',
    observed: () => '보고된 오류 ${errors.map((e) => e.context).toList()}',
  );
  await pumpUntilQuiet(tester, assets);
}
