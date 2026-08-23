import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('503 timetable 오류는 exact code로 보존하고 자동 재시도하지 않는다', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      requestCount++;
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer ${'T' * 43}',
      );
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': false,
            'code': 'ITX_TIMETABLE_UNAVAILABLE',
            'message': 'ITX 시간표를 불러올 수 없어요',
          }),
        );
      await request.response.close();
    });
    final repository = RouteSearchV2ApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      bearerTokenProvider: () async => 'T' * 43,
    );

    await expectLater(
      repository.searchRoute(
        _request(RouteTransportScope.subwayAndItxCheongchun),
      ),
      throwsA(
        isA<RouteSearchOnlineException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.failureReason,
              'failureReason',
              'ITX_TIMETABLE_UNAVAILABLE',
            )
            .having((error) => error.message, 'message', 'ITX 시간표를 불러올 수 없어요'),
      ),
    );
    expect(requestCount, 1);
  });

  test('200 빈 itinerary는 다음 운행 시각을 보존한 blocked 결과로 반환한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'contractVersion': 'ROUTE_SEARCH_V2',
              'originStationId': 'origin',
              'destinationStationId': 'destination',
              'departureTime': '2026-07-01T23:55:00+09:00',
              'mobilityType': 'SENIOR',
              'constraintMode': 'PREFER_STEP_FREE',
              'useRealtime': true,
              'maxTransfers': 3,
              'alternativeCount': 3,
              'statuses': ['NO_TIMETABLE_SERVICE'],
              'nextServiceTime': '2026-07-02T09:00:00+09:00',
              'itineraries': <Object?>[],
            },
          }),
        );
      await request.response.close();
    });
    final repository = RouteSearchV2ApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      bearerTokenProvider: () async => 'T' * 43,
    );

    final result = await repository.searchRoute(
      _request(RouteTransportScope.subwayAndItxCheongchun),
    );

    expect(result.status, 'BLOCKED');
    expect(result.blockedReasons, ['NO_TIMETABLE_SERVICE']);
    expect(result.nextServiceTime, '2026-07-02T09:00:00+09:00');
    expect(result.blockedReasonLabels, [
      '이 시간에는 운행하는 열차가 없어요.',
      '다음 운행 2026-07-02 09:00',
    ]);
    expect(result.supportsRefresh, isFalse);
  });

  test('search 401은 cached session을 무효화하고 자동 재시도하지 않는다', () async {
    var invalidationCount = 0;
    var requestCount = 0;
    final server = await _errorServer(
      statusCode: HttpStatus.unauthorized,
      code: 'ROUTE_SESSION_REQUIRED',
      onRequest: () => requestCount++,
    );
    addTearDown(server.close);
    final repository = RouteSearchV2ApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      bearerTokenProvider: () async => 'T' * 43,
      bearerTokenInvalidator: () => invalidationCount++,
    );

    await expectLater(
      repository.searchRoute(
        _request(RouteTransportScope.subwayAndItxCheongchun),
      ),
      throwsA(
        isA<RouteSearchOnlineException>().having(
          (error) => error.failureReason,
          'failureReason',
          'ROUTE_SESSION_REQUIRED',
        ),
      ),
    );
    expect(requestCount, 1);
    expect(invalidationCount, 1);
  });
}

Future<HttpServer> _errorServer({
  required int statusCode,
  required String code,
  void Function()? onRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onRequest?.call();
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'success': false, 'code': code, 'message': 'error'}));
    await request.response.close();
  });
  return server;
}

RouteSearchRequest _request(RouteTransportScope scope) => RouteSearchRequest(
  originStationId: 'origin',
  destinationStationId: 'destination',
  mobilityType: 'SENIOR',
  transportScope: scope,
);
