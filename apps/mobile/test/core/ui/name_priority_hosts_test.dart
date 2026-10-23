import 'dart:math' as math;

import 'package:easysubway_mobile/app/network_map_nearby_panel_composition.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_panel_state.dart';
import 'package:easysubway_mobile/features/network_map/domain/nearby_adjacent_stations.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/application/station_search_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_line_badges.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_recent_search_section.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_search_body.dart';
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

/// 높이나 이름 폭이 정해진 칸의 마크 한 변은 모두 1.3배에서 멈춘다. 상단바 등 20dp
/// 마크는 26, 호선 탭 줄(48dp)의 32dp 마크는 41.6, 역 상세 머리 칸의 24dp 마크는
/// 31.2다.
final _fixedTabMarkSide = {1.0: 32.0, 1.3: 41.6, 1.5: 41.6, 2.0: 41.6};
final _fixedHeadMarkSide = {1.0: 24.0, 1.3: 31.2, 1.5: 31.2, 2.0: 31.2};
final _fixedChromeMarkSide = {1.0: 20.0, 1.3: 26.0, 1.5: 26.0, 2.0: 26.0};

/// 높이가 늘 수 있는 행 안 20dp 마크의 글자 배율별 한 변과 글자 크기.
/// 번들 PNG가 없는 원 마크 '5'와 알약 '수인분당'의 글자는 12·18·24, 11.6·17.4·23.2다.
final _flexibleMarkSide = {1.0: 20.0, 1.5: 30.0, 2.0: 40.0};
final _flexibleCircleGlyph = {1.0: 12.0, 1.5: 18.0, 2.0: 24.0};
final _flexiblePillGlyph = {1.0: 11.6, 1.5: 17.4, 2.0: 23.2};
final _flexiblePillWidth = {1.0: 60.6, 1.5: 90.4, 2.0: 120.2};

