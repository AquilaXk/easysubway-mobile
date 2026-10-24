import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_min_scale.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// 권역 바탕·노선 강조 레이어·오너 라벨 sidecar는 data 레포 바탕 컴파일러가 굽고 build
// manifest에 sha256을 남긴다. 이 레코드는 그 manifest에서 옮겨 적은 값이라, 자산을
// 다시 가져올 때 data 커밋과 함께 바꾼다.
const _buildRecordPath =
    'test/features/network_map/fixtures/route_map_line_overlays_build_record.json';
const _packPath = 'assets/datapacks/nationwide.sqlite.gz';

String _sha256Of(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

Set<({String region, String lineId})> _datapackRouteMapLines() {
  final workDir = Directory.systemTemp.createTempSync(
    'route-map-overlay-lines-',
  );
  try {
    final pack = File('${workDir.path}/nationwide.sqlite')
      ..writeAsBytesSync(gzip.decode(File(_packPath).readAsBytesSync()));
    final database = sqlite3.open(pack.path, mode: OpenMode.readOnly);
    try {
      return {
        for (final row in database.select(
          'SELECT DISTINCT region, line_id FROM route_map_positions',
        ))
          (region: row['region'] as String, lineId: row['line_id'] as String),
      };
    } finally {
      database.close();
    }
  } finally {
    workDir.deleteSync(recursive: true);
  }
}

void main() {
  final record =
      jsonDecode(File(_buildRecordPath).readAsStringSync())
          as Map<String, dynamic>;
  final pinnedOverlays = (record['overlays'] as Map).cast<String, String>();
  final pinnedBasemaps = (record['basemaps'] as Map).cast<String, String>();

  test('번들 색인은 고정한 data 커밋 manifest의 sha256과 같다', () {
    final indexRecord = record['lineOverlayIndex'] as Map<String, dynamic>;

    expect(
      _sha256Of(kRouteMapLineOverlayIndexAssetPath),
      indexRecord['sha256'],
    );
  });

  test('번들 오너 라벨 sidecar는 고정한 data 커밋 manifest의 sha256과 같다', () {
    final labelsRecord = record['ownerLabels'] as Map<String, dynamic>;

    expect(
      _sha256Of('$kRouteMapBasemapAssetDir/${labelsRecord['file']}'),
      labelsRecord['sha256'],
    );
  });

  test('권역 바탕 .vec는 5권역 전부 manifest sha256과 같다', () {
    expect(
      pinnedBasemaps.keys.toSet(),
      kRouteMapBasemapRegionToId.values.map((id) => '$id.vec').toSet(),
    );
    for (final MapEntry(key: fileName, value: sha256)
        in pinnedBasemaps.entries) {
      expect(
        _sha256Of('$kRouteMapBasemapAssetDir/$fileName'),
        sha256,
        reason: '$fileName sha256',
      );
    }
  });

  test('데이터팩 노선도의 모든 노선이 자기 권역의 강조 레이어를 갖고, 레이어는 manifest sha256과 같다', () {
    final index = RouteMapLineOverlayIndex.parse(
      File(kRouteMapLineOverlayIndexAssetPath).readAsStringSync(),
    );
    final lines = _datapackRouteMapLines();
    final reached = <String>{};

    for (final line in lines) {
      final regionId =
          kRouteMapBasemapRegionToId[routeMapDisplayRegionName(line.region)];
      expect(regionId, isNotNull, reason: '${line.region} 바탕 권역');
      final asset = index.overlayAssetFor(
        regionId: regionId!,
        lineId: line.lineId,
      );
      final fileName = asset.split('/').last;
      expect(
        _sha256Of(asset),
        pinnedOverlays[fileName],
        reason: '$fileName sha256',
      );
      reached.add(fileName);
    }

    expect(lines, hasLength(36));
    expect(reached, pinnedOverlays.keys.toSet());
  });
}
