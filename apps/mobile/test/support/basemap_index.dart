import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

const int _settleRounds = 10;
const Duration _settleRoundDelay = Duration(milliseconds: 10);

/// 바탕 색인과 .vec 디코드가 실제 시간으로 끝나도록 기다리며 프레임을 돌린다. 디코드는 부하에
/// 따라 시간이 달라 한 번에 0초만 기다리면 끝나기 전에 단언이 돈다. 시계는 앞으로 돌리지
/// 않아 카메라가 멈춘 뒤 굽는 타일은 만들지 않는다.
Future<void> settleBasemapLoads(WidgetTester tester) async {
  for (var round = 0; round < _settleRounds; round++) {
    await tester.runAsync(() => Future<void>.delayed(_settleRoundDelay));
    await tester.pump();
  }
}
