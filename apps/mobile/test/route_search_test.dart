import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('경로 검색 결과는 확인 필요 상태를 이동 가능으로 안내하지 않는다', () {
    final result = _sampleRouteSearchResult(status: 'REVIEW_REQUIRED');

    expect(result.statusLabel, '경로 상태를 확인하고 있어요');
    expect(result.guidanceLabel, '확인 후 이동');
    expect(result.guidanceIcon, Icons.warning_amber);
    expect(result.semanticLabel, isNot(contains('이동할 수 있는 경로')));
  });

  test('경로 검색 UNKNOWN 상태는 reason이 있어도 blocked workflow로 분기하지 않는다', () {
    final result = _sampleRouteSearchResult(
      status: 'UNKNOWN',
      blockedReasons: const ['ROUTE_GRAPH_UNKNOWN'],
    );

    expect(result.isBlocked, isFalse);
    expect(result.statusLabel, '경로 상태를 확인하고 있어요');
    expect(result.guidanceLabel, '확인 후 이동');
    expect(result.guidanceIcon, Icons.warning_amber);
    expect(result.needsConfirmation, isTrue);
    expect(result.attentionLabel, '살펴볼 내용');
    expect(result.semanticLabel, contains('살펴볼 내용 길이 이어지는지 확인하고 있어요.'));
    expect(result.semanticLabel, isNot(contains('안내 불가 이유')));
    expect(result.semanticLabel, isNot(contains('다음 행동')));
  });

  test('경로 검색 UNKNOWN localized reason은 구체 안내 문구를 유지한다', () {
    final result = _sampleRouteSearchResult(
      status: 'UNKNOWN',
      blockedReasons: const ['경로 연결 정보를 확인할 수 없습니다.'],
    );

    expect(result.isBlocked, isFalse);
    expect(result.blockedReasonLabels, ['길이 이어지는지 확인하고 있어요.']);
    expect(result.semanticLabel, contains('길이 이어지는지 확인하고 있어요.'));
  });

  test('경로 검색 localized reason은 쉬운 문구를 generic으로 바꾸지 않는다', () {
    final result = _sampleRouteSearchResult(
      status: 'BLOCKED',
      blockedReasons: const ['꼭 필요한 시설을 지금 이용하기 어려워요.'],
    );

    expect(result.blockedReasonLabels, ['꼭 필요한 시설을 지금 이용하기 어려워요.']);
    expect(result.semanticLabel, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
    // 면책은 '안전 안내' 한 곳으로 통합됐다. '이동 전 살펴보기' 이중 고지는 제거(#1577).
    expect(result.semanticLabel, contains('안전 안내'));
    expect(result.semanticLabel, isNot(contains('이동 전 살펴보기')));
    expect(result.semanticLabel, isNot(contains('이동 전 확인')));
    expect(result.semanticLabel, isNot(contains('안내할 수 있는 경로를 아직 찾지 못했어요.')));
  });

  test('경로 검색 결과는 주의 안내를 쉬운 문구로 보여준다', () {
    final safeResult = _sampleRouteSearchResult(warnings: const []);
    final warningResult = _sampleRouteSearchResult(
      warnings: const [
        RouteSearchWarning(code: 'ROUTE_GRAPH_UNKNOWN', message: ''),
      ],
    );

    expect(safeResult.attentionLabel, '주의 안내가 없어요');
    expect(warningResult.attentionLabel, '주의 안내 보기');
  });

  test('ETA source 라벨은 상용 claim 전에 무음 또는 실시간 claim으로 떨어지지 않는다', () {
    expect(routeEtaSourceLabels.keys.toSet(), {
      'REALTIME',
      'MIXED',
      'PLANNED',
      'STATIC_BACKEND_ESTIMATE',
      'STATIC_BACKEND_V1',
      'STATIC_LOCAL',
      'STATIC_ESTIMATE',
      'FALLBACK',
      'UNSUPPORTED',
      'STALE',
    });
    expect(routeEtaSourceLabel('REALTIME'), '실시간 도착정보');
    expect(routeEtaSourceLabel('MIXED'), '일부 실시간 도착정보');
    expect(routeEtaSourceLabel('STATIC_BACKEND_ESTIMATE'), '시간표 기준');
    expect(routeEtaSourceLabel('STATIC_ESTIMATE'), '정적 추정');
    expect(routeEtaSourceLabel('UNSUPPORTED'), '실시간 미지원');
    expect(routeEtaSourceLabel('STALE'), '저장된 데이터 기준');
    expect(routeEtaSourceLabel(''), '도착 정보를 확인하고 있어요');
    expect(routeEtaSourceLabel('SERVER_NEW_VALUE'), '도착 정보를 확인하고 있어요');
    expect(routeEtaSourceLabels.values, isNot(contains('실시간 반영')));
    expect(routeEtaSourceLabels.values, isNot(contains('일부 실시간 반영')));
  });

  test('즐겨찾기 경로는 STATIC_ESTIMATE와 누락된 ETA source를 명시한다', () {
    final staticEstimate = FavoriteRoute.fromJson({
      ..._favoriteRouteJson(),
      'etaSource': 'STATIC_ESTIMATE',
    });
    final missingSource = FavoriteRoute.fromJson(_favoriteRouteJson());

    expect(staticEstimate.scoreBasisText, contains('정적 추정'));
    expect(staticEstimate.semanticLabel, contains('정적 추정'));
    expect(missingSource.scoreBasisText, contains('도착 정보를 확인하고 있어요'));
    expect(missingSource.semanticLabel, contains('도착 정보를 확인하고 있어요'));
  });

  test('경로 결과 badge는 ETA, 접근성, 환승 explicit 필드에서 파생된다', () {
    final tightTransfer = _sampleRouteSearchResult(
      etaSource: 'STATIC_ESTIMATE',
      accessibilityRiskLevel: 'HIGH',
      transferSlackSeconds: 45,
      hasOutOfStationTransfer: true,
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'transfer',
          title: '역 밖 환승',
          description: '밖으로 나가 다음 노선으로 갈아탑니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 5,
          distanceMeters: 180,
          includesStairs: false,
          stairAccessState: 'unknown',
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(tightTransfer.badgeLabels, ['정적 추정', '엘리베이터 상태를 살펴봐 주세요', '역 밖 환승']);
    expect(tightTransfer.semanticLabel, contains('정적 추정'));
    expect(tightTransfer.semanticLabel, contains('엘리베이터 상태를 살펴봐 주세요'));
    expect(tightTransfer.semanticLabel, contains('역 밖 환승'));

    final clearTransfer = _sampleRouteSearchResult(
      etaSource: 'PLANNED',
      accessibilityRiskLevel: 'LOW',
      transferSlackSeconds: 180,
      warnings: const [],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'transfer',
          title: '노선 변경 준비',
          description: '다음 노선으로 갈아탑니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 4,
          distanceMeters: 120,
          includesStairs: false,
          stairAccessState: 'stepFree',
          requiresAccessibilityCheck: false,
        ),
      ],
    );

    expect(clearTransfer.badgeLabels, ['시간표 기준', '계단 없는 경로 확인', '환승 여유 충분']);
  });

  test('경로 이동 부담은 warning 없음만으로 낮음이 되지 않는다', () {
    final longWalkingResult = _sampleRouteSearchResult(
      warnings: const [],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '승강장까지 길게 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 18,
          distanceMeters: 1200,
          includesStairs: false,
          stairAccessState: 'stepFree',
          requiresAccessibilityCheck: false,
        ),
      ],
    );
    final uncertainResult = _sampleRouteSearchResult(
      warnings: const [],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 80,
          includesStairs: false,
          stairAccessState: 'unknown',
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(longWalkingResult.guidanceLabel, '안내 가능');
    expect(longWalkingResult.scoreLabel, '이동 부담 높음');
    expect(uncertainResult.guidanceLabel, '안내 가능');
    expect(uncertainResult.scoreLabel, '이동 부담 보통');
  });

  test('경로 검색 결과 음성 안내는 내부 식별자와 운영 출처 값을 읽지 않는다', () {
    final result = _sampleRouteSearchResult(
      recommendationReasons: const [
        '선택된 경로 edge:edge-a-b-local 근거로 안내합니다.',
        'OFFICIAL_FILE',
      ],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          title: '출발역에서 중간역까지 테스트 노선 이동',
          description: '출발역에서 중간역까지 열차를 이용합니다.',
          lineId: 'line-test',
          lineName: '테스트 노선',
          fromStationId: 'station-a',
          toStationId: 'station-b',
          estimatedMinutes: 2,
          distanceMeters: 830,
          includesStairs: false,
          requiresAccessibilityCheck: false,
          actionTitle: '열차 이동',
          actionDetail: '출발역에서 중간역까지 테스트 노선을 이용합니다.',
          reason: '선택된 경로 edge:edge-a-b-local 근거로 안내합니다.',
          evidenceSources: ['edge:edge-a-b-local'],
          timeSource: 'STATIC_ESTIMATE',
          distanceSource: 'MEASURED',
          confidenceLabel: '확인된 정보예요',
        ),
        RouteSearchStep(
          sequence: 2,
          title: '도착역 출구 이동',
          description: 'edge:exit-b line:test STATIC_ESTIMATE',
          lineId: 'line-test',
          lineName: '테스트 노선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 1,
          distanceMeters: 40,
          includesStairs: false,
          requiresAccessibilityCheck: true,
          actionTitle: '출구 이동',
          actionDetail: 'edge:exit-b line:test STATIC_ESTIMATE',
          reason: 'OFFICIAL_FILE',
          evidenceSources: ['edge:exit-b'],
          timeSource: 'STATIC_ESTIMATE',
          distanceSource: 'MEASURED',
          confidenceLabel: '확인된 정보예요',
          stepType: 'exit',
        ),
      ],
    );

    final semanticLabel = result.semanticLabel;
    expect(semanticLabel, contains('선택한 길을 따라 안내합니다.'));
    expect(semanticLabel, contains('도착역에서 계단 없는 출구 동선을 확인합니다.'));
    expect(semanticLabel, isNot(contains('edge:')));
    expect(semanticLabel, isNot(contains('line:')));
    expect(semanticLabel, isNot(contains('OFFICIAL_')));
    expect(semanticLabel, isNot(contains('STATIC_ESTIMATE')));
    expect(semanticLabel, isNot(contains('MEASURED')));
    expect(semanticLabel, isNot(contains('정적 추정')));
    expect(semanticLabel, isNot(contains('측정값')));
  });

  test('경유 스텝 음성 안내는 신뢰도·측정 출처 문구를 읽지 않는다 (#1975)', () {
    // 경유 마커가 신뢰도 문구(confidenceLabel)와 측정 출처를 갖고 있어도 경유
    // 스텝에서는 그 문구가 음성 안내에 새어 나오지 않아야 한다.
    const waypointStep = RouteSearchStep(
      sequence: 2,
      stepType: 'waypoint',
      title: '선릉 경유',
      description: '내리지 않고 이 역을 지나가요',
      lineId: '',
      lineName: '',
      fromStationId: 'station-seolleung',
      toStationId: 'station-seolleung',
      estimatedMinutes: 0,
      distanceMeters: 0,
      includesStairs: false,
      requiresAccessibilityCheck: false,
      timeSource: 'UNKNOWN',
      distanceSource: 'UNKNOWN',
      confidenceLabel: '확인된 정보예요',
    );

    final label = waypointStep.semanticGuidanceLabel;
    expect(label, isNot(contains('확인된 정보예요')));
    expect(label, isNot(contains('확인하고 있어요')));
  });

  test('경로 단계 이동 부담은 긴 거리를 킬로미터로 표시한다', () {
    const step = RouteSearchStep(
      sequence: 2,
      title: '수도권 4호선으로 사당역까지 이동',
      description: '15개 역을 이동합니다. 환승은 없습니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 30,
      distanceMeters: 13500,
      includesStairs: false,
      requiresAccessibilityCheck: false,
    );

    expect(step.burdenLabel, '약 30분 · 13.5km');
  });

  test('경로 단계 이동 부담은 측정 거리 없음 상태를 0m로 표시하지 않는다', () {
    const step = RouteSearchStep(
      sequence: 2,
      title: '수도권 4호선으로 사당역까지 이동',
      description: '15개 역을 이동합니다. 환승은 없습니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 30,
      distanceMeters: 0,
      includesStairs: false,
      requiresAccessibilityCheck: false,
    );

    expect(step.burdenLabel, '약 30분 · 거리 미확인');
  });

  test('경로 단계 이동 부담은 측정 시간 없음 상태를 0분으로 표시하지 않는다', () {
    const step = RouteSearchStep(
      sequence: 2,
      title: '수도권 4호선으로 사당역까지 이동',
      description: '15개 역을 이동합니다. 환승은 없습니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 0,
      distanceMeters: 180,
      includesStairs: false,
      requiresAccessibilityCheck: false,
    );

    expect(step.burdenLabel, '시간 미확인 · 180m');
  });

  test('경로 계단 상태는 unknown을 계단 없음으로 올리지 않는다', () {
    final result = _sampleRouteSearchResult(
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 80,
          includesStairs: false,
          stairAccessState: 'unknown',
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(result.stairAccessLabel, '계단 여부를 확인하고 있어요');
    expect(result.semanticLabel, contains('계단 여부를 확인하고 있어요'));
    expect(result.semanticLabel, isNot(contains('계단 없음')));
  });

  test('경로 계단 상태는 계단 없는 길을 쉬운 문구로 보여준다', () {
    final result = _sampleRouteSearchResult(
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '엘리베이터로 승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 80,
          includesStairs: false,
          stairAccessState: 'stepFree',
          requiresAccessibilityCheck: false,
        ),
      ],
    );

    expect(result.stairAccessLabel, '계단 없는 길이에요');
    expect(result.semanticLabel, contains('계단 없는 길이에요'));
    expect(result.semanticLabel, isNot(contains('계단 없음 확인')));
  });

  test('경로 요약 사실값은 열차 거리와 환승 문구에 의존하지 않는다', () {
    final result = _sampleRouteSearchResult(
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '엘리베이터로 승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 180,
          includesStairs: false,
          requiresAccessibilityCheck: true,
        ),
        RouteSearchStep(
          sequence: 2,
          stepType: 'ride',
          title: '수도권 4호선 이동',
          description: '열차로 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          estimatedMinutes: 30,
          distanceMeters: 10000,
          includesStairs: false,
          requiresAccessibilityCheck: false,
        ),
        RouteSearchStep(
          sequence: 3,
          stepType: 'transfer',
          title: '노선 변경 준비',
          description: '다음 열차 승강장으로 이동합니다.',
          lineId: 'seoul-2',
          lineName: '수도권 2호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 4,
          distanceMeters: 120,
          includesStairs: false,
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(result.walkingDistanceMeters, 300);
    expect(result.transferCount, 1);
    expect(result.estimatedDurationSeconds, 2220);
  });

  test('즐겨찾기 경로 API 저장소는 인증 헤더로 저장과 목록과 삭제를 요청한다', () async {
    final requestedMethods = <String>[];
    final requestedPaths = <String>[];
    final requestedBodies = <String>[];
    final requestedAuthorizations = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethods.add(request.method);
      requestedPaths.add(request.uri.path);
      requestedAuthorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      requestedBodies.add(await utf8.decoder.bind(request).join());

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;

      if (request.method == 'GET') {
        request.response.write(
          jsonEncode({
            'success': true,
            'data': [_favoriteRouteJson()],
          }),
        );
      } else if (request.method == 'POST') {
        request.response.write(
          jsonEncode({'success': true, 'data': _favoriteRouteJson()}),
        );
      } else {
        request.response.write(jsonEncode({'success': true, 'data': null}));
      }
      await request.response.close();
    });

    final repository = FavoriteRouteApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'password',
      ),
    );

    final favorites = await repository.listFavoriteRoutes();
    final saved = await repository.saveFavoriteRoute('route-1');
    await repository.removeFavoriteRoute('route-1');

    expect(requestedMethods, ['GET', 'POST', 'DELETE']);
    expect(requestedPaths, [
      '/api/v1/me/favorites/routes',
      '/api/v1/me/favorites/routes',
      '/api/v1/me/favorites/routes/route-1',
    ]);
    expect(jsonDecode(requestedBodies[1]), {'routeSearchId': 'route-1'});
    expect(requestedAuthorizations, everyElement(startsWith('Basic ')));
    expect(favorites.single.summaryTitle, '상록수에서 사당까지');
    expect(saved.favoriteRouteId, 'route-1');
    expect(saved.mobilityLabel, '천천히');
    // 플레이스홀더(score/이동·접근성 메트릭) 문구는 카드·시맨틱에서 제거됐다(#1488).
    expect(saved.semanticLabel, contains('상록수에서 사당까지'));
    expect(saved.semanticLabel, isNot(contains('92점')));
    expect(saved.semanticLabel, isNot(contains('아직 알 수 없어요')));
  });

  test('경로 피드백 API 저장소는 익명 사용자 식별자와 평가를 전송한다', () async {
    late Uri requestedUri;
    late String requestedBody;
    late String? requestedAuthorization;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedUri = request.uri;
      requestedAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      requestedBody = await utf8.decoder.bind(request).join();

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'feedbackId': 'route-feedback-1',
              'routeSearchId': 'route-1',
              'userId': 'anonymous-user-1',
              'rating': 'HELPFUL',
              'comment': '추천이 도움이 됐어요',
              'createdAt': '2026-06-15T12:00:00',
            },
          }),
        );
      await request.response.close();
    });

    final repository = RouteFeedbackApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'password',
      ),
    );

    await repository.submitRouteFeedback(
      const RouteFeedbackRequest(
        routeSearchId: 'route-1',
        rating: RouteFeedbackRating.helpful,
        comment: '추천이 도움이 됐어요',
        itineraryId: 'route-1-primary',
        mobilityType: 'SENIOR',
        constraintMode: 'PREFER_STEP_FREE',
        etaSource: 'PLANNED',
        etaOffsetBucket: RouteEtaOffsetBucket.notProvided,
        etaFeedbackOptedIn: true,
      ),
    );

    expect(requestedUri.path, '/api/v1/routes/route-1/feedback');
    expect(requestedAuthorization, startsWith('Basic '));
    expect(jsonDecode(requestedBody), {
      'userId': 'anonymous-user-1',
      'rating': 'HELPFUL',
      'comment': '추천이 도움이 됐어요',
      'itineraryId': 'route-1-primary',
      'mobilityType': 'SENIOR',
      'constraintMode': 'PREFER_STEP_FREE',
      'etaSource': 'PLANNED',
      'etaOffsetBucket': 'NOT_PROVIDED',
      'etaFeedbackOptedIn': true,
    });
  });

  test('경로 피드백 API 저장소는 인증 실패를 성공으로 바꾸지 않는다', () async {
    final noAuthorizationRepository = RouteFeedbackApiRepository(
      baseUri: Uri.parse('http://127.0.0.1'),
      authProvider: const NoAuthorizationHeaderProvider(),
    );
    final throwingAuthorizationRepository = RouteFeedbackApiRepository(
      baseUri: Uri.parse('http://127.0.0.1'),
      authProvider: const _ThrowingAuthorizationHeaderProvider(),
    );
    final malformedAuthorizationRepository = RouteFeedbackApiRepository(
      baseUri: Uri.parse('http://127.0.0.1'),
      authProvider: const _MalformedAuthorizationHeaderProvider(),
    );
    const request = RouteFeedbackRequest(
      routeSearchId: 'route-1',
      rating: RouteFeedbackRating.helpful,
      comment: '',
    );

    await expectLater(
      noAuthorizationRepository.submitRouteFeedback(request),
      throwsA(isA<RouteFeedbackException>()),
    );
    await expectLater(
      throwingAuthorizationRepository.submitRouteFeedback(request),
      throwsA(isA<RouteFeedbackException>()),
    );
    await expectLater(
      malformedAuthorizationRepository.submitRouteFeedback(request),
      throwsA(
        isA<RouteFeedbackException>().having(
          (error) => error.toString(),
          'safe message',
          '의견을 보내지 못했어요.',
        ),
      ),
    );
    expect(
      const FavoriteRouteException('즐겨찾기를 불러오지 못했어요.').toString(),
      '즐겨찾기를 불러오지 못했어요.',
    );

    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((httpRequest) async {
      requestCount += 1;
      httpRequest.response.statusCode = HttpStatus.unauthorized;
      await httpRequest.response.close();
    });
    final expiredAuthorizationRepository = RouteFeedbackApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'expired-password',
      ),
    );

    await expectLater(
      expiredAuthorizationRepository.submitRouteFeedback(request),
      throwsA(isA<RouteFeedbackException>()),
    );
    expect(requestCount, 2);
  });
}

