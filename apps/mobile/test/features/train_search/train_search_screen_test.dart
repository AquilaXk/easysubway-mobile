import 'dart:async';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_models.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_scope_policy.dart';
import 'package:easysubway_mobile/features/train_search/presentation/train_search_screen.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

class _FakeTrainSearchRepository implements TrainSearchRepository {
  _FakeTrainSearchRepository({
    this.stationsCompleter,
    this.stationError,
    this.searchCompleter,
    this.error,
    TrainSearchResult? result,
  }) : result = result ?? _result();

  final Completer<List<TrainStation>>? stationsCompleter;
  TrainSearchException? stationError;
  final Completer<TrainSearchResult>? searchCompleter;
  final TrainSearchException? error;
  final TrainSearchResult result;
  var searchCalls = 0;
  var stationCalls = 0;
  TrainSearchCriteria? lastCriteria;

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) async {
    stationCalls++;
    if (stationError case final TrainSearchException error) throw error;
    if (stationsCompleter case final Completer<List<TrainStation>> completer) {
      return completer.future;
    }
    if (query.contains('서울')) {
      return const [TrainStation(id: 'NAT010000', name: '서울')];
    }
    if (query.contains('대전')) {
      return const [TrainStation(id: 'NAT011668', name: '대전')];
    }
    return const [];
  }

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) async {
    searchCalls++;
    lastCriteria = criteria;
    if (error case final TrainSearchException error) throw error;
    if (searchCompleter case final Completer<TrainSearchResult> completer) {
      return completer.future;
    }
    return result;
  }
}

TrainSearchResult _result() => TrainSearchResult(
  observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
  outbound: [
    TrainJourney(
      trainNumber: '101',
      trainType: TrainSearchTrainType.ktx,
      departureStationId: 'NAT010000',
      departureStationName: '서울',
      departureAt: DateTime.parse('2026-07-20T09:00:00+09:00'),
      arrivalStationId: 'NAT011668',
      arrivalStationName: '대전',
      arrivalAt: DateTime.parse('2026-07-20T10:02:00+09:00'),
      durationMinutes: 62,
      adultFareWon: 23700,
    ),
  ],
  inbound: const [],
);

Future<void> _selectStations(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('trainSearchDepartureField')),
    '서울',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(
    find.byKey(const Key('trainSearchStationSuggestion-departure-NAT010000')),
  );
  await tester.enterText(
    find.byKey(const Key('trainSearchArrivalField')),
    '대전',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(
    find.byKey(const Key('trainSearchStationSuggestion-arrival-NAT011668')),
  );
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('trainSearchScrollView')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.byKey(const Key('trainSearchSubmitButton')),
    240,
    scrollable: scrollable,
  );
  await tester.ensureVisible(find.byKey(const Key('trainSearchSubmitButton')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('trainSearchSubmitButton')));
}

