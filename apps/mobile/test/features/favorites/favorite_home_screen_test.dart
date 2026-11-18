import 'package:easysubway_mobile/features/favorites/presentation/favorite_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'FavoriteHomeScreen empty state는 지하철역 검색하러 가기 CTA를 렌더링하고 탭 시 onSearchStation을 호출한다',
    (tester) async {
      var searchStationCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteHomeScreen(
            favoriteRepository: null,
            favoriteFacilityRepository: null,
            favoriteRouteRepository: null,
            onOpenStationDetail: (_) async {},
            onOpenFacilityReport: (_) async {},
            onOpenFavoriteRoute: (_) async {},
            onSearchStation: () => searchStationCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('즐겨찾기한 항목이 없습니다.'), findsOneWidget);
      final buttonFinder = find.byKey(
        const Key('favoriteHomeSearchStationButton'),
      );
      expect(buttonFinder, findsOneWidget);
      expect(find.text('지하철역 검색하러 가기'), findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(searchStationCalled, isTrue);
    },
  );
}
