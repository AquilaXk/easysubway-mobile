import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_min_scale.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/basemap_index.dart';

// 권역 바탕·노선 강조 레이어·오너 라벨 sidecar는 data 레포 바탕 컴파일러가 변형(윤곽선·
// 텍스트)마다 굽고 build manifest에 sha256을 남긴다. 이 레코드는 그 manifest에서 옮겨 적은
// 값이라, 자산을 다시 가져올 때 data 커밋과 함께 바꾼다.
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

  late final lines = _datapackRouteMapLines();

  for (final variant in RouteMapBasemapVariant.values) {
    final files = bundledBasemapIndex.variant(variant);
    final pinned =
        (record['variants'] as Map<String, dynamic>)[variant.indexKey]
            as Map<String, dynamic>;
    final pinnedFiles = <String, String>{
      ...(pinned['basemaps'] as Map).cast<String, String>(),
      ...(pinned['overlays'] as Map).cast<String, String>(),
    };

    test(
      '${variant.indexKey}: 색인에 실린 파일은 번들 바이트, 색인, manifest의 sha256이 모두 같다',
      () {
        final listed = <String>{};
        for (final MapEntry(key: asset, value: sha256)
            in bundledBasemapIndexFiles(variant).entries) {
          final fileName = asset.split('/').last;
          listed.add(fileName);
          expect(_sha256Of(asset), sha256, reason: '$fileName 번들 바이트');
          expect(pinnedFiles[fileName], sha256, reason: '$fileName manifest');
        }
        expect(listed, pinnedFiles.keys.toSet());
      },
    );

    test('${variant.indexKey}: 바탕이 있는 5권역이 모두 색인 바탕을 갖는다', () {
      for (final regionId in kRouteMapBasemapRegionToId.values) {
        final fileName = files.baseAssetFor(regionId).split('/').last;
        expect(
          (pinned['basemaps'] as Map).containsKey(fileName),
          isTrue,
          reason: '$regionId 바탕 $fileName',
        );
      }
    });

    test('${variant.indexKey}: 데이터팩 노선도의 모든 노선이 자기 권역의 강조 레이어를 갖는다', () {
      final reached = <String>{};
      for (final line in lines) {
        final regionId =
            kRouteMapBasemapRegionToId[routeMapDisplayRegionName(line.region)];
        expect(regionId, isNotNull, reason: '${line.region} 바탕 권역');
        reached.add(
          files
              .overlayAssetFor(regionId: regionId!, lineId: line.lineId)
              .split('/')
              .last,
        );
      }

      expect(lines, hasLength(36));
      expect(reached, (pinned['overlays'] as Map).keys.toSet());
    });
  }
}
