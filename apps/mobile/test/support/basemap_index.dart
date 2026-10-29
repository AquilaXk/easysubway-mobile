import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

/// 번들 바탕 색인(`line-overlays.json`) 원문. flutter test cwd(apps/mobile) 기준으로 연다.
final String bundledBasemapIndexJson = File(
  kRouteMapLineOverlayIndexAssetPath,
).readAsStringSync();

/// 앱과 같은 권역 집합으로 읽은 번들 바탕 색인.
final RouteMapLineOverlayIndex bundledBasemapIndex =
    RouteMapLineOverlayIndex.parse(bundledBasemapIndexJson);

/// 번들 색인 [variant] 변형에 실린 모든 .vec의 자산 경로 → sha256. 앱은 파일 목록과
/// sha256을 읽지 않으므로 자산 계약 테스트가 색인 원문에서 직접 꺼낸다.
Map<String, String> bundledBasemapIndexFiles(RouteMapBasemapVariant variant) {
  final root = jsonDecode(bundledBasemapIndexJson) as Map<String, dynamic>;
  final regions =
      ((root['variants'] as Map<String, dynamic>)[variant.indexKey]
              as Map<String, dynamic>)['regions']
          as Map<String, dynamic>;
  return {
    for (final region in regions.values.cast<Map<String, dynamic>>()) ...{
      '$kRouteMapBasemapAssetDir/${region['baseVector']}':
          region['baseVectorSha256'] as String,
      for (final line
          in (region['lines'] as Map<String, dynamic>).values
              .cast<Map<String, dynamic>>())
        '$kRouteMapBasemapAssetDir/${line['vector']}': line['sha256'] as String,
    },
  };
}

/// 번들 자산 파일 [key]의 바이트.
ByteData bundledAsset(String key) =>
    ByteData.sublistView(File(key).readAsBytesSync());

/// `flutter/assets` 요청 중 [overrides]에 든 키는 그 함수가, 나머지는 번들 파일이 답한다. 답이
/// null이면 읽기 실패다. 받은 자산 키를 요청 순서대로 모은 목록을 돌려준다.
List<String> serveBasemapAssets([
  Map<String, Future<ByteData?> Function()> overrides = const {},
]) {
  final requests = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) {
        final key = Uri.decodeFull(utf8.decode(message!.buffer.asUint8List()));
        requests.add(key);
        return overrides[key]?.call() ?? Future.value(bundledAsset(key));
      });
  return requests;
}

/// [serveBasemapAssets]를 끝내고 테스트 기본 자산 응답으로 돌아간다.
void stopServingBasemapAssets() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null);
}

/// 번들 파일을 읽어 답하고 요청받은 자산 키를 순서대로 [requests]에 모으는 자산 묶음. 플랫폼
/// 채널을 가로채지 않고 [RouteMapBasemapAssets]의 `bundle`로 넘긴다.
class FakeBasemapBundle extends CachingAssetBundle {
  final List<String> requests = [];

  @override
  Future<ByteData> load(String key) {
    requests.add(key);
    return Future.value(bundledAsset(key));
  }
}

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
/// 않는다.
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

/// 읽는 일이 없는 상태가 이벤트 루프 이만큼의 바퀴 동안 이어져야 조용하다고 본다. 읽기가 끝난
/// 바로 뒤에 오는 늦은 보고나 다시 읽기를 놓치지 않으려는 값이다.
const int _quietTurns = 3;

/// [assets]에 읽는 일이 남지 않고 새로 시작하지도 않는 상태가 [_quietTurns]바퀴 이어질 때까지
/// 기다린다. "정확히 한 번"이나 "일어나지 않음"을 단언하기 전에 쓴다.
Future<void> pumpUntilQuiet(WidgetTester tester, RouteMapBasemapAssets assets) {
  var quietTurns = 0;
  return pumpUntil(
    tester,
    () {
      quietTurns = assets.isLoading ? 0 : quietTurns + 1;
      return quietTurns >= _quietTurns;
    },
    reason: '바탕 자산이 읽는 일을 모두 마치기를 기다렸다',
    observed: () => '읽는 중=${assets.isLoading}',
  );
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
