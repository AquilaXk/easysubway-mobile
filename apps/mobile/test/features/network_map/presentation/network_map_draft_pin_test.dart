import 'dart:io';

import 'package:easysubway_mobile/design_tokens.dart';
import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_draft_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _station = NetworkMapStation(
  id: 'station-seoul',
  nameKo: '서울',
  nameEn: 'Seoul',
  region: 'capital',
  lineId: 'line-1',
  stationCode: '133',
  sequence: 1,
  position: NetworkMapPosition(
    x: 50,
    y: 50,
    labelDx: 0,
    labelDy: 0,
    upPath: '',
    downPath: '',
    sourceId: 'seoul',
  ),
);

const _centeredCamera = MapCameraState(
  sourceBounds: Rect.fromLTWH(0, 0, 100, 100),
  viewportSize: Size(200, 200),
  center: Offset(50, 50),
  scale: 2,
  minScale: 1,
  maxScale: 4,
  revision: 0,
);

Future<void> _pumpPin(
  WidgetTester tester, {
  MapCameraState camera = _centeredCamera,
  Offset anchorSource = const Offset(50, 40),
  bool ignorePointers = false,
  required VoidCallback onClear,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: camera.viewportSize.width,
            height: camera.viewportSize.height,
            child: Stack(
              children: [
                NetworkMapDraftPin(
                  key: const Key('draftPin'),
                  station: _station,
                  anchorSource: anchorSource,
                  camera: camera,
                  label: '출발',
                  surfaceColor: EasySubwayFanMenuColors.departure,
                  semanticSuffix: '출발 지정됨',
                  clearButtonKey: const Key('draftPinClear'),
                  ignorePointers: ignorePointers,
                  onClear: onClear,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Positioned _outerPositioned(WidgetTester tester) => tester
    .widgetList<Positioned>(
      find.descendant(
        of: find.byType(NetworkMapDraftPin),
        matching: find.byType(Positioned),
      ),
    )
    .first;

void main() {
  testWidgets('핀 끝을 camera anchor에 맞추고 exact asset layer를 보존한다', (
    tester,
  ) async {
    await _pumpPin(tester, onClear: () {});

    final positioned = _outerPositioned(tester);
    expect(positioned.left, 66);
    expect(positioned.top, 18);
    expect(positioned.width, 78);
    expect(positioned.height, 62);

    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as AssetImage).assetName);
    expect(assetNames, everyElement('assets/illustrations/map_draft_pin.png'));
    expect(assetNames, hasLength(3));
  });

  testWidgets('viewport edge에서 hit bounds를 4dp 안쪽으로 clamp한다', (tester) async {
    const edgeCamera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 100, 100),
      viewportSize: Size(120, 120),
      center: Offset(50, 50),
      scale: 1,
      minScale: 1,
      maxScale: 4,
      revision: 0,
    );
    await _pumpPin(
      tester,
      camera: edgeCamera,
      anchorSource: const Offset(0, 50),
      onClear: () {},
    );

    final positioned = _outerPositioned(tester);
    expect(positioned.left, 4);
    expect(positioned.top, 4);
  });

  testWidgets('station·role Semantics와 56dp clear callback을 보존한다', (
    tester,
  ) async {
    var clearCount = 0;
    final semantics = tester.ensureSemantics();
    await _pumpPin(tester, onClear: () => clearCount += 1);

    expect(find.bySemanticsLabel('서울역, 출발 지정됨'), findsOneWidget);
    expect(find.bySemanticsLabel('출발 지우기'), findsOneWidget);
    final clear = find.byKey(const Key('draftPinClear'));
    expect(tester.getSize(clear), const Size.square(56));

    await tester.tap(clear);
    expect(clearCount, 1);
    semantics.dispose();
  });

  testWidgets('gesture 중에는 핀 pointer를 통과시킨다', (tester) async {
    var clearCount = 0;
    await _pumpPin(
      tester,
      ignorePointers: true,
      onClear: () => clearCount += 1,
    );

    final ignorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(NetworkMapDraftPin),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointer.ignoring, isTrue);
    await tester.tap(
      find.byKey(const Key('draftPinClear')),
      warnIfMissed: false,
    );
    expect(clearCount, 0);
  });

  test('root는 public pin owner만 세 번 조합한다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    final owner = File(
      'lib/features/network_map/presentation/network_map_draft_pin.dart',
    ).readAsStringSync();

    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_draft_pin.dart';",
      ),
    );
    expect('NetworkMapDraftPin('.allMatches(root), hasLength(3));
    expect(root, isNot(contains('_NetworkMapDraftPin')));
    expect(root, isNot(contains("import 'dart:ui' show ImageFilter;")));
    expect(owner, contains('class NetworkMapDraftPin extends StatelessWidget'));
    expect(owner, isNot(contains("import '../../../network_map.dart';")));
  });
}
