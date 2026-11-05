import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRouteMapOwnerLabelsForRegion', () {
    const sidecar = '''
    {
      "schemaVersion": 1,
      "artifactKind": "route-map-basemap-owner-labels",
      "regions": {
        "seoul": [
          {"station": "시청", "role": "transfer", "x": 1069.29, "y": 817.38, "anchor": "start", "fontSizePx": 13.0},
          {"station": "가야", "role": "ordinary", "x": 100.0, "y": 200.0, "anchor": "middle", "fontSizePx": 12.5}
        ],
        "busan": [
          {"station": "가야", "role": "terminal", "x": 300.0, "y": 400.0, "anchor": "end", "fontSizePx": 13.0}
        ]
      }
    }
    ''';

    test('region별 station명 키 맵으로 파싱한다', () {
      final seoul = parseRouteMapOwnerLabelsForRegion(sidecar, 'seoul');
      expect(seoul.length, 2);
      expect(seoul['시청']!.single.role, 'transfer');
      expect(seoul['시청']!.single.position, const Offset(1069.29, 817.38));
      expect(seoul['시청']!.single.anchor, RouteMapOwnerLabelAnchor.start);
      expect(seoul['가야']!.single.anchor, RouteMapOwnerLabelAnchor.middle);
      expect(seoul['가야']!.single.fontSizePx, 12.5);
    });

    test('다른 region은 섞이지 않는다', () {
      final busan = parseRouteMapOwnerLabelsForRegion(sidecar, 'busan');
      expect(busan.length, 1);
      expect(busan['가야']!.single.role, 'terminal');
      expect(busan['가야']!.single.anchor, RouteMapOwnerLabelAnchor.end);
    });

    test('없는 region 키는 빈 맵을 반환하고 잘못된 JSON·스키마는 FormatException을 던진다', () {
      expect(parseRouteMapOwnerLabelsForRegion(sidecar, 'gwangju'), isEmpty);
      expect(
        () => parseRouteMapOwnerLabelsForRegion('not json', 'seoul'),
        throwsFormatException,
      );
      expect(
        () => parseRouteMapOwnerLabelsForRegion('[]', 'seoul'),
        throwsFormatException,
      );
      expect(
        () => parseRouteMapOwnerLabelsForRegion('{}', 'seoul'),
        throwsFormatException,
      );
      expect(
        () => parseRouteMapOwnerLabelsForRegion(
          '{"regions": {"seoul": "not-a-list"}}',
          'seoul',
        ),
        throwsFormatException,
      );
    });

    test('동명이역(같은 이름)은 위치로 구분해 모두 리스트로 보존한다(#2068 busan 좌천·동래 소실 회귀)', () {
      const dup = '''
      {
        "regions": {
          "busan": [
            {"station": "좌천", "role": "ordinary", "x": 4765.675, "y": 2108.1, "anchor": "start", "fontSizePx": 12.0},
            {"station": "좌천", "role": "ordinary", "x": 7538.725, "y": 1733.7, "anchor": "start", "fontSizePx": 12.0}
          ]
        }
      }
      ''';
      final result = parseRouteMapOwnerLabelsForRegion(dup, 'busan');
      expect(result.length, 1);
      final jwacheon = result['좌천']!;
      expect(jwacheon.length, 2, reason: '두 좌천 라벨이 모두 보존돼야 한다');
      expect(jwacheon[0].position, const Offset(4765.675, 2108.1));
      expect(jwacheon[1].position, const Offset(7538.725, 1733.7));
    });

    test('필드 누락 또는 비정상 항목은 FormatException을 던진다', () {
      const nonMapEntry = '{"regions": {"seoul": [123]}}';
      const missingCoordinate = '''
      {
        "regions": {
          "seoul": [
            {"station": "누락역", "role": "ordinary", "anchor": "start", "fontSizePx": 12.0}
          ]
        }
      }
      ''';
      const blankStation = '''
      {
        "regions": {
          "seoul": [
            {"station": "   ", "role": "ordinary", "x": 5.0, "y": 5.0, "anchor": "start", "fontSizePx": 12.0}
          ]
        }
      }
      ''';
      expect(
        () => parseRouteMapOwnerLabelsForRegion(nonMapEntry, 'seoul'),
        throwsFormatException,
      );
      expect(
        () => parseRouteMapOwnerLabelsForRegion(missingCoordinate, 'seoul'),
        throwsFormatException,
      );
      expect(
        () => parseRouteMapOwnerLabelsForRegion(blankStation, 'seoul'),
        throwsFormatException,
      );
    });

    test('lines 필드가 없으면 빈 리스트를 반환한다', () {
      final seoul = parseRouteMapOwnerLabelsForRegion(sidecar, 'seoul');
      expect(seoul['시청']!.single.lines, isEmpty);
    });

    test('#2068 다줄 라벨 렌더: lines가 있으면 텍스트·좌표를 순서대로 파싱한다', () {
      const sidecar = '''
      {
        "regions": {
          "seoul": [
            {"station": "검단사거리", "role": "ordinary", "x": 541.0, "y": 1253.4,
             "anchor": "start", "fontSizePx": 26.374,
             "lines": [
               {"text": "검단", "x": 541.0, "y": 1253.4},
               {"text": "사거리", "x": 530.0, "y": 1282.2}
             ]}
          ]
        }
      }
      ''';
      final result = parseRouteMapOwnerLabelsForRegion(sidecar, 'seoul');
      final entry = result['검단사거리']!.single;
      expect(entry.lines.length, 2);
      expect(entry.lines[0].text, '검단');
      expect(entry.lines[0].position, const Offset(541.0, 1253.4));
      expect(entry.lines[1].text, '사거리');
      expect(entry.lines[1].position, const Offset(530.0, 1282.2));
    });

    test(
      '#2068 다줄 라벨 렌더: lines가 배열이 아니거나 항목 필드가 누락되면 FormatException을 던진다',
      () {
        const nonListLines = '''
      {
        "regions": {
          "seoul": [
            {"station": "테스트역", "role": "ordinary", "x": 1.0, "y": 1.0,
             "anchor": "start", "fontSizePx": 12.0,
             "lines": "not-a-list"}
          ]
        }
      }
      ''';
        const malformedLineEntry = '''
      {
        "regions": {
          "seoul": [
            {"station": "테스트역", "role": "ordinary", "x": 1.0, "y": 1.0,
             "anchor": "start", "fontSizePx": 12.0,
             "lines": [
               {"text": "정상줄", "x": 1.0, "y": 1.0},
               {"text": "  ", "x": 2.0, "y": 2.0}
             ]}
          ]
        }
      }
      ''';
        const nonMapLineEntry = '''
      {
        "regions": {
          "seoul": [
            {"station": "테스트역", "role": "ordinary", "x": 1.0, "y": 1.0,
             "anchor": "start", "fontSizePx": 12.0,
             "lines": [123]}
          ]
        }
      }
      ''';
        expect(
          () => parseRouteMapOwnerLabelsForRegion(nonListLines, 'seoul'),
          throwsFormatException,
        );
        expect(
          () => parseRouteMapOwnerLabelsForRegion(nonMapLineEntry, 'seoul'),
          throwsFormatException,
        );
        expect(
          () => parseRouteMapOwnerLabelsForRegion(malformedLineEntry, 'seoul'),
          throwsFormatException,
        );
      },
    );

    test('#2068 광주 2차: hasLineTerminalBadge 플래그를 파싱하고 미보유 시 false', () {
      const sidecar = '''
      {
        "regions": {
          "gwangju": [
            {"station": "평동", "role": "terminal", "x": 1.0, "y": 1.0, "anchor": "start", "fontSizePx": 78.0, "hasLineTerminalBadge": true},
            {"station": "도산", "role": "ordinary", "x": 2.0, "y": 2.0, "anchor": "start", "fontSizePx": 72.0}
          ]
        }
      }
      ''';
      final result = parseRouteMapOwnerLabelsForRegion(sidecar, 'gwangju');
      expect(result['평동']!.single.hasLineTerminalBadge, isTrue);
      expect(result['도산']!.single.hasLineTerminalBadge, isFalse);
    });
  });

  group('routeMapOwnerLabelsByRegionFrom', () {
    test('전 region을 한 번에 파싱한다', () {
      const sidecar = '''
      {
        "regions": {
          "seoul": [{"station": "시청", "role": "transfer", "x": 1.0, "y": 2.0, "anchor": "start", "fontSizePx": 13.0}],
          "busan": []
        }
      }
      ''';
      final byRegion = routeMapOwnerLabelsByRegionFrom(sidecar);
      expect(byRegion.keys.toSet(), {'seoul', 'busan'});
      expect(byRegion['seoul']!['시청']!.single.role, 'transfer');
      expect(byRegion['busan'], isEmpty);
    });

    test('잘못된 JSON·스키마는 FormatException을 던진다', () {
      expect(
        () => routeMapOwnerLabelsByRegionFrom('not json'),
        throwsFormatException,
      );
      expect(
        () => routeMapOwnerLabelsByRegionFrom('{}'),
        throwsFormatException,
      );
      expect(
        () => routeMapOwnerLabelsByRegionFrom('{"regions": {"seoul": 123}}'),
        throwsFormatException,
      );
    });
  });
}
