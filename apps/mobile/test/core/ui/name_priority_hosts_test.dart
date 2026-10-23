import 'dart:math' as math;

import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_line_badges.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_recent_search_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = '홍대입구역';
const _line2 = StationSearchLine(
  id: 'seoul-2',
  name: '수도권 2호선',
  color: '#00A84D',
  stationCode: '239',
);
const _gyeonguiJungang = StationSearchLine(
  id: 'gyeongui-jungang',
  name: '수도권 경의중앙선',
  color: '#77C4A3',
  stationCode: 'K314',
);
const _airportRailroad = StationSearchLine(
  id: 'airport-railroad',
  name: '수도권 공항철도',
  color: '#0090D2',
  stationCode: 'A03',
);
const _hongdae = [_line2, _gyeonguiJungang, _airportRailroad];

const _line5 = StationSearchLine(
  id: 'seoul-5',
  name: '수도권 5호선',
  color: '#996CAC',
  stationCode: '2625',
);
const _line6 = StationSearchLine(
  id: 'seoul-6',
  name: '수도권 6호선',
  color: '#CD7C2F',
  stationCode: '626',
);
const _suinBundang = StationSearchLine(
  id: 'suin-bundang',
  name: '수도권 수인분당선',
  color: '#F5A200',
  stationCode: 'K211',
);
const _shinbundang = StationSearchLine(
  id: 'shinbundang',
  name: '수도권 신분당선',
  color: '#D4003B',
  stationCode: 'D07',
);

/// 상단바에 놓이는 노선 묶음과 그 결과. 공덕은 실제 4개 호선이고, 나머지는
/// 알약이 많아 가장 넓은 조합이다. `hidden`은 마크 하나 뒤에 붙는 +N이다.
const _appBarFixtures =
    <({String name, List<StationSearchLine> lines, int hidden})>[
      (name: '2개 호선', lines: [_gyeonguiJungang, _airportRailroad], hidden: 0),
      (name: '3개 호선', lines: _hongdae, hidden: 2),
      (
        name: '공덕 4개 호선',
        lines: [_line5, _line6, _airportRailroad, _gyeonguiJungang],
        hidden: 3,
      ),
      (
        name: '알약 5개 호선',
        lines: [
          _gyeonguiJungang,
          _airportRailroad,
          _suinBundang,
          _shinbundang,
          _line2,
        ],
        hidden: 4,
      ),
    ];

Future<void> _pump360(
  WidgetTester tester,
  Widget home,
  double scale, {
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

RenderParagraph _paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text);

int _lineCount(RenderParagraph paragraph) {
  final length = paragraph.text.toPlainText().length;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  );
  return boxes.map((box) => box.top.round()).toSet().length;
}

/// 이름 글자가 마크 때문에 줄바꿈·말줄임으로 망가지지 않았는지 본다.
/// 1.0배는 한 줄 전체가 보여야 하고, 큰 글자에서도 글자 단위로 쪼개지지 않는다.
void _expectNameReadable(RenderParagraph name, double scale) {
  final lines = _lineCount(name);
  if (scale == 1.0) {
    expect(name.didExceedMaxLines, isFalse, reason: '1.0배 이름 말줄임');
    expect(lines, 1, reason: '1.0배 이름 줄바꿈');
  }
  expect(lines, lessThanOrEqualTo(2), reason: '글자 단위 줄바꿈');
}

