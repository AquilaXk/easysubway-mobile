import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/journey/data/journey_api_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

// 서버가 실제로 내는 응답 형태로 생성 디코더를 검증한다(#438).
// 기존 테스트는 생성 모델의 toJson으로 응답을 만들어 디코더와 같은 키 목록을
// 공유했다. 그래서 디코더가 계약 필드를 빠뜨려도 잡지 못했다. 이 fixture는
// 생성 코드와 독립인 backend 응답 형태다.
//
// - search-success.backend-main.json: backend main(#471 병합·배포, 83e6b51e)
//   `JourneySearchResponseMapperTest`가 고정한 wire 형태. 요청 정책만 표준
//   검색(STANDARD/NONE)으로 바꿨고, #455 이후 서버가 내지 않는 ENTRY/EXIT
//   구간 대신 RIDE-TRANSFER-RIDE로 구성했다. #471 필드
//   (`stairFreeAlternative`, `alternativeCategories`)를 담는다.
// - search-success.pre-pr471.json: #471 이전 형태(`stairFreeAlternative` 없음).
//   #471은 운영에 배포됐으므로 이제 거부한다(#441).
// - station-timetable-success.backend-main.json: backend main(#479 병합·배포)
//   역 시간표 형태(`nextStationId`, null `directionName`, `terminalStationId`).
// - station-timetable-success.pre-pr479.json: #479 이전 형태. 이제 거부한다.
Map<String, Object?> _fixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/contracts/api/journey_v3/$name',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

class _StubApiClient extends ApiClient {
  _StubApiClient(this._body)
    : super(baseUri: Uri.parse('https://journey.example.test'));

  final Map<String, Object?> _body;

  @override
  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async => ApiResponse(statusCode: 200, jsonBody: _body);
}

final _standardSearchRequest = JourneySearchRequest(
  requestId: '01K1Y000000000000000000000',
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
  walkingPace: WalkingPace.standard,
  mobilityProfile: MobilityProfile.standard,
  constraintMode: ConstraintMode.none,
  maxTransfers: 3,
  alternativeCount: 2,
);

