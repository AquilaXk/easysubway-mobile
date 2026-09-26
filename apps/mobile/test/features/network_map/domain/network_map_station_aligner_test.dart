import 'package:flutter_test/flutter_test.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_aligner.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';

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

      // 빈 entries 리스트 방어
      expect(
        () => matchBestOwnerEntry(yangpyeong5, const []),
        throwsArgumentError,
      );
    });

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

      final aligned = alignStationForBasemap(outlierStation, ownerEntries);
      expect(aligned.position.x, 2100);
      expect(aligned.position.y, 1850);

      // Normal station within bounds is unchanged
      final normalStation = outlierStation.copyWith(
        position: outlierStation.position.copyWith(x: 2100, y: 1850),
      );
      final kept = alignStationForBasemap(normalStation, ownerEntries);
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
        ownerEntries,
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
        normalizedOwnerEntries,
      );
      expect(alignedNormalized.position.x, 750);
      expect(alignedNormalized.position.y, 1420);

      // Station not found in owner labels remains unchanged
      final unknownStation = outlierStation.copyWith(
        id: 'station-unknown',
        nameKo: '미지의역',
      );
      final keptUnknown = alignStationForBasemap(unknownStation, ownerEntries);
      expect(identical(unknownStation, keptUnknown), isTrue);

      // Null or empty ownerEntries returns original station
      expect(
        identical(outlierStation, alignStationForBasemap(outlierStation, null)),
        isTrue,
      );
      expect(
        identical(
          outlierStation,
          alignStationForBasemap(outlierStation, const {}),
        ),
        isTrue,
      );
    });

    test(
      'alignNetworkMapDataForBasemap aligns whole dataset for basemap region',
      () {
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

        final alignedData = alignNetworkMapDataForBasemap(data, ownerEntries);
        expect(alignedData.stations.first.position.x, 2100);
        expect(alignedData.stations.first.position.y, 1850);

        // For unmapped region, data is returned directly
        final otherRegionData = data.copyWith(selectedRegion: '알수없음');
        final unalignedData = alignNetworkMapDataForBasemap(
          otherRegionData,
          ownerEntries,
        );
        expect(identical(otherRegionData, unalignedData), isTrue);
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