void main() {
  group('상단바 마크는 호선이 많아도 상단바 밖으로 나가지 않는다', () {
    for (final fixture in _appBarFixtures) {
      for (final width in [300.0, 320.0, 360.0]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          testWidgets('${fixture.name} ${width}dp 글자 $scale배', (tester) async {
            await _pump360(
              tester,
              StationDetailScreen(
                repository: _StationRepository(fixture.lines),
                reportRepository: const UnavailableFacilityReportRepository(),
                stationId: 'station-hongdae',
                enableRealtimePolling: false,
              ),
              scale,
              width: width,
            );

            final appBar = tester.getRect(
              find.byKey(const Key('stationDetailAppBar')),
            );
            expect(appBar.height, 60);
            final marks = find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'stationLineBadge',
                  ),
            );
            final overflow = find.byKey(const Key('stationLineBadgeOverflow'));
            final expectedOverflow = fixture.hidden > 0 ? 1 : 0;
            expect(
              marks.evaluate().length - expectedOverflow,
              fixture.lines.length - fixture.hidden,
              reason: '보이는 호선 마크 수',
            );
            expect(overflow, findsNWidgets(expectedOverflow));
            if (fixture.hidden > 0) {
              expect(find.text('+${fixture.hidden}'), findsOneWidget);
            }
            for (final mark in marks.evaluate()) {
              final rect = tester.getRect(find.byWidget(mark.widget));
              expect(rect.top, greaterThanOrEqualTo(appBar.top));
              expect(rect.bottom, lessThanOrEqualTo(appBar.bottom));
              expect(rect.right, lessThanOrEqualTo(appBar.right));
            }
            final name = tester.getRect(
              find.descendant(
                of: find.byKey(const Key('stationDetailAppBar')),
                matching: find.text(_name),
              ),
            );
            for (final mark in marks.evaluate()) {
              final rect = tester.getRect(find.byWidget(mark.widget));
              expect(
                rect.right,
                lessThanOrEqualTo(name.left),
                reason: '이름이 마크에 밀리지 않는다',
              );
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    group('360dp 글자 $scale배에서 역 이름이 마크에 밀리지 않는다', () {
      testWidgets('역 상세 상단바 제목', (tester) async {
        await _pump360(
          tester,
          StationDetailScreen(
            repository: _StationRepository(_hongdae),
            reportRepository: const UnavailableFacilityReportRepository(),
            stationId: 'station-hongdae',
            enableRealtimePolling: false,
          ),
          scale,
        );

        final appBar = find.byKey(const Key('stationDetailAppBar'));
        final name = _paragraph(
          tester,
          find.descendant(of: appBar, matching: find.text(_name)),
        );
        _expectNameReadable(name, scale);
        // 큰 글자에서 말줄임이 생겨도 이름 글자 세 개는 보여야 한다.
        final glyph = name.text.style!.fontSize! * scale;
        expect(name.size.width, greaterThanOrEqualTo(3 * glyph));
        final bar = tester.getRect(appBar);
        for (final mark in tester.widgetList(
          find.descendant(of: appBar, matching: find.byType(LineMark)),
        )) {
          final rect = tester.getRect(find.byWidget(mark));
          expect(rect.top, greaterThanOrEqualTo(bar.top));
          expect(rect.bottom, lessThanOrEqualTo(bar.bottom));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('최근 검색 행', (tester) async {
        await _pump360(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: StationRecentSearchSection(
                  entries: [
                    RecentStationSearchEntry(
                      query: _name,
                      region: null,
                      searchedAt: DateTime(2026, 10, 23),
                      lines: _hongdae,
                    ),
                  ],
                  enabled: true,
                  onStationSelected: (_) {},
                  onRouteSelected: (_) {},
                  onRemove: (_) {},
                  onClearAll: () {},
                ),
              ),
            ),
          ),
          scale,
        );

        final name = _paragraph(tester, find.text(_name));
        _expectNameReadable(name, scale);
        expect(tester.takeException(), isNull);
      });

      testWidgets('최근 경로 행은 마크가 있어도 역 이름이 한 줄로 이어진다', (tester) async {
        await _pump360(
          tester,
          Scaffold(
            body: StationRecentSearchSection(
              entries: [
                RecentRouteSearchEntry(
                  originStationId: 'station-hongdae',
                  originStationName: '홍대입구',
                  destinationStationId: 'station-gangnam',
                  destinationStationName: '강남',
                  region: '수도권',
                  searchedAt: DateTime(2026, 10, 23),
                  originLines: _hongdae,
                  destinationLines: [_hongdae.first],
                ),
              ],
              enabled: true,
              onStationSelected: (_) {},
              onRouteSelected: (_) {},
              onRemove: (_) {},
              onClearAll: () {},
            ),
          ),
          scale,
        );

        for (final name in ['홍대입구역', '강남역']) {
          _expectNameReadable(_paragraph(tester, find.text(name)), scale);
        }
        expect(find.byType(StationLineBadge), findsNWidgets(2));
        expect(
          find.byKey(const Key('stationLineBadgeOverflow')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('주변역 캡슐', (tester) async {
        // 캡슐 이름은 FittedBox가 줄이므로 화면에 그려지는 글자 높이로 잰다.
        Future<double> renderedNameHeight(double textScale) async {
          await _pump360(
            tester,
            Scaffold(
              body: NearbyStationLineBar(
                stationName: '홍대입구',
                leftName: '신촌',
                rightName: '합정',
                badgeText: '경의중앙',
                lineColor: const Color(0xFF77C4A3),
                onStationNameTap: () {},
              ),
            ),
            textScale,
          );
          final host = find.byKey(const Key('nearbyStationLineBarStationName'));
          final paragraph = _paragraph(
            tester,
            find.descendant(of: host, matching: find.text('홍대입구')),
          );
          final fitted = tester.getSize(
            find.descendant(of: host, matching: find.byType(FittedBox)),
          );
          final shrink = math.min(1, fitted.width / paragraph.textSize.width);
          return paragraph.textSize.height * shrink;
        }

        final atDefault = await renderedNameHeight(1.0);
        final atScale = await renderedNameHeight(scale);
        expect(atScale, greaterThanOrEqualTo(atDefault));
      });
    });
  }
}

class _StationRepository implements StationSearchRepository {
  const _StationRepository(this.lines);

  final List<StationSearchLine> lines;

  @override
  Future<StationDetail> getStationDetail(String stationId) async =>
      StationDetail(
        id: 'station-hongdae',
        nameKo: '홍대입구',
        nameEn: 'Hongik Univ.',
        region: '수도권',
        dataQualityLevel: 'LEVEL_1',
        lastVerifiedAt: '2026-09-27',
        latitude: 37.557,
        longitude: 126.924,
        lines: lines,
      );

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async =>
      const [];

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async => const [];

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async => const [];

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async => const [];
}