void main() {
  group('Journey V3 search success wire shape', () {
    test('backend main 응답(serviceDayCutoff 포함)을 해석한다', () {
      final json = _fixture('search-success.backend-main.json');

      expect(() => JourneySearchSuccess.fromJson(json), returnsNormally);
    });

    test('backend main 응답이 저장소 검색 경로에서 프로토콜 실패가 되지 않는다', () async {
      final repository = JourneyApiRepository(
        _StubApiClient(_fixture('search-success.backend-main.json')),
      );

      await expectLater(
        repository.searchJourneys(
          _standardSearchRequest,
          sessionToken: 'session-token',
        ),
        completes,
      );
    });

    test('#471은 배포됐으므로 stairFreeAlternative가 없는 이전 형태는 거부한다', () {
      final json = _fixture('search-success.pre-pr471.json');

      expect(
        () => JourneySearchSuccess.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('serviceDayCutoff 값을 그대로 담는다', () {
      final success = JourneySearchSuccess.fromJson(
        _fixture('search-success.backend-main.json'),
      );

      expect(success.serviceDayCutoff, '03:00');
    });

    test('serviceDayCutoff는 배포된 필수 필드라 빠지거나 다른 값이면 거부한다', () {
      final missing = _fixture('search-success.backend-main.json')
        ..remove('serviceDayCutoff');
      final changed = _fixture('search-success.backend-main.json')
        ..['serviceDayCutoff'] = '04:00';

      expect(
        () => JourneySearchSuccess.fromJson(missing),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JourneySearchSuccess.fromJson(changed),
        throwsA(isA<FormatException>()),
      );
    });

    test('#471 계단 없는 대안 결과와 대표 묶음을 해석한다', () {
      final success = JourneySearchSuccess.fromJson(
        _fixture('search-success.backend-main.json'),
      );

      expect(
        success.stairFreeAlternative?.status,
        JourneyStairFreeAlternativeStatus.included,
      );
      expect(
        success.stairFreeAlternative?.facilityStatus,
        JourneyStairFreeFacilityStatus.unobserved,
      );
      expect(success.journeys.map((j) => j.alternativeCategories), [
        [
          JourneyAlternativeCategory.fastest,
          JourneyAlternativeCategory.stairFree,
        ],
        [JourneyAlternativeCategory.fewestTransfers],
      ]);
    });

    test('#471 필드도 누락·계약 밖 값·키·null은 거부한다', () {
      Map<String, Object?> pr471() =>
          _fixture('search-success.backend-main.json');
      List<Map<String, Object?>> journeys(Map<String, Object?> json) =>
          (json['journeys']! as List).cast<Map<String, Object?>>();
      final cases = <String, Map<String, Object?>>{
        'stairFreeAlternative missing': pr471()..remove('stairFreeAlternative'),
        'stairFreeAlternative null': pr471()..['stairFreeAlternative'] = null,
        'stairFreeAlternative extra key': pr471()
          ..['stairFreeAlternative'] = {
            'status': 'INCLUDED',
            'facilityStatus': 'APPLIED',
            'note': 'x',
          },
        'unknown status': pr471()
          ..['stairFreeAlternative'] = {
            'status': 'MAYBE',
            'facilityStatus': 'APPLIED',
          },
        'duplicate category': (() {
          final json = pr471();
          journeys(json).first['alternativeCategories'] = [
            'FASTEST',
            'FASTEST',
          ];
          return json;
        })(),
        'unknown category': (() {
          final json = pr471();
          journeys(json).first['alternativeCategories'] = ['CHEAPEST'];
          return json;
        })(),
        'null categories': (() {
          final json = pr471();
          journeys(json).first['alternativeCategories'] = null;
          return json;
        })(),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          () => JourneySearchSuccess.fromJson(value),
          throwsA(isA<FormatException>()),
          reason: key,
        );
      }
    });

    test('대표 묶음 규칙을 어기는 응답은 저장소에서 프로토콜 실패로 거부한다', () async {
      List<Map<String, Object?>> journeys(Map<String, Object?> json) =>
          (json['journeys']! as List).cast<Map<String, Object?>>();
      Map<String, Object?> pr471() =>
          _fixture('search-success.backend-main.json');
      final cases = <String, Map<String, Object?>>{
        // 계단 있는 여정에 계단회피 묶음을 붙이면 안 된다.
        'STAIR_FREE on stairs journey': (() {
          final json = pr471();
          journeys(json)[1]['alternativeCategories'] = [
            'FEWEST_TRANSFERS',
            'STAIR_FREE',
          ];
          journeys(json)[0]['alternativeCategories'] = ['FASTEST'];
          return json;
        })(),
        'same category twice': (() {
          final json = pr471();
          journeys(json)[1]['alternativeCategories'] = ['FASTEST'];
          return json;
        })(),
        'no FASTEST': (() {
          final json = pr471();
          journeys(json)[0]['alternativeCategories'] = ['STAIR_FREE'];
          return json;
        })(),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final repository = JourneyApiRepository(_StubApiClient(value));
        await expectLater(
          repository.searchJourneys(
            _standardSearchRequest,
            sessionToken: 'session-token',
          ),
          throwsA(isA<JourneyProtocolFailure>()),
          reason: key,
        );
      }
      await expectLater(
        JourneyApiRepository(
          _StubApiClient(pr471()),
        ).searchJourneys(_standardSearchRequest, sessionToken: 'session-token'),
        completes,
      );
    });

    test('대표 묶음이 일부 여정에만 있어도 계약 위반이 아니라 받는다(#438 리뷰 F6)', () async {
      // 계약(backend #471 Journey.alternativeCategories)은 여정마다 선택 필드이고
      // "모든 여정에 있다"는 규칙이 없다. 계약보다 엄격하면 정상 응답을 거부한다.
      final json = _fixture('search-success.backend-main.json');
      ((json['journeys']! as List).cast<Map<String, Object?>>())[1].remove(
        'alternativeCategories',
      );

      await expectLater(
        JourneyApiRepository(
          _StubApiClient(json),
        ).searchJourneys(_standardSearchRequest, sessionToken: 'session-token'),
        completes,
      );
    });

    test('계약에 없는 최상위 키는 계속 거부한다', () {
      final json = _fixture('search-success.backend-main.json')
        ..['debugTrace'] = 'x';

      expect(
        () => JourneySearchSuccess.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Station timetable success wire shape', () {
    test('backend main 형태(다음 정차역·종착역, 방면 이름 null)를 해석한다', () {
      final json = _fixture('station-timetable-success.backend-main.json');

      expect(
        () => StationTimetableSearchSuccess.fromJson(json),
        returnsNormally,
      );
    });

    test('#479는 배포됐으므로 다음 정차역·종착역이 없는 이전 형태는 거부한다', () {
      final json = _fixture('station-timetable-success.pre-pr479.json');

      expect(
        () => StationTimetableSearchSuccess.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('#479 다음 정차역·종착역을 담고 방면 이름 null을 그대로 둔다', () {
      final success = StationTimetableSearchSuccess.fromJson(
        _fixture('station-timetable-success.backend-main.json'),
      );

      expect(success.directionGroups.map((g) => g.nextStationId), [
        'station-yeoksam',
        'station-gyodae',
      ]);
      expect(success.directionGroups.map((g) => g.directionName), [
        isNull,
        isNull,
      ]);
      expect(
        success.directionGroups.first.departures.map(
          (d) => d.terminalStationId,
        ),
        ['station-seongsu', 'station-seongsu'],
      );
    });

    test('#479 필드도 null·빈 값·계약 밖 키·directionName 누락은 거부한다', () {
      Map<String, Object?> group(Map<String, Object?> json) =>
          (json['directionGroups']! as List).cast<Map<String, Object?>>().first;
      Map<String, Object?> pr479() =>
          _fixture('station-timetable-success.backend-main.json');
      final cases = <String, Map<String, Object?>>{
        'nextStationId null': (() {
          final json = pr479();
          group(json)['nextStationId'] = null;
          return json;
        })(),
        'nextStationId blank': (() {
          final json = pr479();
          group(json)['nextStationId'] = ' ';
          return json;
        })(),
        'nextStationId missing': (() {
          final json = pr479();
          group(json).remove('nextStationId');
          return json;
        })(),
        'terminalStationId missing': (() {
          final json = pr479();
          (group(json)['departures']! as List)
              .cast<Map<String, Object?>>()
              .first
              .remove('terminalStationId');
          return json;
        })(),
        'directionName missing': (() {
          final json = pr479();
          group(json).remove('directionName');
          return json;
        })(),
        'terminalStationId null': (() {
          final json = pr479();
          (group(json)['departures']! as List)
                  .cast<Map<String, Object?>>()
                  .first['terminalStationId'] =
              null;
          return json;
        })(),
        'group extra key': (() {
          final json = pr479();
          group(json)['directionCode'] = 'UP';
          return json;
        })(),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          () => StationTimetableSearchSuccess.fromJson(value),
          throwsA(isA<FormatException>()),
          reason: key,
        );
      }
    });
  });
}
