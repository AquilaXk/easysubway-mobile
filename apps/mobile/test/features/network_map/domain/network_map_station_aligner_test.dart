import 'package:flutter_test/flutter_test.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_aligner.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_nodes.dart';

void main() {
  group('network_map_station_aligner', () {
    test('normalizeStationNameForBasemap removes parenthesized subtitles', () {
      expect(normalizeStationNameForBasemap('석남(거북시장)'), '석남');
      expect(normalizeStationNameForBasemap('온양온천(순천향대)'), '온양온천');
      expect(normalizeStationNameForBasemap('서해구청'), '서구청');
      expect(normalizeStationNameForBasemap('강남'), '강남');
    });

    test('matchBestOwnerEntry disambiguates duplicate stations', () {
      final sinchon2 = const NetworkMapStation(
        id: 'station-sinchon-2',
        nameKo: '신촌',
        nameEn: 'Sinchon',
        region: '수도권',
        lineId: 'line-2',
        stationCode: '240',
        sequence: 1,
        position: NetworkMapPosition(
          x: 45000,
          y: 60000,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'seoul-metro-route-map-positions',
        ),
      );
      final sinchonGyeongui = const NetworkMapStation(
        id: 'station-sinchon-k',
        nameKo: '신촌',
        nameEn: 'Sinchon',
        region: '수도권',
        lineId: 'line-gyeongui-jungang',
        stationCode: 'K110',
        sequence: 1,
        position: NetworkMapPosition(
          x: 45000,
          y: 60000,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'seoul-metro-route-map-positions',
        ),
      );
      final entries = [
        const RouteMapOwnerLabelEntry(
          station: '신촌',
          role: 'ordinary',
          position: Offset(1342.5, 1218.3),
          anchor: RouteMapOwnerLabelAnchor.start,
          fontSizePx: 15.47,
          lines: [],
        ),
        const RouteMapOwnerLabelEntry(
          station: '신촌',
          role: 'ordinary',
          position: Offset(1398.7, 1123.8),
          anchor: RouteMapOwnerLabelAnchor.middle,
          fontSizePx: 15.47,
          lines: [
            RouteMapOwnerLabelLine(
              text: '신촌',
              position: Offset(1398.7, 1123.8),
            ),
            RouteMapOwnerLabelLine(
              text: '(경의중앙선)',
              position: Offset(1398.7, 1139.3),
            ),
          ],
        ),
      ];

      final matched2 = matchBestOwnerEntry(sinchon2, entries);
      expect(matched2.position.dx, closeTo(1342.5, 0.1));

      final matchedK = matchBestOwnerEntry(sinchonGyeongui, entries);
      expect(matchedK.position.dx, closeTo(1398.7, 0.1));

      // 양평: 5호선(y > 1000) vs 경의중앙선(y < 1000)
      final yangpyeong5 = const NetworkMapStation(
        id: 'station-yangpyeong-5',
        nameKo: '양평',
        nameEn: 'Yangpyeong',
        region: '수도권',
        lineId: 'line-5',
        stationCode: '525',
        sequence: 1,
        position: NetworkMapPosition(
          x: 40000,
          y: 40000,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'seoul-metro-route-map-positions',
        ),
      );
      final yangpyeongK = const NetworkMapStation(
        id: 'station-yangpyeong-k',
        nameKo: '양평',
        nameEn: 'Yangpyeong',
        region: '수도권',
        lineId: 'line-gyeongui-jungang',
        stationCode: 'K135',
        sequence: 1,
        position: NetworkMapPosition(
          x: 40000,
          y: 40000,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'seoul-metro-route-map-positions',
        ),
      );
      final yangpyeongEntries = [
        const RouteMapOwnerLabelEntry(
          station: '양평',
          role: 'ordinary',
          position: Offset(1207.7, 1586.2), // 5호선 (도심, y > 1000)
          anchor: RouteMapOwnerLabelAnchor.start,
          fontSizePx: 15.47,
        ),
        const RouteMapOwnerLabelEntry(
          station: '양평',
          role: 'ordinary',
          position: Offset(3337.5, 409.5), // 경의중앙선 (양평군, y < 1000)
          anchor: RouteMapOwnerLabelAnchor.middle,
          fontSizePx: 15.47,
        ),
      ];

      final matchedYangpyeong5 = matchBestOwnerEntry(
        yangpyeong5,
        yangpyeongEntries,
      );
      expect(matchedYangpyeong5.position.dy, closeTo(1586.2, 0.1));

      final matchedYangpyeongK = matchBestOwnerEntry(
        yangpyeongK,
        yangpyeongEntries,
      );
      expect(matchedYangpyeongK.position.dy, closeTo(409.5, 0.1));

      // 카탈로그 lineId(line-6e39be0cb6e2)로도 경의중앙선 정상 매칭 확인
      final matchedYangpyeongKCatalog = matchBestOwnerEntry(
        yangpyeongK.copyWith(lineId: 'line-6e39be0cb6e2'),
        yangpyeongEntries,
      );
      expect(matchedYangpyeongKCatalog.position.dy, closeTo(409.5, 0.1));

      final matchedSinchonKCatalog = matchBestOwnerEntry(
        sinchonGyeongui.copyWith(lineId: 'line-6e39be0cb6e2'),
        entries,
      );
      expect(matchedSinchonKCatalog.position.dx, closeTo(1398.7, 0.1));

      // 신촌/양평 외의 다중 엔트리인 경우 첫 번째 엔트리로 fallback
      final genericStation = const NetworkMapStation(
        id: 'station-generic',
        nameKo: '일반역',
        nameEn: 'Generic',
        region: '수도권',
        lineId: 'line-1',
        stationCode: '100',
        sequence: 1,
        position: NetworkMapPosition(
          x: 100,
          y: 200,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'src',
        ),
      );
      final genericEntries = [
        const RouteMapOwnerLabelEntry(
          station: '일반역',
          role: 'ordinary',
          position: Offset(100.0, 200.0),
          anchor: RouteMapOwnerLabelAnchor.middle,
          fontSizePx: 15.47,
        ),
        const RouteMapOwnerLabelEntry(
          station: '일반역',
          role: 'ordinary',
          position: Offset(300.0, 400.0),
          anchor: RouteMapOwnerLabelAnchor.middle,
          fontSizePx: 15.47,
        ),
      ];
      final matchedGeneric = matchBestOwnerEntry(
        genericStation,
        genericEntries,
      );
      expect(matchedGeneric.position.dx, 100.0);

      // 단일 엔트리는 바로 반환
      expect(
        matchBestOwnerEntry(genericStation, [genericEntries.first]).position.dx,
        100.0,
      );

      // 빈 entries 리스트 방어
      expect(
        () => matchBestOwnerEntry(yangpyeong5, const []),
        throwsArgumentError,
      );
    });

    test('RouteMapOwnerNodeEntry and matchBestNodeEntry work correctly', () {
      final nodeEntry = const RouteMapOwnerNodeEntry(
        stationId: 's1',
        lineId: 'l1',
        name: '역',
        x: 100,
        y: 200,
      );
      expect(nodeEntry.position, const Offset(100, 200));

      // 빈 리스트 예외 방어
      final dummyStation = const NetworkMapStation(
        id: 's',
        nameKo: '신촌',
        nameEn: 'Sinchon',
        region: '수도권',
        lineId: 'line-2',
        stationCode: '240',
        sequence: 1,
        position: NetworkMapPosition(
          x: 0,
          y: 0,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: '',
        ),
      );
      expect(
        () => matchBestNodeEntry(dummyStation, const []),
        throwsArgumentError,
      );

      // 단일 엔트리 바로 반환
      expect(matchBestNodeEntry(dummyStation, [nodeEntry]), nodeEntry);

      // RouteMapOwnerNodeEntry equality, hashCode, toString
      final nodeEntryClone = const RouteMapOwnerNodeEntry(
        stationId: 's1',
        lineId: 'l1',
        name: '역',
        x: 100,
        y: 200,
      );
      final nodeEntryDiff = const RouteMapOwnerNodeEntry(
        stationId: 'station-2',
        lineId: 'line-2',
        name: '서울역',
        x: 100,
        y: 200,
      );
      expect(nodeEntry == nodeEntryClone, isTrue);
      expect(nodeEntry == nodeEntryDiff, isFalse);
      expect(
        nodeEntry ==
            const RouteMapOwnerNodeEntry(
              stationId: 's1',
              lineId: 'l2',
              name: '역',
              x: 100,
              y: 200,
            ),
        isFalse,
      );
      expect(
        nodeEntry ==
            const RouteMapOwnerNodeEntry(
              stationId: 's1',
              lineId: 'l1',
              name: '다른역',
              x: 100,
              y: 200,
            ),
        isFalse,
      );
      expect(
        nodeEntry ==
            const RouteMapOwnerNodeEntry(
              stationId: 's1',
              lineId: 'l1',
              name: '역',
              x: 999,
              y: 200,
            ),
        isFalse,
      );
      expect(
        nodeEntry ==
            const RouteMapOwnerNodeEntry(
              stationId: 's1',
              lineId: 'l1',
              name: '역',
              x: 100,
              y: 999,
            ),
        isFalse,
      );
      expect(nodeEntry.hashCode, nodeEntryClone.hashCode);
      expect(nodeEntry.toString(), contains('역'));

      // 라인 식별 헬퍼 테스트
      expect(isGyeonguiLineId('line-6e39be0cb6e2'), isTrue);
      expect(isGyeonguiLineId('line-gyeongui-jungang'), isTrue);
      expect(isGyeonguiLineId('경의중앙선'), isTrue);
      expect(isGyeonguiLineId('seoul-2'), isFalse);

      expect(isLine2('seoul-2'), isTrue);
      expect(isLine2('line-2'), isTrue);
      expect(isLine2('2호선'), isTrue);
      expect(isLine2('line-5'), isFalse);

      expect(isLine5('line-80fc4d5350d4'), isTrue);
      expect(isLine5('line-5'), isTrue);
      expect(isLine5('5호선'), isTrue);
      expect(isLine5('seoul-2'), isFalse);

      expect(isDonghaeLineId('line-f52eb59d8497'), isTrue);
      expect(isDonghaeLineId('donghae'), isTrue);
      expect(isDonghaeLineId('동해선'), isTrue);
      expect(isDonghaeLineId('busan-1'), isFalse);

      expect(isBusanLine1('line-ab1a041f6266'), isTrue);
      expect(isBusanLine1('busan-1'), isTrue);
      expect(isBusanLine1('1호선'), isTrue);
      expect(isBusanLine1('donghae'), isFalse);

      // 신촌 2호선 vs 경의선 분기 (실제 nodes.json 순서: 경의선이 먼저인 경우와 2호선이 먼저인 경우 모두 검증)
      final sinchon2Node = const RouteMapOwnerNodeEntry(
        stationId: 'station-4e123a19a88f',
        lineId: 'seoul-2',
        name: '신촌',
        x: 1369,
        y: 1227,
      );
      final sinchonKNode = const RouteMapOwnerNodeEntry(
        stationId: 'station-d6935359840d',
        lineId: 'line-6e39be0cb6e2',
        name: '신촌',
        x: 1398,
        y: 1148,
      );
      // nodes.json 실측 순서(경의선이 먼저)
      final sinchonListKFirst = [sinchonKNode, sinchon2Node];
      final sinchonList2First = [sinchon2Node, sinchonKNode];

      for (final list in [sinchonListKFirst, sinchonList2First]) {
        // 정확한 카탈로그 lineId 매칭
        expect(
          matchBestNodeEntry(
            dummyStation.copyWith(nameKo: '신촌', lineId: 'seoul-2'),
            list,
          ),
          sinchon2Node,
        );
        expect(
          matchBestNodeEntry(
            dummyStation.copyWith(nameKo: '신촌', lineId: 'line-6e39be0cb6e2'),
            list,
          ),
          sinchonKNode,
        );
        // 친화 라인 식별자 매칭
        expect(
          matchBestNodeEntry(
            dummyStation.copyWith(nameKo: '신촌', lineId: 'line-2'),
            list,
          ),
          sinchon2Node,
        );
        expect(
          matchBestNodeEntry(
            dummyStation.copyWith(
              nameKo: '신촌',
              lineId: 'line-gyeongui-jungang',
            ),
            list,
          ),
          sinchonKNode,
        );
      }

      // 신촌: lineId 없을 때 y 좌표 기반 판별
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(
            nameKo: '신촌',
            lineId: '',
            position: dummyStation.position.copyWith(y: 1150),
          ),
          sinchonListKFirst,
        ),
        sinchonKNode,
      );
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(
            nameKo: '신촌',
            lineId: '',
            position: dummyStation.position.copyWith(y: 1250),
          ),
          sinchonListKFirst,
        ),
        sinchon2Node,
      );

      // 양평 5호선 vs 경의중앙선 분기 (실제 nodes.json 순서: 경의선 y=419, 5호선 y=1568)
      final yangpyeong5Node = const RouteMapOwnerNodeEntry(
        stationId: 'station-d5909895c7d7',
        lineId: 'line-80fc4d5350d4',
        name: '양평',
        x: 1234,
        y: 1568,
      );
      final yangpyeongKNode = const RouteMapOwnerNodeEntry(
        stationId: 'station-7bbe244e2071',
        lineId: 'line-6e39be0cb6e2',
        name: '양평',
        x: 3338,
        y: 419,
      );
      final ypListKFirst = [yangpyeongKNode, yangpyeong5Node];
      final ypList5First = [yangpyeong5Node, yangpyeongKNode];

      final ypStation = dummyStation.copyWith(nameKo: '양평');
      for (final list in [ypListKFirst, ypList5First]) {
        // 정확한 카탈로그 lineId 매칭
        expect(
          matchBestNodeEntry(
            ypStation.copyWith(lineId: 'line-80fc4d5350d4'),
            list,
          ),
          yangpyeong5Node,
        );
        expect(
          matchBestNodeEntry(
            ypStation.copyWith(lineId: 'line-6e39be0cb6e2'),
            list,
          ),
          yangpyeongKNode,
        );
        // 친화 라인 식별자 매칭
        expect(
          matchBestNodeEntry(ypStation.copyWith(lineId: 'line-5'), list),
          yangpyeong5Node,
        );
        expect(
          matchBestNodeEntry(ypStation.copyWith(lineId: 'line-gyeongui'), list),
          yangpyeongKNode,
        );
      }

      // 양평: lineId 없을 때 y 좌표 기반 판별
      expect(
        matchBestNodeEntry(
          ypStation.copyWith(
            lineId: '',
            position: dummyStation.position.copyWith(y: 400),
          ),
          ypListKFirst,
        ),
        yangpyeongKNode,
      );
      expect(
        matchBestNodeEntry(
          ypStation.copyWith(
            lineId: '',
            position: dummyStation.position.copyWith(y: 1500),
          ),
          ypListKFirst,
        ),
        yangpyeong5Node,
      );

      // 부산 동명이역 (부전, 좌천, 동래): 동해선 vs 1호선
      final bujeonL1Node = const RouteMapOwnerNodeEntry(
        stationId: 'station-9acc028dded4',
        lineId: 'line-ab1a041f6266',
        name: '부전',
        x: 6233,
        y: 4157,
      );
      final bujeonDhNode = const RouteMapOwnerNodeEntry(
        stationId: 'station-ee8407a487c2',
        lineId: 'line-f52eb59d8497',
        name: '부전',
        x: 5817,
        y: 3938,
      );
      final bjList = [bujeonL1Node, bujeonDhNode];
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(nameKo: '부전', lineId: 'line-f52eb59d8497'),
          bjList,
        ),
        bujeonDhNode,
      );
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(nameKo: '부전', lineId: 'donghae'),
          bjList,
        ),
        bujeonDhNode,
      );
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(nameKo: '부전', lineId: 'line-ab1a041f6266'),
          bjList,
        ),
        bujeonL1Node,
      );
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(nameKo: '부전', lineId: '1호선'),
          bjList,
        ),
        bujeonL1Node,
      );

      // 라인 ID 직접 일치 우선
      final custom1 = const RouteMapOwnerNodeEntry(
        stationId: 's-c1',
        lineId: 'line-custom-a',
        name: '커스텀',
        x: 10,
        y: 20,
      );
      final custom2 = const RouteMapOwnerNodeEntry(
        stationId: 's-c2',
        lineId: 'line-custom-b',
        name: '커스텀',
        x: 30,
        y: 40,
      );
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(nameKo: '커스텀', lineId: 'line-custom-b'),
          [custom1, custom2],
        ),
        custom2,
      );

      // 매칭 없으면 first
      expect(
        matchBestNodeEntry(
          dummyStation.copyWith(nameKo: '커스텀', lineId: 'unknown'),
          [custom1, custom2],
        ),
        custom1,
      );
    });

    test('RouteMapOwnerNodesLookup indexes and finds nodes accurately', () {
      final lookup = RouteMapOwnerNodesLookup(
        entries: [
          const RouteMapOwnerNodeEntry(
            stationId: 'station-oxu-3',
            lineId: 'line-3',
            name: '옥수',
            x: 2111,
            y: 1609,
          ),
          const RouteMapOwnerNodeEntry(
            stationId: 'station-oxu-k',
            lineId: 'line-gyeongui-jungang',
            name: '옥수',
            x: 2111,
            y: 1609,
          ),
          const RouteMapOwnerNodeEntry(
            stationId: 'station-seongnam',
            lineId: 'line-7',
            name: '석남(거북시장)',
            x: 444,
            y: 1502,
          ),
        ],
      );

      expect(lookup.isEmpty, isFalse);
      expect(lookup.isNotEmpty, isTrue);

      const dummyPos = NetworkMapPosition(
        x: 50000,
        y: 60000,
        labelDx: 0,
        labelDy: 0,
        upPath: '',
        downPath: '',
        sourceId: 'seoul-metro-route-map-positions',
      );

      // 1. (stationId, lineId) exact match
      final oxu3 = lookup.findNode(
        const NetworkMapStation(
          id: 'station-oxu-3',
          nameKo: '옥수',
          nameEn: 'Oksu',
          region: '수도권',
          lineId: 'line-3',
          stationCode: '335',
          sequence: 1,
          position: dummyPos,
        ),
      );
      expect(oxu3?.x, 2111);
      expect(oxu3?.y, 1609);

      // 2. stationId match (without lineId match)
      final oxuById = lookup.findNode(
        const NetworkMapStation(
          id: 'station-oxu-k',
          nameKo: '옥수',
          nameEn: 'Oksu',
          region: '수도권',
          lineId: 'different-line',
          stationCode: 'K114',
          sequence: 1,
          position: dummyPos,
        ),
      );
      expect(oxuById?.x, 2111);
      expect(oxuById?.y, 1609);

      // 3. (normalizedName, lineId) match
      final seongnamByLine = lookup.findNode(
        const NetworkMapStation(
          id: 'diff-id',
          nameKo: '석남',
          nameEn: 'Seongnam',
          region: '수도권',
          lineId: 'line-7',
          stationCode: '761',
          sequence: 1,
          position: dummyPos,
        ),
      );
      expect(seongnamByLine?.x, 444);
      expect(seongnamByLine?.y, 1502);

      // 4. nameKo match with normalized parenthesized subtitle
      final seongnamByName = lookup.findNode(
        const NetworkMapStation(
          id: 'diff-id',
          nameKo: '석남(거북시장)',
          nameEn: 'Seongnam',
          region: '수도권',
          lineId: 'line-unknown',
          stationCode: '761',
          sequence: 1,
          position: dummyPos,
        ),
      );
      expect(seongnamByName?.x, 444);
      expect(seongnamByName?.y, 1502);

      // 5. Homonym candidates > 1 triggers matchBestNodeEntry
      final sinchonLookup = RouteMapOwnerNodesLookup(
        entries: [
          const RouteMapOwnerNodeEntry(
            stationId: 's1',
            lineId: 'seoul-2',
            name: '신촌',
            x: 1369,
            y: 1227,
          ),
          const RouteMapOwnerNodeEntry(
            stationId: 's2',
            lineId: 'line-6e39be0cb6e2-gyeongui',
            name: '신촌',
            x: 1398,
            y: 1148,
          ),
        ],
      );
      final sinchonMatched = sinchonLookup.findNode(
        const NetworkMapStation(
          id: 'diff-id',
          nameKo: '신촌',
          nameEn: 'Sinchon',
          region: '수도권',
          lineId: '경의중앙선',
          stationCode: '',
          sequence: 1,
          position: dummyPos,
        ),
      );
      expect(sinchonMatched?.x, 1398);

      // 6. Unknown station returns null
      final unknown = lookup.findNode(
        const NetworkMapStation(
          id: 'diff-id',
          nameKo: '미등록역',
          nameEn: 'Unknown',
          region: '수도권',
          lineId: 'line-unknown',
          stationCode: '999',
          sequence: 1,
          position: dummyPos,
        ),
      );
      expect(unknown, isNull);
    });

    test(
      'Transfer station lines share identical node coordinates and are unified',
      () {
        final lookup = RouteMapOwnerNodesLookup(
          entries: [
            const RouteMapOwnerNodeEntry(
              stationId: 'station-oxu-3',
              lineId: 'line-3',
              name: '옥수',
              x: 2111,
              y: 1609,
            ),
            const RouteMapOwnerNodeEntry(
              stationId: 'station-oxu-k',
              lineId: 'line-gyeongui-jungang',
              name: '옥수',
              x: 2111,
              y: 1609,
            ),
          ],
        );

        final oxuLine3 = const NetworkMapStation(
          id: 'station-oxu-3',
          nameKo: '옥수',
          nameEn: 'Oksu',
          region: '수도권',
          lineId: 'line-3',
          stationCode: '335',
          sequence: 1,
          position: NetworkMapPosition(
            x: 2111,
            y: 1609,
            labelDx: 0,
            labelDy: 16,
            upPath: '',
            downPath: '',
            sourceId: 'owner-self-drawn-sma-schematic',
          ),
        );

        final oxuGyeongui = const NetworkMapStation(
          id: 'station-oxu-k',
          nameKo: '옥수',
          nameEn: 'Oksu',
          region: '수도권',
          lineId: 'line-gyeongui-jungang',
          stationCode: 'K114',
          sequence: 1,
          position: NetworkMapPosition(
            x: 51661,
            y: 65640,
            labelDx: 0,
            labelDy: -23,
            labelPolygon: '51661,65640 51700,65700',
            upPath: 'M51661 65640',
            downPath: 'M51661 65640',
            sourceId: 'seoul-metro-route-map-positions',
          ),
        );

        final aligned3 = alignStationForBasemap(oxuLine3, ownerNodes: lookup);
        final alignedK = alignStationForBasemap(
          oxuGyeongui,
          ownerNodes: lookup,
        );

        // 환승역의 두 호선이 100% 동일한 노드 중심 좌표를 공유
        expect(aligned3.position.x, 2111);
        expect(aligned3.position.y, 1609);
        expect(alignedK.position.x, 2111);
        expect(alignedK.position.y, 1609);
        expect(alignedK.position.labelPolygon, isEmpty);
        expect(alignedK.position.upPath, isEmpty);
        expect(alignedK.position.downPath, isEmpty);
      },
    );

    test('alignStationForBasemap aligns outlier stations to owner labels', () {
      final ownerEntries = {
        '강남': [
          const RouteMapOwnerLabelEntry(
            station: '강남',
            role: 'transfer',
            position: Offset(2100.0, 1850.0),
            anchor: RouteMapOwnerLabelAnchor.middle,
            fontSizePx: 15.47,
          ),
        ],
      };

      final outlierStation = const NetworkMapStation(
        id: 'station-gangnam',
        nameKo: '강남',
        nameEn: 'Gangnam',
        region: '수도권',
        lineId: 'line-2',
        stationCode: '222',
        sequence: 1,
        position: NetworkMapPosition(
          x: 48500,
          y: 65200,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'seoul-metro-route-map-positions',
        ),
      );

      final aligned = alignStationForBasemap(
        outlierStation,
        ownerEntries: ownerEntries,
      );
      expect(aligned.position.x, 2100);
      expect(aligned.position.y, 1850);

      // Normal station within bounds is unchanged
      final normalStation = outlierStation.copyWith(
        position: outlierStation.position.copyWith(x: 2100, y: 1850),
      );
      final kept = alignStationForBasemap(
        normalStation,
        ownerEntries: ownerEntries,
      );
      expect(identical(normalStation, kept), isTrue);

      // Station with owner-self-drawn-sma-schematic source is unchanged
      final schematicStation = outlierStation.copyWith(
        position: outlierStation.position.copyWith(
          x: 6000,
          y: 6000,
          sourceId: 'owner-self-drawn-sma-schematic',
        ),
      );
      final keptSchematic = alignStationForBasemap(
        schematicStation,
        ownerEntries: ownerEntries,
      );
      expect(identical(schematicStation, keptSchematic), isTrue);

      // Station with parenthesized subtitle falls back to normalized name in owner labels
      final parenthesizedStation = outlierStation.copyWith(
        id: 'station-seongnam',
        nameKo: '석남(거북시장)',
      );
      final normalizedOwnerEntries = {
        '석남': [
          const RouteMapOwnerLabelEntry(
            station: '석남',
            role: 'transfer',
            position: Offset(750.0, 1420.0),
            anchor: RouteMapOwnerLabelAnchor.middle,
            fontSizePx: 15.47,
          ),
        ],
      };
      final alignedNormalized = alignStationForBasemap(
        parenthesizedStation,
        ownerEntries: normalizedOwnerEntries,
      );
      expect(alignedNormalized.position.x, 750);
      expect(alignedNormalized.position.y, 1420);

      // Station not found in owner labels remains unchanged
      final unknownStation = outlierStation.copyWith(
        id: 'station-unknown',
        nameKo: '미지의역',
      );
      final keptUnknown = alignStationForBasemap(
        unknownStation,
        ownerEntries: ownerEntries,
      );
      expect(identical(unknownStation, keptUnknown), isTrue);

      // Null or empty ownerEntries returns original station
      expect(
        identical(
          outlierStation,
          alignStationForBasemap(outlierStation, ownerEntries: null),
        ),
        isTrue,
      );
      expect(
        identical(
          outlierStation,
          alignStationForBasemap(outlierStation, ownerEntries: const {}),
        ),
        isTrue,
      );
    });

    test(
      'alignNetworkMapDataForBasemap aligns whole dataset for basemap region',
      () {
        final ownerNodes = RouteMapOwnerNodesLookup(
          entries: [
            const RouteMapOwnerNodeEntry(
              stationId: 'station-gangnam',
              lineId: 'line-2',
              name: '강남',
              x: 2105,
              y: 1855,
            ),
          ],
        );
        final ownerEntries = {
          '강남': [
            const RouteMapOwnerLabelEntry(
              station: '강남',
              role: 'transfer',
              position: Offset(2100.0, 1850.0),
              anchor: RouteMapOwnerLabelAnchor.middle,
              fontSizePx: 15.47,
            ),
          ],
        };

        final data = NetworkMapData(
          regions: const [NetworkMapRegion(name: '수도권')],
          selectedRegion: '수도권',
          lines: const [],
          stations: [
            const NetworkMapStation(
              id: 'station-gangnam',
              nameKo: '강남',
              nameEn: 'Gangnam',
              region: '수도권',
              lineId: 'line-2',
              stationCode: '222',
              sequence: 1,
              position: NetworkMapPosition(
                x: 48500,
                y: 65200,
                labelDx: 0,
                labelDy: 0,
                upPath: '',
                downPath: '',
                sourceId: 'seoul-metro-route-map-positions',
              ),
            ),
          ],
          edges: const [],
          positionSources: const [],
          stationLineMemberships: const [],
          lineTracks: const [],
        );

        // ownerNodes가 있으면 exact node center (2105, 1855) 우선 정렬
        final alignedWithNodes = alignNetworkMapDataForBasemap(
          data,
          ownerNodes: ownerNodes,
          ownerEntries: ownerEntries,
        );
        expect(alignedWithNodes.stations.first.position.x, 2105);
        expect(alignedWithNodes.stations.first.position.y, 1855);

        // ownerNodes가 없으면 ownerEntries (2100, 1850)로 폴백
        final alignedData = alignNetworkMapDataForBasemap(
          data,
          ownerEntries: ownerEntries,
        );
        expect(alignedData.stations.first.position.x, 2100);
        expect(alignedData.stations.first.position.y, 1850);

        // For unmapped region, data is returned directly
        final otherRegionData = data.copyWith(selectedRegion: '알수없음');
        final unalignedData = alignNetworkMapDataForBasemap(
          otherRegionData,
          ownerEntries: ownerEntries,
        );
        expect(identical(otherRegionData, unalignedData), isTrue);

        // Empty / null ownerNodes and ownerEntries returns data directly
        expect(identical(data, alignNetworkMapDataForBasemap(data)), isTrue);
      },
    );

    test('routeMapOwnerNodesByRegionFrom parses sidecar correctly', () {
      const validJson = '''
      {
        "schemaVersion": 1,
        "artifactKind": "route-map-basemap-owner-nodes",
        "regions": {
          "seoul": [
            {
              "stationId": "s1",
              "lineId": "l1",
              "name": "시청",
              "x": 1845,
              "y": 1318
            }
          ]
        }
      }
      ''';
      final byRegion = routeMapOwnerNodesByRegionFrom(validJson);
      expect(byRegion.containsKey('seoul'), isTrue);
      final seoul = byRegion['seoul']!;
      expect(seoul.entries.length, 1);
      expect(seoul.entries.first.name, '시청');
      expect(seoul.entries.first.x, 1845);
      expect(seoul.entries.first.y, 1318);

      // Malformed json returns empty map
      expect(routeMapOwnerNodesByRegionFrom('invalid json'), isEmpty);
      expect(routeMapOwnerNodesByRegionFrom('{"regions": null}'), isEmpty);
      expect(
        routeMapOwnerNodesByRegionFrom('{"regions": {"seoul": 123}}'),
        isNotEmpty,
      );
      expect(
        routeMapOwnerNodesByRegionFrom(
          '{"regions": {"seoul": 123}}',
        )['seoul']!.isEmpty,
        isTrue,
      );
      expect(routeMapOwnerNodesByRegionFrom('{}'), isEmpty);
    });

    test(
      'alignStationForBasemap updates non-outlier station if node coordinates differ',
      () {
        final inBoundsStation = const NetworkMapStation(
          id: 'station-inbounds',
          nameKo: '내부역',
          nameEn: 'InBounds',
          region: '수도권',
          lineId: 'line-1',
          stationCode: '101',
          sequence: 1,
          position: NetworkMapPosition(
            x: 100,
            y: 200,
            labelDx: 0,
            labelDy: 0,
            labelPolygon: '100,200',
            upPath: 'M100 200',
            downPath: 'M100 200',
            sourceId: 'src',
          ),
        );
        final inBoundsLookup = RouteMapOwnerNodesLookup(
          entries: [
            const RouteMapOwnerNodeEntry(
              stationId: 'station-inbounds',
              lineId: 'line-1',
              name: '내부역',
              x: 105,
              y: 205,
            ),
          ],
        );
        final alignedInBounds = alignStationForBasemap(
          inBoundsStation,
          ownerNodes: inBoundsLookup,
        );
        expect(alignedInBounds.position.x, 105);
        expect(alignedInBounds.position.y, 205);
        expect(alignedInBounds.position.labelPolygon, '100,200');
        expect(alignedInBounds.position.upPath, 'M100 200');
        expect(alignedInBounds.position.downPath, 'M100 200');
      },
    );

    test(
      'NetworkMapStation and NetworkMapPosition copyWith covers all fields and defaults',
      () {
        const pos = NetworkMapPosition(
          x: 10,
          y: 20,
          labelDx: 1,
          labelDy: 2,
          labelPolygon: '1,2 3,4',
          upPath: 'M0 0',
          downPath: 'M1 1',
          sourceId: 'src',
        );

        final posDefault = pos.copyWith();
        expect(posDefault.x, 10);
        expect(posDefault.y, 20);
        expect(posDefault.labelDx, 1);
        expect(posDefault.labelDy, 2);
        expect(posDefault.labelPolygon, '1,2 3,4');
        expect(posDefault.upPath, 'M0 0');
        expect(posDefault.downPath, 'M1 1');
        expect(posDefault.sourceId, 'src');

        final posReplaced = pos.copyWith(
          x: 100,
          y: 200,
          labelDx: 11,
          labelDy: 22,
          labelPolygon: '5,6 7,8',
          upPath: 'M2 2',
          downPath: 'M3 3',
          sourceId: 'src2',
        );
        expect(posReplaced.x, 100);
        expect(posReplaced.y, 200);
        expect(posReplaced.labelDx, 11);
        expect(posReplaced.labelDy, 22);
        expect(posReplaced.labelPolygon, '5,6 7,8');
        expect(posReplaced.upPath, 'M2 2');
        expect(posReplaced.downPath, 'M3 3');
        expect(posReplaced.sourceId, 'src2');

        const station = NetworkMapStation(
          id: 's1',
          nameKo: '역1',
          nameEn: 'Station1',
          region: '수도권',
          lineId: 'line-1',
          stationCode: '101',
          sequence: 1,
          position: pos,
        );

        final stationDefault = station.copyWith();
        expect(stationDefault.id, 's1');
        expect(stationDefault.nameKo, '역1');
        expect(stationDefault.nameEn, 'Station1');
        expect(stationDefault.region, '수도권');
        expect(stationDefault.lineId, 'line-1');
        expect(stationDefault.stationCode, '101');
        expect(stationDefault.sequence, 1);
        expect(stationDefault.position.x, 10);

        final stationReplaced = station.copyWith(
          id: 's2',
          nameKo: '역2',
          nameEn: 'Station2',
          region: '부산',
          lineId: 'line-2',
          stationCode: '202',
          sequence: 2,
          position: posReplaced,
        );
        expect(stationReplaced.id, 's2');
        expect(stationReplaced.nameKo, '역2');
        expect(stationReplaced.nameEn, 'Station2');
        expect(stationReplaced.region, '부산');
        expect(stationReplaced.lineId, 'line-2');
        expect(stationReplaced.stationCode, '202');
        expect(stationReplaced.sequence, 2);
        expect(stationReplaced.position.x, 100);
      },
    );
  });
}