/// 검색 결과 행 높이. 마크 때문에 늘어나고, 알약이 넓은 320dp 2.0배에서는 이름이
/// 두 줄이 되어 행이 더 커진다.
final _searchRowHeight = {
  (320.0, 1.0): 52.0,
  (320.0, 1.5): 52.0,
  (320.0, 2.0): 56.0,
  (360.0, 1.0): 52.0,
  (360.0, 1.5): 52.0,
  (360.0, 2.0): 56.0,
};
const _searchPillRowHeight320At2x = 92.0;

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
        for (final scale in [1.0, 1.3, 1.5, 2.0]) {
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
              expect(
                rect.height,
                _fixedChromeMarkSide[scale],
                reason: '상단바 마크는 1.3배에서 멈춘다',
              );
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

  group('높이가 늘 수 있는 행의 마크는 시스템 글자 배율을 그대로 따른다', () {
    const circleMarkLine = StationSearchLine(
      id: 'busan-5',
      name: '부산 5호선',
      color: '#00A84D',
      stationCode: '',
    );
    const pillMarkLine = StationSearchLine(
      id: 'suin-bundang',
      name: '수도권 수인분당선',
      color: '#F5A200',
      stationCode: 'K211',
    );

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('검색 결과 행 ${width}dp 글자 $scale배', (tester) async {
          const station = StationSearchResult(
            id: 'hongdae',
            nameKo: '홍대입구',
            nameEn: '',
            region: '수도권',
            dataQualityLevel: 'LEVEL_1',
            lastVerifiedAt: '2026-06-13',
            lines: [circleMarkLine, pillMarkLine, _line2],
          );
          await _pump360(
            tester,
            Scaffold(
              body: SingleChildScrollView(
                child: StationSearchBody(
                  state: const StationSearchState(
                    status: StationSearchStatus.success,
                    results: [station],
                  ),
                  query: '홍',
                  onResultTap: (_, _) {},
                ),
              ),
            ),
            scale,
            width: width,
          );

          final side = _flexibleMarkSide[scale]!;
          for (final line in [circleMarkLine, pillMarkLine, _line2]) {
            final row = find.byKey(
              Key('stationSearchResult-hongdae-${line.id}'),
            );
            final mark = find.descendant(
              of: row,
              matching: find.byKey(Key('stationLineBadge-${line.id}')),
            );
            final markSize = tester.getSize(mark);
            expect(markSize.height, side, reason: '${line.id} 마크 한 변');

            final isPill = line == pillMarkLine;
            if (isPill) {
              expect(markSize.width, closeTo(_flexiblePillWidth[scale]!, 0.05));
            } else {
              expect(markSize.width, side);
            }
            if (line != _line2) {
              final glyph = _paragraph(
                tester,
                find.descendant(of: mark, matching: find.byType(Text)),
              );
              final expectedFont = isPill
                  ? _flexiblePillGlyph[scale]!
                  : _flexibleCircleGlyph[scale]!;
              expect(glyph.text.style!.fontSize, closeTo(expectedFont, 0.001));
              expect(glyph.didExceedMaxLines, isFalse);
              expect(glyph.textSize.height, lessThanOrEqualTo(markSize.height));
              expect(glyph.textSize.width, lessThanOrEqualTo(markSize.width));
            }

            final rowHeight = tester.getSize(row).height;
            final expectedHeight = isPill && width == 320 && scale == 2.0
                ? _searchPillRowHeight320At2x
                : _searchRowHeight[(width, scale)];
            expect(rowHeight, expectedHeight, reason: '${line.id} 행 높이');
            expect(rowHeight, greaterThanOrEqualTo(markSize.height + 16));

            final name = _paragraph(
              tester,
              find.descendant(of: row, matching: find.byType(RichText)).first,
            );
            _expectNameReadable(name, scale);
            expect(
              name.size.width,
              greaterThanOrEqualTo(4 * 16.0 * scale),
              reason: '${line.id} 이름은 마크 옆에서도 글자 네 개 폭을 지킨다',
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('최근 검색 행 알약은 ${width}dp 글자 $scale배에서도 눌리지 않는다', (
          tester,
        ) async {
          await _pump360(
            tester,
            Scaffold(
              body: SingleChildScrollView(
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
            scale,
            width: width,
          );

          for (final label in ['경의중앙', '공항철도']) {
            final glyph = _paragraph(tester, find.text(label));
            expect(
              glyph.text.style!.fontSize,
              closeTo(_flexiblePillGlyph[scale]!, 0.001),
            );
            expect(glyph.didExceedMaxLines, isFalse, reason: '$label 글자 잘림');
            final mark = tester.getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(LineMark),
                  )
                  .first,
            );
            expect(mark.height, _flexibleMarkSide[scale]);
            expect(mark.width, closeTo(_flexiblePillWidth[scale]!, 0.05));
            expect(glyph.textSize.width, lessThanOrEqualTo(mark.width));
          }
          _expectNameReadable(_paragraph(tester, find.text(_name)), scale);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '최근 경로 행 마크는 글자 $scale배에서 상한 없이 ${_flexibleMarkSide[scale]}가 된다',
        (tester) async {
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
                    originLines: [_gyeonguiJungang],
                    destinationLines: [_line2],
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

          final side = _flexibleMarkSide[scale]!;
          final pill = tester.getSize(
            find.byKey(Key('stationLineBadge-${_gyeonguiJungang.id}')),
          );
          expect(pill.height, side, reason: '알약 한 변');
          expect(pill.width, closeTo(_flexiblePillWidth[scale]!, 0.05));
          expect(
            tester.getSize(find.byKey(Key('stationLineBadge-${_line2.id}'))),
            Size.square(side),
            reason: '원 마크 한 변',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('높이나 이름 폭이 정해진 칸의 마크는 1.3배에서 멈춘다', () {
    const circleLine = StationSearchLine(
      id: 'seoul-4',
      name: '수도권 4호선',
      color: '#00A5DE',
      stationCode: '434',
    );

    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets(
        '호선 탭 줄은 글자 $scale배에서 48dp 안에 마크 한 변 ${_fixedTabMarkSide[scale]}를 둔다',
        (tester) async {
          await _pump360(
            tester,
            Scaffold(
              body: Row(
                children: [
                  for (final line in [circleLine, _gyeonguiJungang])
                    StationLineBadgeTab(
                      line: line,
                      selected: false,
                      onTap: () {},
                    ),
                ],
              ),
            ),
            scale,
          );

          final side = _fixedTabMarkSide[scale]!;
          for (final line in [circleLine, _gyeonguiJungang]) {
            final tab = tester.getRect(
              find.byKey(Key('stationLineBadgeTab-${line.id}')),
            );
            final mark = tester.getRect(
              find.byKey(Key('stationLineBadge-${line.id}')),
            );
            expect(tab.height, 48);
            expect(mark.height, closeTo(side, 0.001), reason: '${line.id} 마크');
            expect(mark.top, greaterThanOrEqualTo(tab.top));
            expect(mark.bottom, lessThanOrEqualTo(tab.bottom));
          }
        },
      );

      testWidgets(
        '역 상세 머리 칸은 글자 $scale배에서 마크 한 변 ${_fixedHeadMarkSide[scale]}에서 멈추고 이름 폭을 남긴다',
        (tester) async {
          await _pump360(
            tester,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: StationDetailBody(
                  state: const StationDetailState(
                    status: StationDetailStatus.success,
                    detail: StationDetail(
                      id: 'station-hongdae',
                      nameKo: '홍대입구',
                      nameEn: '',
                      region: '수도권',
                      dataQualityLevel: 'LEVEL_1',
                      lastVerifiedAt: '2026-09-27',
                      latitude: 37.557,
                      longitude: 126.924,
                      lines: [_suinBundang],
                    ),
                    exits: [],
                    facilities: [],
                  ),
                  onRetryRealtime: () {},
                  onOpenFacilityReport: (_) async {},
                  showContextChrome: true,
                  showRealtimeSection: false,
                  onClose: () {},
                ),
              ),
            ),
            scale,
            width: 320,
          );

          final chrome = find.byKey(const Key('stationDetailContextChrome'));
          final mark = tester.getRect(
            find.descendant(
              of: chrome,
              matching: find.byKey(const Key('stationLineBadge-suin-bundang')),
            ),
          );
          final side = _fixedHeadMarkSide[scale]!;
          expect(mark.height, closeTo(side, 0.001));
          final name = tester.getRect(
            find.descendant(of: chrome, matching: find.text('홍대입구역')),
          );
          expect(mark.right, lessThanOrEqualTo(name.left));
          expect(
            name.width,
            greaterThanOrEqualTo(90),
            reason: '마크가 1.3배에서 멈추므로 이름은 실측 90dp 아래로 줄지 않는다',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    // 캡슐 높이는 지도 폭에 비례해 정해진다. 마크는 1.3배에서 멈추고 캡슐 안에
    // 있다. 320dp의 원 마크는 캡슐 안쪽 높이 29.1이 한 변 31.2보다 작아 높이가 눌린다.
    // 앱이 조합하는 주변역 패널의 막대와, 배지 빌더가 없을 때의 막대를 모두 잰다.
    for (final (width, circleSide, circleHeight) in [
      (320.0, 31.2, 29.1),
      (360.0, 31.8, 31.8),
    ]) {
      for (final scale in [1.3, 1.5, 2.0]) {
        testWidgets('주변역 캡슐 ${width}dp 글자 $scale배 마크는 캡슐 안에서 멈춘다', (
          tester,
        ) async {
          Future<(Rect, Rect)> composedBar(StationSearchLine line) async {
            final content = buildNetworkMapNearbyPanelSuccessContent(
              results: const [
                StationSearchResult(
                  id: 'hongdae',
                  nameKo: '홍대입구',
                  nameEn: '',
                  region: '수도권',
                  dataQualityLevel: 'LEVEL_1',
                  lastVerifiedAt: '2026-06-13',
                  lines: [circleLine, _gyeonguiJungang],
                ),
              ],
              realtime: const RealtimeSnapshot(
                status: RealtimeSnapshotStatus.unavailable,
              ),
              selectedLineId: line.id,
              dataSource: NetworkMapNearbyPanelDataSource.realtime,
              timetable: null,
              adjacentStations: const NearbyAdjacentStations(
                leftName: '신촌',
                rightName: '합정',
              ),
            );
            await _pump360(
              tester,
              Scaffold(body: content.stationBar),
              scale,
              width: width,
            );
            return (
              tester.getRect(
                find.byKey(const Key('nearbyStationLineBarCapsule')),
              ),
              tester.getRect(find.byKey(Key('stationLineBadge-${line.id}'))),
            );
          }

          final (circleCapsule, circle) = await composedBar(circleLine);
          expect(circle.width, closeTo(circleSide, 0.05));
          expect(circle.height, closeTo(circleHeight, 0.05));
          expect(circle.top, greaterThanOrEqualTo(circleCapsule.top));
          expect(circle.bottom, lessThanOrEqualTo(circleCapsule.bottom));

          final (pillCapsule, pill) = await composedBar(_gyeonguiJungang);
          expect(pill.height, 26);
          expect(pill.width, closeTo(78.48, 0.05));
          expect(pill.top, greaterThanOrEqualTo(pillCapsule.top));
          expect(pill.bottom, lessThanOrEqualTo(pillCapsule.bottom));
          expect(pill.left, greaterThanOrEqualTo(pillCapsule.left));
          expect(pill.right, lessThanOrEqualTo(pillCapsule.right));
          expect(tester.takeException(), isNull);
        });

        testWidgets('배지 빌더 없는 주변역 캡슐 ${width}dp 글자 $scale배 알약은 26에서 멈춘다', (
          tester,
        ) async {
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
            scale,
            width: width,
          );

          final capsule = tester.getRect(
            find.byKey(const Key('nearbyStationLineBarCapsule')),
          );
          final mark = tester.getRect(
            find.byKey(const Key('nearbyStationLineBarBadge')),
          );
          expect(mark.height, 26);
          expect(mark.width, closeTo(78.48, 0.05));
          expect(mark.top, greaterThanOrEqualTo(capsule.top));
          expect(mark.bottom, lessThanOrEqualTo(capsule.bottom));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
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
