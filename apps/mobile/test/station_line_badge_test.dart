import 'dart:io';

import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_line_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const badgeCases = [
    ('seoul-1', '수도권 1호선', 'seoul_1_compact_256.png'),
    ('seoul-2', '수도권 2호선', 'seoul_2_compact_256.png'),
    ('seoul-3', '수도권 3호선', 'seoul_3_compact_256.png'),
    ('seoul-4', '수도권 4호선', 'seoul_4_compact_256.png'),
    ('seoul-5', '수도권 5호선', 'seoul_5_compact_256.png'),
    ('seoul-6', '수도권 6호선', 'seoul_6_compact_256.png'),
    ('seoul-7', '수도권 7호선', 'seoul_7_compact_256.png'),
    ('seoul-8', '수도권 8호선', 'seoul_8_compact_256.png'),
    ('seoul-9', '수도권 9호선', 'seoul_9_compact_256.png'),
    ('gyeongui-jungang', '수도권 경의중앙선', 'gyeongui_jungang_compact_256.png'),
    ('suin-bundang', '수도권 수인분당선', 'suin_bundang_compact_256.png'),
    ('shinbundang', '수도권 신분당선', 'shinbundang_compact_256.png'),
    ('airport', '수도권 공항철도', 'airport_railroad_compact_256.png'),
    ('incheon-1', '수도권 인천 1호선', 'incheon_1_compact_256.png'),
    ('incheon-2', '수도권 인천 2호선', 'incheon_2_compact_256.png'),
    ('uijeongbu', '수도권 의정부경전철', 'uijeongbu_lrt_compact_256.png'),
    ('ui-sinseol', '수도권 우이신설선', 'ui_sinseol_compact_256.png'),
    ('gimpo-goldline', '수도권 김포골드라인', 'gimpo_goldline_compact_256.png'),
    ('everline', '수도권 용인에버라인', 'everline_compact_256.png'),
    ('sillim', '수도권 신림선', 'sillim_compact_256.png'),
    ('gyeongchun', '수도권 경춘선', 'gyeongchun_compact_256.png'),
    ('gyeonggang', '수도권 경강선', 'gyeonggang_compact_256.png'),
    ('seohae', '수도권 서해선', 'seohae_compact_256.png'),
    ('gtx-a', '수도권 GTX-A', 'gtx_a_compact_256.png'),
    ('busan-1', '1호선', 'busan_1_compact_256.png'),
    ('busan-2', '2호선', 'busan_2_compact_256.png'),
    ('busan-3', '3호선', 'busan_3_compact_256.png'),
    ('busan-4', '4호선', 'busan_4_compact_256.png'),
    ('bgl', '부산김해경전철', 'busan_gimhae_compact_256.png'),
    ('donghae', '동해선', 'donghae_compact_256.png'),
    ('daegu-1', '대구 1호선', 'daegu_1_compact_256.png'),
    ('daegu-2', '대구 2호선', 'daegu_2_compact_256.png'),
    ('daegu-3', '대구 3호선', 'daegu_3_compact_256.png'),
    ('daegyeong', '대구 대경선', 'daegyeong_compact_256.png'),
    ('daejeon-1', '대전 1호선', 'daejeon_1_compact_256.png'),
    ('gwangju-1', '광주 1호선', 'gwangju_1_compact_256.png'),
  ];

  test('전국 노선 심볼은 제공 라이브러리 PNG asset으로 연결된다', () {
    for (final (id, name, asset) in badgeCases) {
      expect(stationLineBadgeAssetNameFor(id: id, name: name), asset);
      expect(
        File('assets/metro_symbols/line_badges/$asset').existsSync(),
        isTrue,
      );
    }

    final assetCount = Directory('assets/metro_symbols/line_badges')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_compact_256.png'))
        .length;
    expect(assetCount, badgeCases.length);
  });

  test('제공되지 않은 번호 노선은 PNG asset 경로를 만들지 않는다', () {
    expect(
      stationLineBadgeAssetNameFor(id: 'seoul-10', name: '수도권 10호선'),
      isNull,
    );
    expect(stationLineBadgeAssetNameFor(id: 'busan-5', name: '부산 5호선'), isNull);
    expect(
      stationLineBadgeAssetNameFor(id: 'daejeon-2', name: '대전 2호선'),
      isNull,
    );
  });

  testWidgets('노선 배지 위젯은 가변 알약 캡슐형 시스템에 맞춰 렌더링한다', (tester) async {
    final lines = [
      for (final (id, name, _) in badgeCases)
        StationSearchLine(
          id: id,
          name: name,
          color: '#00A5DE',
          stationCode: '',
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StationLineBadges(lines: lines, size: 40)),
      ),
    );

    for (final (id, name, _) in badgeCases) {
      final finder = find.byKey(Key('stationLineBadge-$id'));
      expect(finder, findsOneWidget);
      final size = tester.getSize(finder);
      final badgeText = stationLineBadgeText(name);
      final isSingleChar = badgeText.length <= 1;

      if (isSingleChar) {
        expect(size, const Size(40, 40), reason: '$name ($badgeText) 정원형');
      } else {
        expect(size.height, 40, reason: '$name ($badgeText) 높이 고정');
        expect(size.width, greaterThan(40), reason: '$name ($badgeText) 가변 알약');
      }
    }
  });

  testWidgets('StationLineBadgeTab은 배지 폭에 맞춰 인디케이터가 연동된다', (tester) async {
    const singleLine = StationSearchLine(
      id: 'seoul-4',
      name: '수도권 4호선',
      color: '#00A5DE',
      stationCode: '448',
    );
    const multiLine = StationSearchLine(
      id: 'suin-bundang',
      name: '수도권 수인분당선',
      color: '#FABE00',
      stationCode: 'K210',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              StationLineBadgeTab(
                line: singleLine,
                selected: true,
                onTap: () {},
                size: 28,
              ),
              StationLineBadgeTab(
                line: multiLine,
                selected: false,
                onTap: () {},
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );

    final singleFinder = find.byKey(const Key('stationLineBadgeTab-seoul-4'));
    final multiFinder = find.byKey(
      const Key('stationLineBadgeTab-suin-bundang'),
    );

    expect(singleFinder, findsOneWidget);
    expect(multiFinder, findsOneWidget);

    final singleSize = tester.getSize(singleFinder);
    final multiSize = tester.getSize(multiFinder);

    expect(singleSize.height, 48);
    expect(singleSize.width, 48); // 최소 터치 타겟 48 유지

    expect(multiSize.height, 48);
    expect(multiSize.width, greaterThan(48)); // 가변 알약에 맞춰 확장
  });

  test('stationLineBadgeText는 경전철 및 GTX를 포함한 전국 노선명을 정확히 추출한다', () {
    expect(stationLineBadgeText('수도권 1호선'), '1');
    expect(stationLineBadgeText('수도권 4호선'), '4');
    expect(stationLineBadgeText('수도권 9호선'), '9');
    expect(stationLineBadgeText('부산 1호선'), '1');
    expect(stationLineBadgeText('대구 2호선'), '2');
    expect(stationLineBadgeText('대전 1호선'), '1');
    expect(stationLineBadgeText('광주 1호선'), '1');
    expect(stationLineBadgeText('수도권 수인분당선'), '수인분당');
    expect(stationLineBadgeText('수도권 경의중앙선'), '경의중앙');
    expect(stationLineBadgeText('수도권 신분당선'), '신분당');
    expect(stationLineBadgeText('수도권 공항철도'), '공항철도');
    expect(stationLineBadgeText('수도권 의정부경전철'), '의정부');
    expect(stationLineBadgeText('수도권 우이신설선'), '우이신설');
    expect(stationLineBadgeText('우이신설경전철'), '우이신설');
    expect(stationLineBadgeText('수도권 신림선'), '신림');
    expect(stationLineBadgeText('신림경전철'), '신림');
    expect(stationLineBadgeText('수도권 용인에버라인'), '에버라인');
    expect(stationLineBadgeText('수도권 김포골드라인'), '김포골드');
    expect(stationLineBadgeText('부산김해경전철'), '부산김해');
    expect(stationLineBadgeText('수도권 GTX-A'), 'GTX-A');
    expect(stationLineBadgeText('GTX-B'), 'GTX-B');
    expect(stationLineBadgeText('GTX-C'), 'GTX-C');
    expect(stationLineBadgeText('동해선'), '동해');
    expect(stationLineBadgeText('수도권 서해선'), '서해');
    expect(stationLineBadgeText('수도권 경춘선'), '경춘');
    expect(stationLineBadgeText('수도권 경강선'), '경강');
    expect(stationLineBadgeText('대구 대경선'), '대경');
  });

  testWidgets('2.0x 초고배율 텍스트 스케일 환경에서도 배지 및 탭에 레이아웃 overflow가 없다', (
    tester,
  ) async {
    const singleLine = StationSearchLine(
      id: 'seoul-4',
      name: '수도권 4호선',
      color: '#00A5DE',
      stationCode: '448',
    );
    const multiLine = StationSearchLine(
      id: 'suin-bundang',
      name: '수도권 수인분당선',
      color: '#FABE00',
      stationCode: 'K210',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: Row(
              children: [
                StationLineBadge(line: singleLine, size: 28),
                StationLineBadge(line: multiLine, size: 28),
                StationLineBadgeTab(
                  line: singleLine,
                  selected: true,
                  onTap: () {},
                  size: 28,
                ),
                StationLineBadgeTab(
                  line: multiLine,
                  selected: false,
                  onTap: () {},
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'NearbyStationLineBar는 장문 역명 및 다글자 배지 결합 시 320dp 좁은 화면에서도 overflow 없이 렌더링된다',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: NearbyStationLineBar(
                  stationName: '동대문역사문화공원',
                  leftName: '디지털미디어시티',
                  rightName: '국립중앙박물관',
                  badgeText: '경의중앙',
                  lineColor: const Color(0xFF77C4A3),
                  onStationNameTap: () {},
                  onLeftNameTap: () {},
                  onRightNameTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('동대문역사문화공원'), findsOneWidget);
      expect(find.text('디지털미디어시티'), findsOneWidget);
      expect(find.text('국립중앙박물관'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    },
  );
}
