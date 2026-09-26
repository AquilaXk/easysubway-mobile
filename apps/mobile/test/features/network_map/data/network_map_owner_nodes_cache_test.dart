import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('network_map_owner_nodes_cache', () {
    tearDown(() {
      resetNetworkMapOwnerNodesCacheForTest();
    });

    test('cache state management works correctly', () {
      expect(cachedNetworkMapOwnerNodesByRegion, isNull);

      final mockLookup = RouteMapOwnerNodesLookup(
        entries: const [
          RouteMapOwnerNodeEntry(
            stationId: 's1',
            lineId: 'l1',
            name: '역1',
            x: 10,
            y: 20,
          ),
        ],
      );
      final mockData = {'수도권': mockLookup};

      primeNetworkMapOwnerNodesCacheForTest(mockData);
      expect(cachedNetworkMapOwnerNodesByRegion, isNotNull);
      expect(cachedNetworkMapOwnerNodesByRegion?['수도권']?.entries.length, 1);

      invalidateNetworkMapOwnerNodesLoad();
      expect(cachedNetworkMapOwnerNodesByRegion, isNotNull);

      resetNetworkMapOwnerNodesCacheForTest();
      expect(cachedNetworkMapOwnerNodesByRegion, isNull);
    });

    test(
      'loadNetworkMapOwnerNodesByRegion parses asset pack correctly',
      () async {
        final byRegion = await loadNetworkMapOwnerNodesByRegion();
        expect(byRegion, isNotEmpty);
        expect(byRegion.containsKey('seoul'), isTrue);
        expect(byRegion['seoul']!.isNotEmpty, isTrue);
        expect(cachedNetworkMapOwnerNodesByRegion, isNotNull);

        // Subsequent call reuses cached future
        final cachedAgain = await loadNetworkMapOwnerNodesByRegion();
        expect(identical(byRegion, cachedAgain), isTrue);
      },
    );
  });
}
