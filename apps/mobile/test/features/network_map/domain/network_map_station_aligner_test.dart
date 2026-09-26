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
  });
}