void main() {
  testWidgets('역 선택 후 검색하면 KTX 시간·성인 1인 운임을 표시한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('trainSearchResults')),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('trainSearchScrollView')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(repository.searchCalls, 1);
    expect(find.text('KTX 101'), findsOneWidget);
    expect(find.text('23,700원'), findsOneWidget);
    expect(find.text('서울 → 대전'), findsOneWidget);
    expect(find.text('09:00 → 10:02 · 62분'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                '서울 출발, 대전 도착, KTX 101, '
                    '09:00 출발, 10:02 도착, 62분 소요, 성인 1인 23,700원',
      ),
      findsOneWidget,
    );
  });

  testWidgets('한국시간 03시 이후에는 새 service day를 기본 검색일로 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _FakeTrainSearchRepository(),
          now: () => DateTime.utc(2026, 7, 19, 18, 30),
        ),
      ),
    );

    expect(find.text('2026.07.20 (월)'), findsOneWidget);
    expect(find.text('가는 날'), findsOneWidget);
  });

  testWidgets('출발·도착을 바꾸고 왕복 날짜를 검색 조건에 반영한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);

    await tester.tap(find.byKey(const Key('trainSearchSwapButton')));
    await tester.tap(find.text('왕복'));
    await tester.pump();
    expect(
      find.byKey(const Key('trainSearchReturnDateButton')),
      findsOneWidget,
    );

    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(repository.lastCriteria!.departure.name, '대전');
    expect(repository.lastCriteria!.arrival.name, '서울');
    expect(repository.lastCriteria!.returnDate, DateTime(2026, 7, 19));
  });

  testWidgets('왕복 결과는 오는 열차가 없어도 빈 오는 편을 표시한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await tester.tap(find.text('왕복'));
    await tester.pump();
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('오는 열차'), findsOneWidget);
    expect(find.text('운행 열차가 없습니다.'), findsOneWidget);
  });

  testWidgets('자정을 넘는 열차는 다음 날 도착을 화면과 semantics에 표시한다', (tester) async {
    final overnight = TrainSearchResult(
      observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
      outbound: [
        TrainJourney(
          trainNumber: '999',
          trainType: TrainSearchTrainType.ktx,
          departureStationId: 'NAT010000',
          departureStationName: '서울',
          departureAt: DateTime.parse('2026-07-20T23:30:00+09:00'),
          arrivalStationId: 'NAT011668',
          arrivalStationName: '대전',
          arrivalAt: DateTime.parse('2026-07-21T00:30:00+09:00'),
          durationMinutes: 60,
          adultFareWon: 23700,
        ),
      ],
      inbound: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _FakeTrainSearchRepository(result: overnight),
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('23:30 → 다음 날 00:30 · 60분'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.contains(
                  '23:30 출발, 다음 날 00:30 도착, 60분 소요',
                ) ==
                true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('역 교환은 진행 중인 자동완성 응답을 무효화한다', (tester) async {
    final completer = Completer<List<TrainStation>>();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _FakeTrainSearchRepository(stationsCompleter: completer),
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('trainSearchDepartureField')),
      '서울',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('trainSearchSwapButton')));
    completer.complete(const [TrainStation(id: 'NAT010000', name: '서울')]);
    await tester.pump();

    expect(
      find.byKey(const Key('trainSearchStationSuggestion-departure-NAT010000')),
      findsNothing,
    );
  });

  testWidgets('역 자동완성은 마지막 입력만 300ms 뒤 조회한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    final field = find.byKey(const Key('trainSearchDepartureField'));
    await tester.enterText(field, '서울');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(field, '서울역');
    await tester.pump(const Duration(milliseconds: 299));

    expect(repository.stationCalls, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.stationCalls, 1);
  });

  testWidgets('역 자동완성 오류는 입력란에서 안내하고 다시 조회한다', (tester) async {
    final repository = _FakeTrainSearchRepository(
      stationError: const TrainSearchException(
        TrainSearchFailureKind.network,
        '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('trainSearchDepartureField')),
      '서울',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.stationCalls, 1);
    expect(find.byKey(const Key('trainSearchError')), findsNothing);
    expect(find.byKey(const Key('trainSearchRetryButton')), findsNothing);
    expect(
      find.byKey(const Key('trainSearchStationError-departure')),
      findsOneWidget,
    );
    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);

    repository.stationError = null;
    await tester.tap(
      find.byKey(const Key('trainSearchStationRetry-departure')),
    );
    await tester.pump();

    expect(repository.stationCalls, 2);
    expect(
      find.byKey(const Key('trainSearchStationSuggestion-departure-NAT010000')),
      findsOneWidget,
    );
  });

  testWidgets('제출 직전 지난 service day를 오늘로 갱신하고 재확인을 요구한다', (tester) async {
    var now = DateTime.utc(2026, 7, 19, 3);
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(repository: repository, now: () => now),
      ),
    );
    await _selectStations(tester);

    now = DateTime.utc(2026, 7, 20, 3);
    await _tapSubmit(tester);
    await tester.pump();

    expect(repository.searchCalls, 0);
    expect(find.text('가는 날이 지나 오늘로 변경했습니다. 날짜를 확인해 주세요.'), findsOneWidget);
    expect(find.text('2026.07.20 (월)'), findsOneWidget);
    expect(find.text('가는 날'), findsOneWidget);
  });

  testWidgets('검색 중 중복 제출을 막고 loading 상태를 알린다', (tester) async {
    final completer = Completer<TrainSearchResult>();
    final repository = _FakeTrainSearchRepository(searchCompleter: completer);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);

    await _tapSubmit(tester);
    await tester.pump();
    await tester.tap(find.byKey(const Key('trainSearchSubmitButton')));
    await tester.pump();

    expect(repository.searchCalls, 1);
    expect(find.byKey(const Key('trainSearchLoading')), findsOneWidget);
    completer.complete(_result());
    await tester.pumpAndSettle();
  });

  testWidgets('unavailable은 이전 결과 없이 명시적 오류와 재시도를 표시한다', (tester) async {
    final repository = _FakeTrainSearchRepository(
      error: const TrainSearchException(
        TrainSearchFailureKind.unavailable,
        '기차 검색을 일시적으로 사용할 수 없습니다.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trainSearchError')), findsOneWidget);
    expect(find.text('기차 검색을 일시적으로 사용할 수 없습니다.'), findsOneWidget);
    expect(find.text('KTX 101'), findsNothing);
  });

  testWidgets('검색 결과가 없으면 empty 상태를 명시한다', (tester) async {
    final repository = _FakeTrainSearchRepository(
      result: TrainSearchResult(
        observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
        outbound: const [],
        inbound: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trainSearchEmpty')), findsOneWidget);
  });

  testWidgets('200% 글자 크기에서도 검색 폼과 결과가 overflow 없이 스크롤된다', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: TrainSearchScreen(
            repository: _FakeTrainSearchRepository(),
            now: () => DateTime.utc(2026, 7, 19, 3),
          ),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsWidgets);
  });

  testWidgets('노선도 메뉴의 역 검색 바로 아래 기차 검색이 callback을 연다', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: const _EmptyNetworkMapRepository(),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: (_, _) {},
          onOpenTrainSearch: () => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();

    final stationSearch = tester.getTopLeft(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    final train = tester.getTopLeft(
      find.byKey(const Key('networkMapMenuTrainSearchButton')),
    );
    expect(train.dy, greaterThan(stationSearch.dy));

    await tester.tap(find.byKey(const Key('networkMapMenuTrainSearchButton')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('가는 날 탭 시 입력 포커스를 해제하고 즉시 캘린더 피커를 띄운다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 출발역 텍스트 입력으로 포커스 활성화
    await tester.enterText(
      find.byKey(const Key('trainSearchDepartureField')),
      '서',
    );
    await tester.pump();

    // 날짜 버튼 탭
    await tester.tap(find.byKey(const Key('trainSearchDepartureDateButton')));
    await tester.pumpAndSettle();

    // 캘린더 DatePickerDialog가 열려야 함
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('기차 카드 탭 시 Screen 3 기차 시간표 및 운임 모달이 열리고 탭 전환이 동작한다', (
    tester,
  ) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    // 카드 탭 -> 모달 열림
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    final cardFinder = find.byKey(
      const Key('trainSearchJourneyCard-outbound-101'),
    );
    await tester.scrollUntilVisible(cardFinder, 200, scrollable: scrollable);
    await tester.ensureVisible(cardFinder);
    await tester.pumpAndSettle();

    await tester.tap(cardFinder);
    await tester.pumpAndSettle();

    expect(find.text('기차 시간표 · 운임'), findsOneWidget);
    expect(find.text('KTX 101'), findsWidgets);
    expect(find.text('기차 시각'), findsOneWidget);
    expect(find.text('운임요금'), findsOneWidget);
    expect(find.text('정차역'), findsOneWidget);
    expect(find.text('출발역'), findsOneWidget);
    expect(find.text('도착역'), findsOneWidget);

    // 운임요금 탭 전환
    await tester.tap(find.text('운임요금'));
    await tester.pumpAndSettle();

    expect(find.text('일반실 (어른)'), findsOneWidget);
    expect(find.text('특실 / 우등실 (어른)'), findsOneWidget);
    expect(find.text('어린이 (만 6~12세)'), findsOneWidget);
    expect(find.text('경로 (만 65세 이상, 평일)'), findsOneWidget);
  });

  testWidgets('Screen 2 열차종 필터 칩을 탭하면 결과 목록이 필터링된다', (tester) async {
    final multiResult = TrainSearchResult(
      observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
      outbound: [
        TrainJourney(
          trainNumber: '101',
          trainType: TrainSearchTrainType.ktx,
          departureStationId: 'NAT010000',
          departureStationName: '서울',
          departureAt: DateTime.parse('2026-07-20T09:00:00+09:00'),
          arrivalStationId: 'NAT011668',
          arrivalStationName: '대전',
          arrivalAt: DateTime.parse('2026-07-20T10:02:00+09:00'),
          durationMinutes: 62,
          adultFareWon: 23700,
        ),
        TrainJourney(
          trainNumber: '665',
          trainType: TrainSearchTrainType.srt,
          departureStationId: 'NAT010000',
          departureStationName: '수서',
          departureAt: DateTime.parse('2026-07-20T09:30:00+09:00'),
          arrivalStationId: 'NAT011668',
          arrivalStationName: '대전',
          arrivalAt: DateTime.parse('2026-07-20T10:32:00+09:00'),
          durationMinutes: 62,
          adultFareWon: 20100,
        ),
      ],
      inbound: const [],
    );
    final repository = _FakeTrainSearchRepository(result: multiResult);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('KTX 101'), findsOneWidget);
    expect(find.text('SRT 665'), findsOneWidget);

    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    final ktxChip = find.widgetWithText(InkWell, 'KTX');
    await tester.scrollUntilVisible(ktxChip, 200, scrollable: scrollable);
    await tester.ensureVisible(ktxChip);
    await tester.pumpAndSettle();

    // KTX 탭 선택
    await tester.tap(ktxChip);
    await tester.pumpAndSettle();

    expect(find.text('KTX 101'), findsOneWidget);
    expect(find.text('SRT 665'), findsNothing);

    // SRT 탭 선택
    final srtChip = find.widgetWithText(InkWell, 'SRT');
    await tester.tap(srtChip);
    await tester.pumpAndSettle();

    expect(find.text('KTX 101'), findsNothing);
    expect(find.text('SRT 665'), findsOneWidget);

    // 전체 탭 선택
    final allChip = find.widgetWithText(InkWell, '전체');
    await tester.tap(allChip);
    await tester.pumpAndSettle();

    expect(find.text('KTX 101'), findsOneWidget);
    expect(find.text('SRT 665'), findsOneWidget);
  });

  testWidgets('Screen 2 날짜 이동 화살표를 탭하면 다음 날로 검색일이 이동한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    final nextBtn = find.byKey(const Key('trainSearchNextDayButton'));
    await tester.scrollUntilVisible(nextBtn, 200, scrollable: scrollable);
    await tester.ensureVisible(nextBtn);
    await tester.pumpAndSettle();

    expect(find.text('2026.07.19'), findsWidgets);

    // 다음 날 탭
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    expect(find.text('2026.07.20'), findsWidgets);
    expect(repository.searchCalls, 2);

    // 이전 날 탭
    final prevBtn = find.byKey(const Key('trainSearchPrevDayButton'));
    await tester.tap(prevBtn);
    await tester.pumpAndSettle();

    expect(find.text('2026.07.19'), findsWidgets);
    expect(repository.searchCalls, 3);
  });

  testWidgets('화면 타이틀이 기차 조회로 노출되고 배너 슬롭 문구 및 시외교통·승차권·어른1명·일반좌석이 제거된다', (
    tester,
  ) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 화면 타이틀 확인 (AppBar에 1개만 단독 노출 및 배너 슬롭 문구 제거)
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, EasySubwayAccessibleColors.primary);
    expect(appBar.foregroundColor, Colors.white);
    expect(appBar.toolbarHeight, 60);
    expect(appBar.elevation, 0);

    expect(find.text('기차 조회'), findsOneWidget);
    final titleWidget = tester.widget<Text>(find.text('기차 조회'));
    expect(titleWidget.style?.color, Colors.white);
    expect(titleWidget.style?.fontSize, 22);
    expect(titleWidget.style?.fontWeight, FontWeight.bold);
    expect(find.text('전국 열차 시간표와 운임을 간편하게 조회하세요'), findsNothing);

    // 제거된 TMI / 예매 옵션 확인
    expect(find.text('시외교통'), findsNothing);
    expect(find.text('기차 조회 · 예매'), findsNothing);
    expect(find.text('승차권'), findsNothing);
    expect(find.text('일정 · 인원 선택'), findsNothing);
    expect(find.text('일정 선택'), findsOneWidget);
    expect(find.text('어른 1명'), findsNothing);
    expect(find.text('일반좌석'), findsNothing);
  });

  testWidgets('일정 선택 섹션에서 가는 날과 열차종류가 통일된 행 형태와 구분자(ㅣ)로 노출된다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 라벨, 구분자(ㅣ), 기본 선택값 확인
    expect(find.text('가는 날'), findsOneWidget);
    expect(find.text('2026.07.19 (일)'), findsOneWidget);
    expect(find.text('열차종류'), findsOneWidget);
    expect(find.text('전체 열차'), findsOneWidget);
    expect(find.text('ㅣ'), findsNWidgets(2));

    // 구분자(ㅣ)의 가로 위치(dx)가 행 간에 정확히 일치하여 수직 정렬됨을 검증
    final dividerGoingDay = tester.getTopLeft(find.text('ㅣ').at(0));
    final dividerTrainType = tester.getTopLeft(find.text('ㅣ').at(1));
    expect(dividerGoingDay.dx, equals(dividerTrainType.dx));

    // 왕복 활성화 시 오는 날도 동일한 형태로 노출 및 구분자 수직 정렬 검증
    await tester.tap(find.text('왕복'));
    await tester.pump();
    expect(find.text('오는 날'), findsOneWidget);
    expect(find.text('ㅣ'), findsNWidgets(3));

    final dividerReturnDay = tester.getTopLeft(find.text('ㅣ').at(1));
    final dividerTrainTypeRound = tester.getTopLeft(find.text('ㅣ').at(2));
    expect(dividerReturnDay.dx, equals(dividerGoingDay.dx));
    expect(dividerTrainTypeRound.dx, equals(dividerGoingDay.dx));
  });

  testWidgets('출발 및 도착 카드와 일정 선택 영역의 폰트 크기, 힌트 텍스트 및 스왑 시맨틱스가 강화된다', (
    tester,
  ) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 출발·도착 라벨 18pt bold 확인
    final departLabel = tester.widget<Text>(find.text('출발'));
    expect(departLabel.style?.fontSize, 18);
    expect(departLabel.style?.fontWeight, FontWeight.bold);

    final arriveLabel = tester.widget<Text>(find.text('도착'));
    expect(arriveLabel.style?.fontSize, 18);
    expect(arriveLabel.style?.fontWeight, FontWeight.bold);

    // 출발·도착 입력창 힌트 텍스트 확인
    final departField = tester.widget<TextField>(
      find.byKey(const Key('trainSearchDepartureField')),
    );
    expect(departField.decoration?.hintText, '출발역 입력');
    expect(departField.style?.fontSize, 20);

    final arriveField = tester.widget<TextField>(
      find.byKey(const Key('trainSearchArrivalField')),
    );
    expect(arriveField.decoration?.hintText, '도착역 입력');
    expect(arriveField.style?.fontSize, 20);

    // 스왑 버튼 시맨틱스 및 툴팁 확인
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == '출발역과 도착역 맞바꾸기',
      ),
      findsOneWidget,
    );

    // 일정 선택 헤더 18pt w700 확인
    final scheduleHeader = tester.widget<Text>(find.text('일정 선택'));
    expect(scheduleHeader.style?.fontSize, 18);
    expect(scheduleHeader.style?.fontWeight, FontWeight.w700);

    // 일정 선택 행 라벨 16pt w700, 값 16pt w700 확인
    final goingLabel = tester.widget<Text>(find.text('가는 날'));
    expect(goingLabel.style?.fontSize, 16);
    expect(goingLabel.style?.fontWeight, FontWeight.w700);

    final goingValue = tester.widget<Text>(find.text('2026.07.19 (일)'));
    expect(goingValue.style?.fontSize, 16);
    expect(goingValue.style?.fontWeight, FontWeight.w700);

    // 시간표 조회 버튼 높이 54 확인
    final submitBox = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byKey(const Key('trainSearchSubmitButton')),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(submitBox.height, 54);
  });

  testWidgets('열차종류 탭 시 바텀시트가 열리고 열차종을 선택하면 조건에 반영된다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 열차종류 행 탭
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeField')));
    await tester.pumpAndSettle();

    // 바텀시트 노출 확인
    expect(find.text('열차종류 선택'), findsOneWidget);
    expect(
      find.byKey(const Key('trainSearchTrainTypeOption-KTX')),
      findsOneWidget,
    );

    // KTX 선택
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeOption-KTX')));
    await tester.pumpAndSettle();

    // 열차종류 행에 KTX 반영 확인
    expect(find.text('KTX'), findsOneWidget);

    // 검색 실행 후 criteria에 KTX가 전달되었는지 확인
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(repository.searchCalls, 1);
    expect(repository.lastCriteria?.trainType, TrainSearchTrainType.ktx);
  });

  testWidgets('시간표 조회 결과 카드 및 모달에서 코레일+ 연동(URL Scheme)이 동작한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    final launchedUrls = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
          onLaunchUrl: (uri) async {
            launchedUrls.add(uri);
            return true;
          },
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    // 결과 카드 내 코레일+ 버튼 확인 및 탭
    final korailButton = find.byKey(
      const Key('trainSearchKorailTalkButton-101'),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(korailButton, 200, scrollable: scrollable);
    await tester.ensureVisible(korailButton);
    await tester.pumpAndSettle();

    expect(find.text('코레일+'), findsOneWidget);
    await tester.tap(korailButton);
    await tester.pumpAndSettle();

    expect(launchedUrls, hasLength(1));
    expect(launchedUrls.single.scheme, 'korailtalk');

    // 상세 모달 열기
    final cardFinder = find.byKey(
      const Key('trainSearchJourneyCard-outbound-101'),
    );
    await tester.tap(cardFinder);
    await tester.pumpAndSettle();

    // 모달 내 코레일+ 에서 예매 CTA 확인 및 탭
    final modalCta = find.byKey(const Key('trainModalKorailTalkButton'));
    expect(modalCta, findsOneWidget);
    expect(find.text('코레일+ 에서 예매'), findsOneWidget);

    await tester.tap(modalCta);
    await tester.pumpAndSettle();

    expect(launchedUrls, hasLength(2));
    expect(launchedUrls.last.scheme, 'korailtalk');
  });

  testWidgets('코레일+ 앱 스킴 실패 시 모바일 웹(https://m.korail.com)으로 fallback 연동된다', (
    tester,
  ) async {
    final repository = _FakeTrainSearchRepository();
    final launchedUrls = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
          onLaunchUrl: (uri) async {
            launchedUrls.add(uri);
            // Return false for app schemes so it falls back to webUrl
            return uri.scheme == 'https';
          },
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    final korailButton = find.byKey(
      const Key('trainSearchKorailTalkButton-101'),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(korailButton, 200, scrollable: scrollable);
    await tester.ensureVisible(korailButton);
    await tester.pumpAndSettle();

    await tester.tap(korailButton);
    await tester.pumpAndSettle();

    expect(
      launchedUrls.map((u) => u.toString()),
      contains('https://m.korail.com'),
    );
  });

  testWidgets('onLaunchUrl 실패 시 스낵바가 실행된다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
          onLaunchUrl: (_) async => false,
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    final korailButton = find.byKey(
      const Key('trainSearchKorailTalkButton-101'),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(korailButton, 200, scrollable: scrollable);
    await tester.ensureVisible(korailButton);
    await tester.pumpAndSettle();

    await tester.tap(korailButton);
    await tester.pumpAndSettle();

    expect(find.text('코레일+ 또는 예매 페이지를 열 수 없습니다.'), findsOneWidget);
  });

  testWidgets('열차 종류 필터 모달에서 KTX 및 전체 열차 선택과 닫기가 정상 동작한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    // 필터 열기
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeField')));
    await tester.pumpAndSettle();

    // 닫기 버튼 탭
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeCloseButton')));
    await tester.pumpAndSettle();

    // 다시 열고 KTX 선택
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeField')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeOption-KTX')));
    await tester.pumpAndSettle();

    // 다시 열고 전체 열차 선택
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeField')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.byKey(const Key('trainSearchTrainTypeOption-ALL')));
    await tester.pumpAndSettle();
  });

  testWidgets('왕복 모드에서 오는 날짜 탭 및 열차 상세 모달 닫기가 동작한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    // 왕복 탭
    await tester.tap(find.byKey(const Key('trainSearchTripType')));
    await tester.pumpAndSettle();

    // 오는 날짜 탭
    await tester.tap(find.byKey(const Key('trainSearchReturnDateButton')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // 캘린더 다이얼로그 취소
    final cancelButton = find.text('Cancel');
    if (cancelButton.evaluate().isNotEmpty) {
      await tester.tap(cancelButton);
    } else {
      await tester.tap(find.text('취소'));
    }
    await tester.pumpAndSettle();

    // 조회 후 상세 모달 열고 닫기
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('trainSearchJourneyCard-outbound-101'));
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(card, 200, scrollable: scrollable);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    // 상세 모달 닫기
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });

  testWidgets('SRT 열차 카드 코레일톡/외부앱 연결이 정상 동작한다', (tester) async {
    final launchedUrls = <Uri>[];
    final repo = _FakeTrainSearchRepository(
      result: TrainSearchResult(
        observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
        outbound: [
          TrainJourney(
            trainNumber: '301',
            trainType: TrainSearchTrainType.srt,
            departureStationId: 'NAT010000',
            departureStationName: '수서',
            departureAt: DateTime.parse('2026-07-20T09:00:00+09:00'),
            arrivalStationId: 'NAT011668',
            arrivalStationName: '부산',
            arrivalAt: DateTime.parse('2026-07-20T10:02:00+09:00'),
            durationMinutes: 62,
            adultFareWon: 52000,
          ),
        ],
        inbound: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repo,
          onLaunchUrl: (url) async {
            launchedUrls.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 역 선택 및 조회
    await _selectStations(tester);
    await _tapSubmit(tester);

    final card = find.byKey(const Key('trainSearchJourneyCard-outbound-301'));
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('trainSearchScrollView')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(card, 200, scrollable: scrollable);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();

    // 코레일톡 버튼 탭
    await tester.tap(find.byKey(const Key('trainSearchKorailTalkButton-301')));
    await tester.pumpAndSettle();

    expect(launchedUrls.first.scheme, 'srt');
  });

  testWidgets('왕복 모드에서 다음 날 이동 시 도착일이 출발일 이전이 되면 동기화된다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await tester.tap(find.text('왕복'));
    await tester.pump();
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    // 다음 날 버튼 탭
    await tester.tap(find.byKey(const Key('trainSearchNextDayButton')).first);
    await tester.pumpAndSettle();

    expect(repository.lastCriteria!.departureDate, DateTime(2026, 7, 20));
    expect(repository.lastCriteria!.returnDate, DateTime(2026, 7, 20));
  });

  test(
    'defaultTrainLaunchUrl은 canLaunchUrl 예외 발생 시 안전하게 false를 반환한다',
    () async {
      final result = await defaultTrainLaunchUrl(
        Uri.parse('https://example.com'),
      );
      expect(result, isFalse);
    },
  );

  test(
    'defaultTrainLaunchUrl은 canLaunch가 true일 때 launch를 실행하고 결과를 반환한다',
    () async {
      final result = await defaultTrainLaunchUrl(
        Uri.parse('https://example.com'),
        canLaunch: (uri) async => true,
        launch:
            (uri, {LaunchMode mode = LaunchMode.platformDefault}) async => true,
      );
      expect(result, isTrue);
    },
  );
}

class _EmptyNetworkMapRepository implements NetworkMapRepository {
  const _EmptyNetworkMapRepository();

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return const NetworkMapData(
      regions: [NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: [],
      stations: [],
      edges: [],
      positionSources: [],
    );
  }
}
