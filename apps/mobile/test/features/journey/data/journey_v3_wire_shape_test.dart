import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/journey/data/journey_api_repository.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

// 서버가 실제로 내는 응답 형태로 생성 디코더를 검증한다(#438).
// 기존 테스트는 생성 모델의 toJson으로 응답을 만들어 디코더와 같은 키 목록을
// 공유했다. 그래서 디코더가 계약 필드를 빠뜨려도 잡지 못했다. 이 fixture는
// 생성 코드와 독립인 backend 응답 형태다.
//
// - search-success.backend-main.json: backend main(cd824e1a)
//   `JourneySearchResponseMapperTest`가 고정한 wire 형태. 요청 정책만 표준
//   검색(STANDARD/NONE)으로 바꿨고, #455 이후 서버가 내지 않는 ENTRY/EXIT
//   구간 대신 RIDE-TRANSFER-RIDE로 구성했다.
// - search-success.backend-pr471.json: backend PR #471 브랜치의 같은 테스트가
//   고정한 추가 필드(`stairFreeAlternative`, `alternativeCategories`).
// - station-timetable-success.backend-main.json: 현재 계약의 역 시간표 형태.
// - station-timetable-success.backend-pr479.json: backend PR #479 형태
//   (`nextStationId`, null `directionName`, `terminalStationId`).
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

    test('backend #471 응답(배포 전 추가 필드 포함)도 해석한다', () {
      final json = _fixture('search-success.backend-pr471.json');

      expect(() => JourneySearchSuccess.fromJson(json), returnsNormally);
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
    test('현재 계약 형태를 해석한다', () {
      final json = _fixture('station-timetable-success.backend-main.json');

      expect(() => StationTimetableSearchSuccess.fromJson(json), returnsNormally);
    });

    test('backend #479 형태(다음 정차역·종착역, 방면 이름 null)를 해석한다', () {
      final json = _fixture('station-timetable-success.backend-pr479.json');

      expect(() => StationTimetableSearchSuccess.fromJson(json), returnsNormally);
    });
  });
}