class _ThrowingAuthorizationHeaderProvider
    implements AuthorizationHeaderProvider {
  const _ThrowingAuthorizationHeaderProvider();

  @override
  Future<String?> authorizationHeader() async {
    throw StateError('authorization unavailable');
  }

  @override
  Future<void> invalidateAuthorization() async {}
}

class _MalformedAuthorizationHeaderProvider
    implements AuthorizationHeaderProvider {
  const _MalformedAuthorizationHeaderProvider();

  @override
  Future<String?> authorizationHeader() async => 'Basic not-base64';

  @override
  Future<void> invalidateAuthorization() async {}
}

RouteSearchResult _sampleRouteSearchResult({
  String routeSearchId = 'route-1',
  String status = 'FOUND',
  String constraintMode = 'PREFER_STEP_FREE',
  List<RouteSearchStep> steps = const [
    RouteSearchStep(
      sequence: 1,
      title: '상록수역에서 4호선 승강장으로 이동',
      description: '엘리베이터를 이용해 승강장으로 이동합니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 4,
      distanceMeters: 180,
      includesStairs: false,
      requiresAccessibilityCheck: true,
    ),
  ],
  List<String> recommendationReasons = const [
    '엘리베이터 동선을 우선했어요',
    '계단 없는 출구를 확인했어요',
    '천천히 이동하기 쉬운 동선을 확인했어요',
  ],
  List<RouteSearchWarning> warnings = const [
    RouteSearchWarning(
      code: 'LOW_DATA_CONFIDENCE',
      message: '일부 시설 안내는 아직 확인되지 않았어요.',
    ),
  ],
  List<String> blockedReasons = const [],
  String etaSource = '',
  String etaConfidence = '',
  String accessibilityRiskLevel = '',
  int? transferSlackSeconds,
  bool hasOutOfStationTransfer = false,
}) {
  return RouteSearchResult(
    routeSearchId: routeSearchId,
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: 'SENIOR',
    constraintMode: constraintMode,
    status: status,
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    steps: steps,
    warnings: warnings,
    recommendationReasons: recommendationReasons,
    blockedReasons: blockedReasons,
    createdAt: '2026-06-13T04:20:00',
    etaSource: etaSource,
    etaConfidence: etaConfidence,
    accessibilityRiskLevel: accessibilityRiskLevel,
    transferSlackSeconds: transferSlackSeconds,
    hasOutOfStationTransfer: hasOutOfStationTransfer,
  );
}

Map<String, Object?> _favoriteRouteJson() {
  return {
    'userId': 'anonymous-user-1',
    'favoriteRouteId': 'route-1',
    'routeSearchId': 'route-1',
    'originStationId': 'station-sangnoksu',
    'originStationName': '상록수',
    'destinationStationId': 'station-sadang',
    'destinationStationName': '사당',
    'mobilityType': 'SENIOR',
    'status': 'FOUND',
    'lineId': 'seoul-4',
    'lineName': '수도권 4호선',
    'score': 92,
    'routeCreatedAt': '2026-06-13T04:20:00',
    'addedAt': '2026-06-14T10:00:00',
  };
}
