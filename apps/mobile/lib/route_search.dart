import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth_headers.dart';
import 'core/error/server_error_mapper.dart';
import 'core/network/api_client.dart';
import 'features/fare/official_od_fare_quote.dart';
import 'features/routes/domain/route_identity.dart';
import 'mobile_error_reporter.dart';
import 'features/mobility_profile/mobility_preset_labels.dart';
import 'route_hedge_labels.dart';

const _routeSearchTimeout = Duration(seconds: 8);
const _routeOnlineSearchErrorMessage = '실시간/서버 경로를 확인하지 못했어요.';
const _routeFeedbackErrorMessage = '의견을 보내지 못했어요.';
const _favoriteRouteErrorMessage = '즐겨찾기 경로를 바꾸지 못했어요.';
const _favoriteRouteLoadErrorMessage = '즐겨찾기 경로를 불러오지 못했어요.';
const _routeSafetyGuidanceNotice = '이동 전 현장 안내와 역무원 안내를 확인해 주세요.';
const _routeSearchFailureNextAction = '역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.';
String _mobilityLabelFor(String mobilityType) {
  final preset = mobilityPresetFromRepresentativeMobilityType(mobilityType);
  if (preset != null) {
    return mobilityPresetDisplayName(preset);
  }
  return '이동 조건을 다시 선택해 주세요';
}

String _routeDateLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 10) {
    return '최근 확인 ${trimmed.substring(0, 10)}';
  }
  return '최근 확인일이 아직 없어요';
}

const routeEtaSourceLabels = <String, String>{
  'REALTIME': '실시간 도착정보',
  'MIXED': '일부 실시간 도착정보',
  'PLANNED': '시간표 기준',
  'STATIC_BACKEND_ESTIMATE': '시간표 기준',
  'STATIC_BACKEND_V1': '시간표 기준',
  'STATIC_LOCAL': '저장된 데이터 기준',
  'STATIC_ESTIMATE': '정적 추정',
  'FALLBACK': '실시간 미지원',
  'UNSUPPORTED': '실시간 미지원',
  'STALE': '저장된 데이터 기준',
};

String routeEtaSourceLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '도착 정보를 확인하고 있어요';
  }
  return routeEtaSourceLabels[trimmed] ?? '도착 정보를 확인하고 있어요';
}

abstract class RouteSearchRepository {
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request);

  Future<RouteRefreshResult> refreshRoute(String routeSearchId);
}

abstract class RouteFeedbackRepository {
  Future<void> submitRouteFeedback(RouteFeedbackRequest request);
}

enum RouteFeedbackRating {
  helpful('HELPFUL'),
  notHelpful('NOT_HELPFUL'),
  blockedByRealWorld('BLOCKED_BY_REAL_WORLD');

  const RouteFeedbackRating(this.serverValue);

  final String serverValue;
}

enum RouteEtaOffsetBucket {
  earlyOver3Minutes('EARLY_OVER_3_MINUTES'),
  early1To3Minutes('EARLY_1_TO_3_MINUTES'),
  onTime('ON_TIME'),
  late1To3Minutes('LATE_1_TO_3_MINUTES'),
  lateOver3Minutes('LATE_OVER_3_MINUTES'),
  notProvided('NOT_PROVIDED');

  const RouteEtaOffsetBucket(this.serverValue);

  final String serverValue;
}

class RouteFeedbackRequest {
  const RouteFeedbackRequest({
    required this.routeSearchId,
    required this.rating,
    required this.comment,
    this.itineraryId = '',
    this.mobilityType = '',
    this.constraintMode = '',
    this.etaSource = '',
    this.etaOffsetBucket = RouteEtaOffsetBucket.notProvided,
    this.etaFeedbackOptedIn = false,
  });

  final String routeSearchId;
  final RouteFeedbackRating rating;
  final String comment;
  final String itineraryId;
  final String mobilityType;
  final String constraintMode;
  final String etaSource;
  final RouteEtaOffsetBucket etaOffsetBucket;
  final bool etaFeedbackOptedIn;

  RouteFeedbackRequest trimmed() {
    return RouteFeedbackRequest(
      routeSearchId: routeSearchId.trim(),
      rating: rating,
      comment: comment.trim(),
      itineraryId: itineraryId.trim(),
      mobilityType: mobilityType.trim(),
      constraintMode: constraintMode.trim(),
      etaSource: etaSource.trim(),
      etaOffsetBucket: etaOffsetBucket,
      etaFeedbackOptedIn: etaFeedbackOptedIn,
    );
  }

  Map<String, Object?> toJson({required String userId}) {
    final trimmedRequest = trimmed();
    final payload = <String, Object?>{
      'userId': userId.trim(),
      'rating': trimmedRequest.rating.serverValue,
      'comment': trimmedRequest.comment,
    };
    if (trimmedRequest.etaFeedbackOptedIn) {
      payload.addAll({
        'itineraryId': trimmedRequest.itineraryId,
        'mobilityType': trimmedRequest.mobilityType,
        'constraintMode': trimmedRequest.constraintMode,
        'etaSource': trimmedRequest.etaSource,
        'etaOffsetBucket': trimmedRequest.etaOffsetBucket.serverValue,
        'etaFeedbackOptedIn': true,
      });
    }
    return payload;
  }
}

class RouteSearchOnlineException extends RouteSearchException {
  const RouteSearchOnlineException.unavailable({
    this.statusCode,
    this.failureReason = 'online-unavailable',
    String message = _routeOnlineSearchErrorMessage,
    this.correlationId,
  }) : super(message);

  factory RouteSearchOnlineException.http(int statusCode) {
    final backend4xxFailure = statusCode >= 400 && statusCode < 500;
    final backend5xxFailure = statusCode >= 500;
    return RouteSearchOnlineException._(
      statusCode: statusCode,
      failureReason: backend5xxFailure
          ? 'backend-5xx'
          : backend4xxFailure
          ? 'backend-4xx'
          : 'backend-unexpected',
    );
  }

  factory RouteSearchOnlineException.response(ApiResponse response) {
    final body = response.jsonBody;
    final map = body is Map ? Map<String, Object?>.from(body) : null;
    final rawCode = map?['code'];
    final rawCorrelationId = map?['correlationId'];
    final correlationId = rawCorrelationId is String
        ? rawCorrelationId.trim()
        : null;
    final normalizedCorrelationId =
        (correlationId == null || correlationId.isEmpty) ? null : correlationId;

    if (rawCode is String && rawCode.isNotEmpty) {
      final mapped = serverErrorMapper.resolve(
        code: rawCode,
        correlationId: normalizedCorrelationId,
        statusCode: response.statusCode,
        defaultMessage: _routeOnlineSearchErrorMessage,
      );
      return RouteSearchOnlineException._(
        statusCode: response.statusCode,
        failureReason: rawCode,
        message: mapped.userMessage,
        correlationId: mapped.correlationId,
      );
    }

    final httpFallback = RouteSearchOnlineException.http(response.statusCode);
    return RouteSearchOnlineException._(
      statusCode: httpFallback.statusCode,
      failureReason: httpFallback.failureReason,
      message: httpFallback.message,
      correlationId: normalizedCorrelationId,
    );
  }

  const RouteSearchOnlineException._({
    required this.statusCode,
    required this.failureReason,
    String message = _routeOnlineSearchErrorMessage,
    this.correlationId,
  }) : super(message);

  final int? statusCode;
  final String failureReason;
  final String? correlationId;
}

enum RouteTransportScope {
  subway('SUBWAY'),
  subwayAndItxCheongchun('SUBWAY_AND_ITX_CHEONGCHUN');

  const RouteTransportScope(this.serverValue);

  final String serverValue;
}

RouteTransportScope _routeTransportScopeFromValue(Object? value) {
  return switch (value) {
    'SUBWAY_AND_ITX_CHEONGCHUN' => RouteTransportScope.subwayAndItxCheongchun,
    _ => RouteTransportScope.subway,
  };
}

/// 길찾기 최적화 목표. 선택 컨트롤이지만 실제 운행 정보(급행 여부)와는 무관한
/// 별개 차원이다. 서버는 null을 FASTEST로 해석하므로 기본값도 FASTEST다.
enum RouteObjective {
  fastest('FASTEST', '최단시간'),
  fewestTransfers('FEWEST_TRANSFERS', '최소환승');

  const RouteObjective(this.serverValue, this.label);

  final String serverValue;
  final String label;
}

class RouteFeedbackApiRepository implements RouteFeedbackRepository {
  RouteFeedbackApiRepository({
    required this.baseUri,
    required this.authProvider,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final ApiClient _apiClient;

  @override
  Future<void> submitRouteFeedback(RouteFeedbackRequest feedbackRequest) async {
    final trimmedRequest = feedbackRequest.trimmed();
    if (trimmedRequest.routeSearchId.isEmpty) {
      throw const RouteFeedbackException(_routeFeedbackErrorMessage);
    }

    final path =
        '/api/v1/routes/${Uri.encodeComponent(trimmedRequest.routeSearchId)}/feedback';

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_routeSearchTimeout);
        // Basic 인증의 username을 사용자 식별자로 사용한다.
        final userId = _userIdFromAuthorizationHeader(authorizationHeader);
        if (userId == null) {
          throw const RouteFeedbackException(_routeFeedbackErrorMessage);
        }

        final response = await _apiClient.postJson(
          path,
          body: trimmedRequest.toJson(userId: userId),
          headers: {HttpHeaders.authorizationHeader: authorizationHeader!},
        );

        // 저장된 인증이 만료된 경우 한 번만 재시도한다.
        if (response.isUnauthorized && attempt == 0) {
          await authProvider.invalidateAuthorization().timeout(
            _routeSearchTimeout,
          );
          continue;
        }

        if (!response.isOk) {
          throw const RouteFeedbackException(_routeFeedbackErrorMessage);
        }

        final decoded = response.jsonBody;
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw const RouteFeedbackException(_routeFeedbackErrorMessage);
        }
        return;
      } on RouteFeedbackException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '경로 피드백 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw const RouteFeedbackException(_routeFeedbackErrorMessage);
      }
    }
    throw const RouteFeedbackException(_routeFeedbackErrorMessage);
  }

  String? _userIdFromAuthorizationHeader(String? authorizationHeader) {
    const prefix = 'Basic ';
    if (authorizationHeader == null ||
        !authorizationHeader.startsWith(prefix)) {
      return null;
    }

    try {
      final decoded = utf8.decode(
        base64Decode(authorizationHeader.substring(prefix.length)),
      );
      final separatorIndex = decoded.indexOf(':');
      if (separatorIndex <= 0) {
        return null;
      }
      final userId = decoded.substring(0, separatorIndex).trim();
      return userId.isEmpty ? null : userId;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 피드백 사용자 식별자 처리 중 예외가 발생했습니다.',
      );
      return null;
    }
  }
}

class RouteFeedbackException implements Exception {
  const RouteFeedbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FavoriteRouteRepository {
  Future<List<FavoriteRoute>> listFavoriteRoutes();

  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  });

  Future<void> removeFavoriteRoute(String favoriteRouteId);
}

class FavoriteRouteApiRepository implements FavoriteRouteRepository {
  FavoriteRouteApiRepository({
    required this.baseUri,
    required this.authProvider,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final ApiClient _apiClient;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    final data = await _requestData(
      'GET',
      '/api/v1/me/favorites/routes',
      errorMessage: _favoriteRouteLoadErrorMessage,
    );
    if (data is! List<Object?>) {
      throw const FavoriteRouteException(_favoriteRouteLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite route payload');
            }
            return FavoriteRoute.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteRouteException(_favoriteRouteLoadErrorMessage);
    }
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  }) async {
    final data = await _requestData(
      'POST',
      '/api/v1/me/favorites/routes',
      body: {'routeSearchId': routeSearchId},
      errorMessage: _favoriteRouteErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const FavoriteRouteException(_favoriteRouteErrorMessage);
    }

    try {
      return FavoriteRoute.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteRouteException(_favoriteRouteErrorMessage);
    }
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {
    await _requestData(
      'DELETE',
      '/api/v1/me/favorites/routes/$favoriteRouteId',
      errorMessage: _favoriteRouteErrorMessage,
    );
  }

  Future<Object?> _requestData(
    String method,
    String path, {
    Map<String, Object?>? body,
    required String errorMessage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_routeSearchTimeout);
        final headers = <String, String>{};
        if (authorizationHeader != null) {
          headers[HttpHeaders.authorizationHeader] = authorizationHeader;
        }

        final response = await switch (method) {
          'GET' => _apiClient.getJson(path, headers: headers),
          'POST' => _apiClient.postJson(path, body: body!, headers: headers),
          'DELETE' => _apiClient.deleteJson(path, headers: headers),
          _ => throw FavoriteRouteException(errorMessage),
        };

        if (response.isUnauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 만료된 인증은 비우고 한 번만 다시 시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _routeSearchTimeout,
          );
          continue;
        }

        if (!response.isSuccess) {
          throw FavoriteRouteException(errorMessage);
        }

        final decoded = response.jsonBody;
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteRouteException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteRouteException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 경로 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteRouteException(errorMessage);
      }
    }
    throw FavoriteRouteException(errorMessage);
  }
}

class FavoriteRouteException implements Exception {
  const FavoriteRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteRoute {
  const FavoriteRoute({
    required this.userId,
    required this.favoriteRouteId,
    required this.routeSearchId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.mobilityType,
    required this.status,
    required this.lineId,
    required this.lineName,
    required this.score,
    required this.routeCreatedAt,
    required this.addedAt,
    this.etaSource = '',
    this.transportScope = RouteTransportScope.subway,
    this.needsResearch = false,
  });

  factory FavoriteRoute.fromJson(Map<String, Object?> json) {
    return FavoriteRoute(
      userId: _requiredRouteString(json, 'userId'),
      favoriteRouteId: _requiredRouteString(json, 'favoriteRouteId'),
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      originStationName: _requiredRouteString(json, 'originStationName'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      destinationStationName: _requiredRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      status: _requiredRouteString(json, 'status'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      score: _requiredRouteInt(json, 'score'),
      routeCreatedAt: _requiredRouteString(json, 'routeCreatedAt'),
      addedAt: _requiredRouteString(json, 'addedAt'),
      etaSource: _optionalRouteString(json, 'etaSource'),
      transportScope: _routeTransportScopeFromValue(json['transportScope']),
      needsResearch: json['needsResearch'] == true,
    );
  }

  final String userId;
  final String favoriteRouteId;
  final String routeSearchId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String status;
  final String lineId;
  final String lineName;
  final int score;
  final String routeCreatedAt;
  final String addedAt;
  final String etaSource;
  final RouteTransportScope transportScope;
  final bool needsResearch;

  String get statusLabel => needsResearch ? '다시 검색 필요' : status;

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  /// 노선명(모르면 빈 문자열 — 호출부에서 줄 자체를 숨긴다).
  String get lineLabel => lineName;

  bool get hasLine => lineName.isNotEmpty;

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get etaSourceLabel => routeEtaSourceLabel(etaSource);

  /// 확정 정보만: 이동 조건 · 노선(있을 때) · 최근 확인일 · 출처.
  String get scoreBasisText {
    return [
      '$mobilityLabel 조건',
      if (hasLine) lineLabel,
      _routeDateLabel(routeCreatedAt),
      if (etaSourceLabel.isNotEmpty) etaSourceLabel,
    ].join(' · ');
  }

  String get scoreBasisSemanticLabel {
    return [
      '$mobilityLabel 조건',
      if (hasLine) lineLabel,
      _routeDateLabel(routeCreatedAt),
      if (etaSourceLabel.isNotEmpty) etaSourceLabel,
    ].join(', ');
  }

  String get semanticLabel {
    return [
      '즐겨찾기 경로',
      summaryTitle,
      if (hasLine) lineLabel,
      mobilityLabel,
      if (needsResearch) statusLabel,
      scoreBasisSemanticLabel,
    ].join(', ');
  }
}

class RouteSearchException implements Exception {
  const RouteSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RouteSearchRequest {
  const RouteSearchRequest({
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityType,
    this.constraintMode,
    this.waypointStationId,
    this.mobilityPreset,
    this.transportScope = RouteTransportScope.subway,
    this.objective = RouteObjective.fastest,
  });

  final String originStationId;
  final String destinationStationId;
  final String mobilityType;
  final String? constraintMode;
  final String? waypointStationId;

  /// v2 요청에만 실리는 보행 프리셋 서버 문자열(하위호환으로 mobilityType도 유지).
  final String? mobilityPreset;
  final RouteTransportScope transportScope;

  /// 최적화 목표(FASTEST·FEWEST_TRANSFERS). 급행 여부와는 무관한 별개 차원이며,
  /// 요청 serialization에는 이 값만 싣고 servicePattern/expressOnly는 싣지 않는다.
  final RouteObjective objective;

  String get effectiveConstraintMode =>
      constraintMode ?? _defaultConstraintMode(mobilityType);

  RouteQueryIdentity get queryIdentity {
    final request = trimmed();
    return RouteQueryIdentity(
      originStationId: request.originStationId,
      destinationStationId: request.destinationStationId,
      mobilityType: request.mobilityType,
      constraintMode: request.effectiveConstraintMode,
      waypointStationId: request.waypointStationId,
      mobilityPreset: request.mobilityPreset,
      transportScope: request.transportScope.serverValue,
      objective: request.objective.serverValue,
    );
  }

  RouteSearchRequest trimmed() {
    return RouteSearchRequest(
      originStationId: originStationId.trim(),
      destinationStationId: destinationStationId.trim(),
      mobilityType: mobilityType.trim(),
      constraintMode: constraintMode?.trim(),
      waypointStationId: waypointStationId?.trim(),
      mobilityPreset: mobilityPreset?.trim(),
      transportScope: transportScope,
      objective: objective,
    );
  }

  Map<String, Object?> toJson() {
    final trimmedRequest = trimmed();
    return {
      'originStationId': trimmedRequest.originStationId,
      'destinationStationId': trimmedRequest.destinationStationId,
      'mobilityType': trimmedRequest.mobilityType,
      'constraintMode': trimmedRequest.effectiveConstraintMode,
    };
  }

  Map<String, Object?> toV2Json() {
    final trimmedPreset = mobilityPreset?.trim();
    return {
      ...toJson(),
      if (trimmedPreset != null && trimmedPreset.isNotEmpty)
        'mobilityPreset': trimmedPreset,
      'objective': objective.serverValue,
      'departureTime': _routeV2DepartureTimeNow(),
      'useRealtime': true,
      'maxTransfers': 3,
      'alternativeCount': 3,
    };
  }

  static String _defaultConstraintMode(String mobilityType) =>
      mobilityType == 'WHEELCHAIR' ? 'STRICT_STEP_FREE' : 'PREFER_STEP_FREE';
}

class RouteSearchV2Result {
  const RouteSearchV2Result({
    required this.contractVersion,
    required this.originStationId,
    required this.destinationStationId,
    required this.departureTime,
    required this.mobilityType,
    required this.constraintMode,
    required this.useRealtime,
    required this.maxTransfers,
    required this.alternativeCount,
    required this.statuses,
    required this.itineraries,
    this.nextServiceTime = '',
  });

  factory RouteSearchV2Result.fromJson(Map<String, Object?> json) {
    final rawItineraries = json['itineraries'];
    if (rawItineraries is! List<Object?>) {
      throw const FormatException('Invalid route v2 itinerary payload');
    }
    return RouteSearchV2Result(
      contractVersion: _requiredRouteString(json, 'contractVersion'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      departureTime: _requiredRouteString(json, 'departureTime'),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      constraintMode: _requiredRouteString(json, 'constraintMode'),
      useRealtime: _requiredRouteBool(json, 'useRealtime'),
      maxTransfers: _requiredRouteInt(json, 'maxTransfers'),
      alternativeCount: _requiredRouteInt(json, 'alternativeCount'),
      statuses: _routeStringList(json['statuses'], 'route v2 status'),
      nextServiceTime:
          _optionalNullableRouteString(json, 'nextServiceTime') ?? '',
      itineraries: rawItineraries
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route v2 itinerary payload');
            }
            return RouteSearchV2Itinerary.fromJson(item);
          })
          .toList(growable: false),
    );
  }

  final String contractVersion;
  final String originStationId;
  final String destinationStationId;
  final String departureTime;
  final String mobilityType;
  final String constraintMode;
  final bool useRealtime;
  final int maxTransfers;
  final int alternativeCount;
  final List<String> statuses;
  final List<RouteSearchV2Itinerary> itineraries;
  final String nextServiceTime;
}

/// 무단차 선호(`PREFER_STEP_FREE`) 검색에서 백엔드가 덧붙이는 대안 후보 태그.
///
/// 백엔드 계약(#2560): 대표 중 `stairAccess == STEP_FREE`가 하나도 없고
/// alternativeCount에 자리가 남을 때만, 같은 기준을 만족하는 후보 1건에 붙는다.
///
/// 주의 — 이 태그는 `계단 없는 길이에요`와 같은 뜻이 아니다. 태깅 술어는 계단
/// 사실만 보는 반면(#2560), 화면에 실리는 판정(`stairAccess`)은 데이터 신뢰도
/// 경고까지 반영해 한 단계 낮아질 수 있다(#2590). 따라서 대안의 계단 표기는 태그가
/// 아니라 대안 자신의 [RouteSearchResult.stairAccessLabel]로만 말한다.
const _stepFreePreferredObjectiveTag = 'STEP_FREE_PREFERRED';

class RouteSearchV2Itinerary {
  const RouteSearchV2Itinerary({
    required this.itineraryId,
    required this.status,
    required this.plannedArrivalTime,
    required this.realtimeArrivalTime,
    required this.etaSource,
    required this.etaConfidence,
    required this.durationSeconds,
    required this.transferCount,
    required this.walkingDistanceMeters,
    required this.accessibilityRisk,
    required this.legs,
    required this.commercialEtaEligible,
    this.stairAccess = '',
    this.objectiveTags = const [],
    this.officialFare,
  });

  factory RouteSearchV2Itinerary.fromJson(Map<String, Object?> json) {
    final rawLegs = json['legs'];
    final rawAccessibilityRisk = json['accessibilityRisk'];
    if (rawLegs is! List<Object?> ||
        rawAccessibilityRisk is! Map<String, Object?>) {
      throw const FormatException('Invalid route v2 itinerary payload');
    }
    return RouteSearchV2Itinerary(
      itineraryId: _requiredRouteString(json, 'itineraryId'),
      status: _requiredRouteString(json, 'status'),
      plannedArrivalTime: _requiredRouteString(json, 'plannedArrivalTime'),
      realtimeArrivalTime: _optionalNullableRouteString(
        json,
        'realtimeArrivalTime',
      ),
      etaSource: _requiredRouteString(json, 'etaSource'),
      etaConfidence: _requiredRouteString(json, 'etaConfidence'),
      durationSeconds: _requiredRouteInt(json, 'durationSeconds'),
      transferCount: _requiredRouteInt(json, 'transferCount'),
      walkingDistanceMeters: _requiredRouteInt(json, 'walkingDistanceMeters'),
      accessibilityRisk: RouteSearchV2AccessibilityRisk.fromJson(
        rawAccessibilityRisk,
      ),
      legs: rawLegs
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route v2 leg payload');
            }
            return RouteSearchV2Leg.fromJson(item);
          })
          .toList(growable: false),
      commercialEtaEligible: _requiredRouteBool(json, 'commercialEtaEligible'),
      stairAccess: _optionalRouteString(json, 'stairAccess'),
      objectiveTags: _routeStringList(
        json['objectiveTags'] ?? const <Object?>[],
        'route v2 objective tag',
      ),
      officialFare: switch (json['officialFare']) {
        null => null,
        Map<String, Object?> value => RouteSearchOfficialFare.fromJson(value),
        _ => throw const FormatException('Invalid route v2 official fare'),
      },
    );
  }

  final String itineraryId;
  final String status;
  final String plannedArrivalTime;
  final String? realtimeArrivalTime;
  final String etaSource;
  final String etaConfidence;
  final int durationSeconds;
  final int transferCount;
  final int walkingDistanceMeters;
  final RouteSearchV2AccessibilityRisk accessibilityRisk;
  final List<RouteSearchV2Leg> legs;
  final bool commercialEtaEligible;
  final RouteSearchOfficialFare? officialFare;

  /// 백엔드가 내린 경로 전체의 계단 판정(#2590). 화면은 이 값을 표시만 하고 leg를
  /// 훑어 다시 계산하지 않는다. 판정 필드가 없는 레거시 응답에서는 빈 문자열이다.
  final String stairAccess;

  /// 백엔드가 itinerary에 붙이는 objective 태그.
  ///
  /// 대표 itinerary에는 요청 objective 어휘(`FASTEST`·`FEWEST_TRANSFERS`)가 붙고,
  /// 두 objective가 같은 경로면 dual-tag dedupe로 두 태그를 모두 담는다. 여기에
  /// 더해 무단차 선호 검색에서는 [_stepFreePreferredObjectiveTag]가 붙은 대안
  /// 후보가 최대 1건 함께 올 수 있다(#2560). 모르는 태그는 무시한다.
  final List<String> objectiveTags;

  bool matchesObjective(RouteObjective objective) =>
      objectiveTags.contains(objective.serverValue);
}

class RouteSearchOfficialFare {
  const RouteSearchOfficialFare({
    required this.adultFareWon,
    required this.currency,
    required this.policy,
    required this.sourceIds,
    required this.sourceSnapshotIds,
  });

  factory RouteSearchOfficialFare.fromJson(Map<String, Object?> json) {
    final fare = RouteSearchOfficialFare(
      adultFareWon: _requiredRouteInt(json, 'adultFareWon'),
      currency: _requiredRouteString(json, 'currency'),
      policy: _requiredRouteString(json, 'policy'),
      sourceIds: _routeStringList(json['sourceIds'], 'official fare source'),
      sourceSnapshotIds: _routeStringList(
        json['sourceSnapshotIds'],
        'official fare source snapshot',
      ),
    );
    if (fare.adultFareWon <= 0 ||
        fare.currency != 'KRW' ||
        fare.policy != 'SUM_OF_OFFICIAL_RIDE_OD_FARES' ||
        fare.sourceIds.isEmpty ||
        fare.sourceSnapshotIds.isEmpty) {
      throw const FormatException('Invalid route v2 official fare');
    }
    return fare;
  }

  final int adultFareWon;
  final String currency;
  final String policy;
  final List<String> sourceIds;
  final List<String> sourceSnapshotIds;
}

class RouteSearchV2Leg {
  const RouteSearchV2Leg({
    required this.legType,
    required this.fromStationId,
    required this.toStationId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.lineId,
    required this.tripId,
    required this.trainNo,
    required this.plannedDepartureTime,
    required this.realtimeDepartureTime,
    required this.plannedArrivalTime,
    required this.realtimeArrivalTime,
    required this.waitTimeSeconds,
    required this.slackSeconds,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.etaSource,
    required this.confidence,
    required this.accessibilityRisk,
    this.stairAccess = '',
    this.requiresAccessibilityCheck,
    this.serviceClass,
    this.servicePattern,
  });

  factory RouteSearchV2Leg.fromJson(Map<String, Object?> json) {
    final rawAccessibilityRisk = json['accessibilityRisk'];
    if (rawAccessibilityRisk is! Map<String, Object?>) {
      throw const FormatException('Invalid route v2 leg payload');
    }
    final legType = _requiredRouteString(json, 'legType');
    final (serviceClass, servicePattern) = _routeV2LegServiceFields(
      legType,
      json['serviceClass'],
      json['servicePattern'],
    );
    return RouteSearchV2Leg(
      legType: legType,
      fromStationId: _optionalRouteString(json, 'fromStationId'),
      toStationId: _optionalRouteString(json, 'toStationId'),
      fromNodeId: _optionalRouteString(json, 'fromNodeId'),
      toNodeId: _optionalRouteString(json, 'toNodeId'),
      lineId: _optionalRouteString(json, 'lineId'),
      tripId: _optionalRouteString(json, 'tripId'),
      trainNo: _optionalRouteString(json, 'trainNo'),
      plannedDepartureTime: _requiredRouteString(json, 'plannedDepartureTime'),
      realtimeDepartureTime: _optionalNullableRouteString(
        json,
        'realtimeDepartureTime',
      ),
      plannedArrivalTime: _requiredRouteString(json, 'plannedArrivalTime'),
      realtimeArrivalTime: _optionalNullableRouteString(
        json,
        'realtimeArrivalTime',
      ),
      waitTimeSeconds: _requiredRouteInt(json, 'waitTimeSeconds'),
      slackSeconds: _requiredRouteInt(json, 'slackSeconds'),
      durationSeconds: _requiredRouteInt(json, 'durationSeconds'),
      distanceMeters: _requiredRouteInt(json, 'distanceMeters'),
      etaSource: _requiredRouteString(json, 'etaSource'),
      confidence: _requiredRouteString(json, 'confidence'),
      accessibilityRisk: RouteSearchV2AccessibilityRisk.fromJson(
        rawAccessibilityRisk,
      ),
      stairAccess: _optionalRouteString(json, 'stairAccess'),
      requiresAccessibilityCheck: _optionalRouteBool(
        json,
        'requiresAccessibilityCheck',
      ),
      serviceClass: serviceClass,
      servicePattern: servicePattern,
    );
  }

  final String legType;
  final String fromStationId;
  final String toStationId;
  final String fromNodeId;
  final String toNodeId;
  final String lineId;
  final String tripId;
  final String trainNo;
  final String plannedDepartureTime;
  final String? realtimeDepartureTime;
  final String plannedArrivalTime;
  final String? realtimeArrivalTime;
  final int waitTimeSeconds;
  final int slackSeconds;
  final int durationSeconds;
  final int distanceMeters;
  final String etaSource;
  final String confidence;
  final RouteSearchV2AccessibilityRisk accessibilityRisk;

  /// 백엔드가 내린 leg 계단 판정(#2590). `STAIR_ONLY`·`STEP_FREE`·`UNKNOWN`과, 계단
  /// 개념이 적용되지 않는 구간을 뜻하는 `NOT_APPLICABLE`을 받는다. 이 값은 그 구간
  /// 자신의 사실만 담으므로 경로 전체의 판정([RouteSearchV2Itinerary.stairAccess])과
  /// 다를 수 있다 — 화면이 쓰는 것은 경로 판정이다. 판정 필드가 없는 레거시 응답에서는
  /// 빈 문자열이고, 그때만 화면이 원자료로 폴백한다.
  final String stairAccess;

  /// 백엔드 플래너가 이 구간에 세운 검증 근거 없음 표기(#2590). 계단 사실
  /// ([stairAccess])과는 다른 축이라 따로 싣는다 — 계단이 확인된 구간도 검증 근거가
  /// 없으면 이 표기가 함께 붙어야 한다. 이 필드가 없는 레거시 응답에서는 null이고,
  /// 그때만 화면이 원자료로 폴백한다.
  final bool? requiresAccessibilityCheck;

  /// 운행 클래스(SUBWAY·ITX_CHEONGCHUN). RIDE leg에서만 채워지고, 그 외에는 null.
  final String? serviceClass;

  /// 운행종별(LOCAL·EXPRESS). RIDE leg에서만 채워지고, 그 외에는 null.
  final String? servicePattern;

  /// 지하철 급행 leg 여부. `급행` 배지를 노출하는 유일한 조건이다.
  bool get isSubwayExpress =>
      serviceClass == 'SUBWAY' && servicePattern == 'EXPRESS';
}

const _routeV2ServiceClasses = {'SUBWAY', 'ITX_CHEONGCHUN'};
const _routeV2ServicePatterns = {'LOCAL', 'EXPRESS'};

/// RIDE leg의 serviceClass·servicePattern을 필수 enum으로 검증하고, non-ride leg은
/// null만 허용한다. unknown·blank·non-ride 값 존재는 payload error로 처리해
/// LOCAL 추정 없이 unavailable로 흐르게 한다.
(String?, String?) _routeV2LegServiceFields(
  String legType,
  Object? rawServiceClass,
  Object? rawServicePattern,
) {
  final isRide = legType == 'RIDE';
  if (!isRide) {
    if (rawServiceClass != null || rawServicePattern != null) {
      throw const FormatException(
        'Non-ride route v2 leg must not carry service fields',
      );
    }
    return (null, null);
  }
  if (rawServiceClass is! String ||
      !_routeV2ServiceClasses.contains(rawServiceClass)) {
    throw const FormatException('Invalid route v2 ride serviceClass');
  }
  if (rawServicePattern is! String ||
      !_routeV2ServicePatterns.contains(rawServicePattern)) {
    throw const FormatException('Invalid route v2 ride servicePattern');
  }
  return (rawServiceClass, rawServicePattern);
}

class RouteSearchV2AccessibilityRisk {
  const RouteSearchV2AccessibilityRisk({
    required this.stairCount,
    required this.unknownAccessibilityCount,
    required this.generatedConnectorCount,
    required this.staleDataCount,
    required this.lowConfidenceCount,
    required this.unavailableFacilityCount,
    required this.riskLevel,
    required this.reasonCodes,
    required this.level,
    required this.reasons,
  });

  factory RouteSearchV2AccessibilityRisk.fromJson(Map<String, Object?> json) {
    final reasonCodes = _routeStringList(
      json['reasonCodes'] ?? json['reasons'],
      'route v2 accessibility risk reason',
    );
    final riskLevel = _optionalRouteString(
      json,
      'riskLevel',
      fallback: _optionalRouteString(json, 'level', fallback: 'UNKNOWN'),
    );
    return RouteSearchV2AccessibilityRisk(
      stairCount: _optionalRouteInt(json, 'stairCount') ?? 0,
      unknownAccessibilityCount:
          _optionalRouteInt(json, 'unknownAccessibilityCount') ?? 0,
      generatedConnectorCount:
          _optionalRouteInt(json, 'generatedConnectorCount') ?? 0,
      staleDataCount: _optionalRouteInt(json, 'staleDataCount') ?? 0,
      lowConfidenceCount: _optionalRouteInt(json, 'lowConfidenceCount') ?? 0,
      unavailableFacilityCount:
          _optionalRouteInt(json, 'unavailableFacilityCount') ?? 0,
      riskLevel: riskLevel,
      reasonCodes: reasonCodes,
      level: _requiredRouteString(json, 'level'),
      reasons: _routeStringList(
        json['reasons'],
        'route v2 accessibility risk reason',
      ),
    );
  }

  final int stairCount;
  final int unknownAccessibilityCount;
  final int generatedConnectorCount;
  final int staleDataCount;
  final int lowConfidenceCount;
  final int unavailableFacilityCount;
  final String riskLevel;
  final List<String> reasonCodes;
  final String level;
  final List<String> reasons;
}

class RouteSearchResult {
  const RouteSearchResult({
    required this.routeSearchId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.mobilityType,
    this.constraintMode = '',
    required this.status,
    required this.lineId,
    required this.lineName,
    required this.score,
    int? accessibilityScore,
    int? burdenCost,
    int? estimatedDurationSeconds,
    int? walkingDistanceMeters,
    int? transferCount,
    this.evidenceSummary = const [],
    required this.steps,
    required this.warnings,
    this.recommendationReasons = const [],
    required this.blockedReasons,
    required this.createdAt,
    this.etaSource = '',
    this.etaConfidence = '',
    this.accessibilityRiskLevel = '',
    this.transferSlackSeconds,
    this.hasOutOfStationTransfer = false,
    this.commercialEtaEligible = false,
    this.sourceUpdatedAt = '',
    this.officialOdFareQuote,
    this.supportsRefresh = true,
    this.nextServiceTime = '',
    this.transportScope = RouteTransportScope.subway,
    this.objective = RouteObjective.fastest,
    this.departureTimeIso = '',
    this.arrivalTimeIso = '',
    this.officialFare,
    this.stepFreeAlternative,
    this.stairAccess = '',
    this.queryIdentity,
    this.candidateIdentity,
    String? providerRouteSearchId,
    String? providerItineraryId,
  }) : providerRouteSearchId = providerRouteSearchId ?? '',
       providerItineraryId = providerItineraryId ?? '',
       // `burdenCost`는 API contract 이름이고 저장 필드는 private 값이다.
       // ignore: prefer_initializing_formals
       _accessibilityScore = accessibilityScore,
       // ignore: prefer_initializing_formals
       _burdenCost = burdenCost,
       // ignore: prefer_initializing_formals
       _estimatedDurationSeconds = estimatedDurationSeconds,
       // ignore: prefer_initializing_formals
       _walkingDistanceMeters = walkingDistanceMeters,
       // ignore: prefer_initializing_formals
       _transferCount = transferCount;

  factory RouteSearchResult.fromJson(
    Map<String, Object?> json, {
    String? constraintMode,
    RouteObjective objective = RouteObjective.fastest,
  }) {
    final rawSteps = json['steps'];
    final rawWarnings = json['warnings'];
    final rawRecommendationReasons = json['recommendationReasons'];
    final rawBlockedReasons = json['blockedReasons'];
    final legacyScore = _optionalRouteInt(json, 'score');
    final accessibilityScore = _optionalRouteInt(json, 'accessibilityScore');
    final burdenCost =
        _optionalRouteInt(json, 'burdenCost') ??
        legacyScore ??
        (throw const FormatException(
          'Missing required route field: burdenCost',
        ));
    if (rawSteps is! List<Object?> ||
        rawWarnings is! List<Object?> ||
        (rawRecommendationReasons != null &&
            rawRecommendationReasons is! List<Object?>) ||
        rawBlockedReasons is! List<Object?>) {
      throw const FormatException('Invalid route payload');
    }

    return RouteSearchResult(
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      providerRouteSearchId: _requiredRouteString(json, 'routeSearchId'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      originStationName: _requiredRouteString(json, 'originStationName'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      destinationStationName: _requiredRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      constraintMode: constraintMode?.trim().isNotEmpty == true
          ? constraintMode!.trim()
          : _optionalRouteString(json, 'constraintMode'),
      status: _requiredRouteString(json, 'status'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      score: accessibilityScore ?? legacyScore ?? burdenCost,
      accessibilityScore: accessibilityScore ?? legacyScore,
      burdenCost: burdenCost,
      estimatedDurationSeconds: _optionalRouteInt(
        json,
        'estimatedDurationSeconds',
      ),
      walkingDistanceMeters: _optionalRouteInt(json, 'walkingDistanceMeters'),
      transferCount: _optionalRouteInt(json, 'transferCount'),
      steps: rawSteps
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route step payload');
            }
            return RouteSearchStep.fromJson(item);
          })
          .toList(growable: false),
      warnings: rawWarnings
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route warning payload');
            }
            return RouteSearchWarning.fromJson(item);
          })
          .toList(growable: false),
      recommendationReasons: _routeStringList(
        rawRecommendationReasons,
        'recommendation reason',
      ),
      evidenceSummary: _routeStringList(
        json['evidenceSummary'],
        'route evidence summary',
      ),
      blockedReasons: rawBlockedReasons
          .map((item) {
            if (item is! String || item.trim().isEmpty) {
              throw const FormatException('Invalid blocked reason payload');
            }
            return item;
          })
          .toList(growable: false),
      createdAt: _requiredRouteString(json, 'createdAt'),
      etaSource: _optionalRouteString(json, 'etaSource'),
      etaConfidence: _optionalRouteString(json, 'etaConfidence'),
      accessibilityRiskLevel: _optionalRouteString(
        json,
        'accessibilityRiskLevel',
      ),
      transferSlackSeconds: _optionalRouteInt(json, 'transferSlackSeconds'),
      hasOutOfStationTransfer:
          _optionalRouteBool(json, 'hasOutOfStationTransfer') ?? false,
      commercialEtaEligible:
          _optionalRouteBool(json, 'commercialEtaEligible') ?? false,
      sourceUpdatedAt: _optionalRouteString(json, 'sourceUpdatedAt'),
      nextServiceTime: _optionalRouteString(json, 'nextServiceTime'),
      transportScope: _routeTransportScopeFromValue(json['transportScope']),
      objective: objective,
    );
  }

  factory RouteSearchResult.fromV2(
    RouteSearchV2Result result, {
    RouteObjective objective = RouteObjective.fastest,
    RouteQueryIdentity? queryIdentity,
  }) {
    if (result.itineraries.isEmpty) {
      if (result.statuses.isEmpty) {
        throw const FormatException(
          'Route v2 response has neither status nor itinerary',
        );
      }
      return RouteSearchResult(
        routeSearchId:
            'route-v2-${result.originStationId}-${result.destinationStationId}-${result.departureTime}',
        originStationId: result.originStationId,
        originStationName: result.originStationId,
        destinationStationId: result.destinationStationId,
        destinationStationName: result.destinationStationId,
        mobilityType: result.mobilityType,
        constraintMode: result.constraintMode,
        status: 'BLOCKED',
        lineId: '',
        lineName: '',
        score: 0,
        burdenCost: 0,
        estimatedDurationSeconds: 0,
        walkingDistanceMeters: 0,
        transferCount: 0,
        evidenceSummary: result.statuses,
        steps: const [],
        warnings: const [],
        blockedReasons: result.statuses,
        createdAt: result.departureTime,
        etaSource: result.nextServiceTime.isEmpty ? 'UNSUPPORTED' : 'PLANNED',
        sourceUpdatedAt: result.departureTime,
        supportsRefresh: false,
        nextServiceTime: result.nextServiceTime,
        transportScope: RouteTransportScope.subwayAndItxCheongchun,
        objective: objective,
        departureTimeIso: result.departureTime,
        queryIdentity: queryIdentity,
      );
    }
    final selection = _selectRouteV2Itinerary(result.itineraries, objective);
    final alternative = selection.stepFreeAlternative;
    return _routeSearchResultFromV2Itinerary(
      result: result,
      itinerary: selection.primary,
      objective: objective,
      queryIdentity: queryIdentity,
      // 대안도 같은 변환을 거쳐 동일한 화면 모델이 된다 — 탭 전환 시 그대로 주
      // 결과가 되므로 별도 변환 경로를 두지 않는다(#2582).
      stepFreeAlternative: alternative == null
          ? null
          : _routeSearchResultFromV2Itinerary(
              result: result,
              itinerary: alternative,
              objective: objective,
              queryIdentity: queryIdentity,
            ),
    );
  }

  final String routeSearchId;
  final RouteQueryIdentity? queryIdentity;
  final RouteCandidateIdentity? candidateIdentity;
  final String providerRouteSearchId;
  final String providerItineraryId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String constraintMode;
  final String status;
  final String lineId;
  final String lineName;
  final int score;
  final int? _accessibilityScore;
  final int? _burdenCost;
  final int? _estimatedDurationSeconds;
  final int? _walkingDistanceMeters;
  final int? _transferCount;
  final List<String> evidenceSummary;
  final List<RouteSearchStep> steps;
  final List<RouteSearchWarning> warnings;
  final List<String> recommendationReasons;
  final List<String> blockedReasons;
  final String createdAt;
  final String etaSource;
  final String etaConfidence;
  final String accessibilityRiskLevel;
  final int? transferSlackSeconds;
  final bool hasOutOfStationTransfer;
  final bool commercialEtaEligible;
  final String sourceUpdatedAt;
  final OfficialOdFareQuote? officialOdFareQuote;
  final bool supportsRefresh;
  final String nextServiceTime;
  final RouteTransportScope transportScope;
  final RouteObjective objective;
  final String departureTimeIso;
  final String arrivalTimeIso;
  final RouteSearchOfficialFare? officialFare;

  /// 무단차 선호 검색에서 백엔드가 함께 보존한 대안(#2582).
  ///
  /// 없는 것이 정상이다. 대안이 실제로 어느 계단 상태로 표시되는지는
  /// [_stepFreePreferredObjectiveTag] 주석 참고 — 태그가 곧 `계단 없는 길이에요`를
  /// 뜻하지는 않으므로 대안의 계단 표기는 대안 자신의 [stairAccessLabel]로만
  /// 말한다. 대안 자신은 이 필드를 갖지 않는다 — 화면이 대안으로 전환하면
  /// 되돌아갈 대표는 화면이 계속 들고 있다.
  final RouteSearchResult? stepFreeAlternative;

  /// 백엔드가 내린 경로 계단 판정(#2590). 판정 원천은 백엔드 하나이고 화면은 이
  /// 값을 표시만 한다. 판정 필드가 없는 응답(레거시 백엔드)과 로컬 폴백 결과에서는
  /// 비어 있으며, 그때만 [stairAccessLabel]이 스텝 원자료로 폴백한다.
  final String stairAccess;

  bool get hasOfficialOdFareQuote => officialOdFareQuote != null;

  int get accessibilityScore => _accessibilityScore ?? score;

  int get burdenCost => _burdenCost ?? score;

  int get estimatedDurationSeconds {
    return _estimatedDurationSeconds ??
        steps.fold<int>(
          0,
          (sum, step) =>
              sum +
              (step.estimatedMinutes < 0 ? 0 : step.estimatedMinutes * 60),
        );
  }

  List<String> get recommendationReasonLabels {
    if (recommendationReasons.isEmpty) {
      return const [];
    }
    return const ['선택한 길을 따라 안내합니다.'];
  }

  List<String> get blockedReasonLabels {
    return [
      ...blockedReasons.map(_routeBlockedReasonLabel),
      if (nextServiceTime.isNotEmpty)
        _routeNextServiceTimeLabel(nextServiceTime),
    ];
  }

  String get stairAccessLabel {
    return _routeStairAccessLabel(
      stairAccess.isEmpty
          ? _routeStairAccessFromSteps(steps)
          : _normalizeRouteStairState(stairAccess),
    );
  }

  int get walkingDistanceMeters {
    return _walkingDistanceMeters ??
        steps.fold<int>(
          0,
          (sum, step) => step.isWalkingStep ? sum + step.distanceMeters : sum,
        );
  }

  int get transferCount {
    if (_transferCount != null) {
      return _transferCount;
    }
    final typedTransfers = steps.where(
      (step) => _isRouteTransferStepType(step.stepType),
    );
    if (typedTransfers.isNotEmpty) {
      return typedTransfers.length;
    }
    var previousLine = '';
    var changes = 0;
    for (final step in movementSteps) {
      final line = step.lineId.isNotEmpty ? step.lineId : step.lineName;
      if (line.isEmpty) {
        continue;
      }
      if (previousLine.isNotEmpty && previousLine != line) {
        changes += 1;
      }
      previousLine = line;
    }
    return changes;
  }

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  String get statusLabel {
    return switch (status) {
      'FOUND' => '경로를 찾았습니다',
      'BLOCKED' => '안내할 수 있는 경로가 없습니다',
      _ => '경로 상태를 확인하고 있어요',
    };
  }

  String get scoreLabel => burdenLevelLabel;

  String get lineLabel => lineName.isEmpty ? '노선 미확인' : lineName;

  bool get isBlocked => status == 'BLOCKED';

  bool get needsConfirmation => !isBlocked && status != 'FOUND';

  bool get isLocalResult => routeSearchId.startsWith('local-');

  String get sourceNotice {
    if (isLocalResult && etaSource == 'STATIC_LOCAL') {
      final updatedAt = sourceUpdatedAt.trim();
      final freshness = updatedAt.isEmpty
          ? ''
          : ' · ${_routeDateLabel(updatedAt)}';
      return '예상 소요시간: 저장된 데이터 기준$freshness';
    }
    return '예상 소요시간: ${routeEtaSourceLabel(etaSource)}';
  }

  /// #1933 E: 결과-우선 헤더용 짧은 안내. 강등 사다리의 정직함(저장된 데이터
  /// 기준·실시간/시간표 미표기)은 그대로 두되, "예상 소요시간:" 접두와 긴 날짜
  /// 문장을 떼어 작은 캡션 한 줄로 만든다. 시맨틱·기타 문맥은 `sourceNotice` 유지.
  String get sourceNoticeCaption => routeEtaSourceLabel(etaSource);

  String get etaBadgeLabel => routeEtaSourceLabel(etaSource);

  String get accessibilityBadgeLabel {
    if (isBlocked) {
      return '엘리베이터 상태를 살펴봐 주세요';
    }
    final risk = accessibilityRiskLevel.trim().toUpperCase();
    if (risk == 'HIGH' ||
        risk == 'UNKNOWN' ||
        steps.any((step) => step.requiresAccessibilityCheck)) {
      return '엘리베이터 상태를 살펴봐 주세요';
    }
    if (stairAccessLabel == '계단 없는 길이에요') {
      return '계단 없는 경로 확인';
    }
    return '일부 이동 정보를 살펴봐 주세요';
  }

  String get transferBadgeLabel {
    if (hasOutOfStationTransfer) {
      return '역 밖 환승';
    }
    final slackSeconds = transferSlackSeconds;
    if (slackSeconds == null) {
      return '';
    }
    return slackSeconds <= 90 ? '환승 빠듯함' : '환승 여유 충분';
  }

  List<String> get badgeLabels {
    return [
      etaBadgeLabel,
      accessibilityBadgeLabel,
      transferBadgeLabel,
    ].where((label) => label.trim().isNotEmpty).toList(growable: false);
  }

  /// 표시용 이름만 채워 넣은 사본. 온라인 결과는 화면에 닿기 전 반드시 이 경로를
  /// 지나므로([OnlineFirstRouteSearchRepository.searchRoute]), **여기서 옮기지 않은
  /// 필드는 화면에 도달하지 못하고 기본값으로 되돌아간다.** 필드를 더할 때 이 목록에
  /// 함께 더한다.
  ///
  /// `route_search_test.dart`의 소스 가드가 생성자 필드가 전부 나타나는지, 그리고 그
  /// 값이 원래 필드나 이 메서드의 파라미터를 참조하는지까지 본다. 그 이상(옮긴 값이
  /// 의미상 맞는지)은 가드의 범위 밖이다.
  RouteSearchResult withDisplayLabels({
    String? originStationName,
    String? destinationStationName,
    String? lineName,
    List<RouteSearchStep>? steps,
    String? etaSource,
    OfficialOdFareQuote? officialOdFareQuote,
    RouteObjective? objective,
    RouteSearchResult? stepFreeAlternative,
  }) {
    return RouteSearchResult(
      routeSearchId: routeSearchId,
      queryIdentity: queryIdentity,
      candidateIdentity: candidateIdentity,
      providerRouteSearchId: providerRouteSearchId,
      providerItineraryId: providerItineraryId,
      originStationId: originStationId,
      originStationName: originStationName ?? this.originStationName,
      destinationStationId: destinationStationId,
      destinationStationName:
          destinationStationName ?? this.destinationStationName,
      mobilityType: mobilityType,
      constraintMode: constraintMode,
      status: status,
      lineId: lineId,
      lineName: lineName ?? this.lineName,
      score: score,
      accessibilityScore: _accessibilityScore,
      burdenCost: _burdenCost,
      estimatedDurationSeconds: _estimatedDurationSeconds,
      walkingDistanceMeters: _walkingDistanceMeters,
      transferCount: _transferCount,
      evidenceSummary: evidenceSummary,
      steps: steps ?? this.steps,
      warnings: warnings,
      recommendationReasons: recommendationReasons,
      blockedReasons: blockedReasons,
      createdAt: createdAt,
      etaSource: etaSource ?? this.etaSource,
      etaConfidence: etaConfidence,
      accessibilityRiskLevel: accessibilityRiskLevel,
      transferSlackSeconds: transferSlackSeconds,
      hasOutOfStationTransfer: hasOutOfStationTransfer,
      commercialEtaEligible: commercialEtaEligible,
      sourceUpdatedAt: sourceUpdatedAt,
      officialOdFareQuote: officialOdFareQuote ?? this.officialOdFareQuote,
      supportsRefresh: supportsRefresh,
      nextServiceTime: nextServiceTime,
      transportScope: transportScope,
      objective: objective ?? this.objective,
      departureTimeIso: departureTimeIso,
      arrivalTimeIso: arrivalTimeIso,
      officialFare: officialFare,
      stepFreeAlternative: stepFreeAlternative ?? this.stepFreeAlternative,
      stairAccess: stairAccess,
    );
  }

  RouteSearchStep? get arrivalGuidanceStep {
    for (final step in steps.reversed) {
      final isDestinationAccessStep =
          step.requiresAccessibilityCheck &&
          step.fromStationId == destinationStationId &&
          step.toStationId == destinationStationId;
      if (isDestinationAccessStep) {
        return step;
      }
    }
    return null;
  }

  List<RouteSearchStep> get movementSteps {
    final arrivalStep = arrivalGuidanceStep;
    if (arrivalStep == null) {
      return steps;
    }
    return steps.where((step) => !identical(step, arrivalStep)).toList();
  }

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get comfortLabel {
    if (isBlocked) {
      return '다른 경로 필요';
    }
    return burdenLevelLabel;
  }

  String get guidanceLabel {
    if (isBlocked) {
      return '현재 조건으로 안내 어려움';
    }
    if (status == 'FOUND' && warnings.isEmpty) {
      return '안내 가능';
    }
    return '확인 후 이동';
  }

  IconData get guidanceIcon {
    if (isBlocked) {
      return Icons.priority_high;
    }
    return guidanceLabel == '안내 가능' ? Icons.check_circle : Icons.warning_amber;
  }

  String get attentionLabel {
    if (isBlocked) {
      return '안내 불가 이유';
    }
    if (needsConfirmation) {
      return '살펴볼 내용';
    }
    return warnings.isEmpty ? '주의 안내가 없어요' : '주의 안내 보기';
  }

  // 여러 주의 코드를 케이스별 카드로 누적하지 않고 각주 한 줄로 합친다(#1577).
  // 같은 문구는 한 번만 남긴다.
  String get warningNoticeText {
    if (warnings.isEmpty) {
      return '';
    }
    final seen = <String>{};
    final messages = <String>[];
    for (final warning in warnings) {
      final message = warning.userMessage;
      if (message.isEmpty || !seen.add(message)) {
        continue;
      }
      messages.add(message);
    }
    return messages.join(' · ');
  }

  String get semanticLabel {
    // 결과 첫 문장은 사용자가 이동 가능 여부를 바로 판단할 수 있게 구성한다.
    final parts = <String>[
      '경로 검색 결과',
      guidanceLabel,
      mobilityLabel,
      summaryTitle,
      lineLabel,
      comfortLabel,
      stairAccessLabel,
      ...badgeLabels,
    ];
    if (!isBlocked && warnings.isNotEmpty) {
      parts.add(attentionLabel);
    }
    final safeRecommendationReasons = recommendationReasonLabels;
    if (!isBlocked && safeRecommendationReasons.isNotEmpty) {
      parts.add('추천 이유 ${safeRecommendationReasons.join(', ')}');
    }
    final arrivalStep = arrivalGuidanceStep;
    if (arrivalStep != null) {
      parts.add('도착 안내 ${arrivalStep.userDescription}');
    }
    final safeBlockedReasons = blockedReasonLabels;
    if (safeBlockedReasons.isNotEmpty) {
      parts.add('$attentionLabel ${safeBlockedReasons.join(', ')}');
    }
    if (isBlocked) {
      parts.add('다른 방법 $_routeSearchFailureNextAction');
    }
    if (warnings.isNotEmpty) {
      parts.add('주의 $warningNoticeText');
    }
    if (sourceNotice.isNotEmpty) {
      parts.add(sourceNotice);
    }
    final stepsForGuidance = movementSteps;
    if (stepsForGuidance.isNotEmpty) {
      parts.add(
        '이동 안내 ${stepsForGuidance.map((step) => step.semanticGuidanceLabel).join(', ')}',
      );
    }
    // 면책·주의 안내는 '안전 안내' 한 곳으로 통합한다. '이동 전 살펴보기'는
    // 같은 의미의 이중 고지라 시맨틱에서 제거한다(#1577).
    parts.add('안전 안내 $_routeSafetyGuidanceNotice');
    return parts.join(', ');
  }

  String get burdenLevelLabel {
    if (isBlocked) {
      return '이동 부담 미확인';
    }
    if (movementSteps.isEmpty) {
      return '이동 부담 미확인';
    }
    if (_hasHighBurdenFact) {
      return '이동 부담 높음';
    }
    if (_hasMediumBurdenFact) {
      return '이동 부담 보통';
    }
    return '이동 부담 낮음';
  }

  bool get _hasHighBurdenFact {
    return walkingDistanceMeters >= 1000 ||
        transferCount >= 2 ||
        movementSteps.any(
          (step) =>
              step.includesStairs || _routeStepStairState(step) == 'stairOnly',
        );
  }

  bool get _hasMediumBurdenFact {
    return walkingDistanceMeters >= 400 ||
        transferCount >= 1 ||
        movementSteps.any(
          (step) =>
              step.requiresAccessibilityCheck ||
              _routeStepStairState(step) == 'unknown',
        );
  }
}

class RouteRefreshResult {
  const RouteRefreshResult({
    required this.routeSearchId,
    required this.status,
    required this.result,
    required this.refreshedAt,
    required this.etaSource,
    required this.etaConfidence,
    required this.sourceLabel,
    this.reasonCodes = const [],
  });

  factory RouteRefreshResult.fromJson(Map<String, Object?> json) {
    final route = json['route'];
    if (route is! Map<String, Object?>) {
      throw const FormatException('Invalid route refresh payload');
    }
    return RouteRefreshResult(
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      status: _requiredRouteString(json, 'status'),
      result: RouteSearchResult.fromJson(route),
      refreshedAt: _requiredRouteString(json, 'refreshedAt'),
      etaSource: _requiredRouteString(json, 'etaSource'),
      etaConfidence: _requiredRouteString(json, 'etaConfidence'),
      sourceLabel: _requiredRouteString(json, 'sourceLabel'),
      reasonCodes: _routeStringList(
        json['reasonCodes'],
        'route refresh reason',
      ),
    );
  }

  final String routeSearchId;
  final String status;
  final RouteSearchResult result;
  final String refreshedAt;
  final String etaSource;
  final String etaConfidence;
  final String sourceLabel;
  final List<String> reasonCodes;

  String get userMessage {
    final statusLabel = switch (status) {
      'UPDATED_ETA' => '도착 시간을 새로 확인했어요.',
      'UNCHANGED' => '도착 시간이 그대로예요.',
      'STALE_FALLBACK' => '실시간 정보가 늦어 계획 시간으로 안내해요.',
      'REROUTE_REQUIRED' => '경로를 다시 찾아야 해요.',
      _ => '도착 시간을 확인했어요.',
    };
    final confidenceLabel = switch (etaConfidence) {
      'HIGH' => '신뢰도 높음',
      'MEDIUM' => '신뢰도 보통',
      'LOW' => '신뢰도 낮음',
      _ => '신뢰도 확인 중',
    };
    final source = sourceLabel.trim();
    return source.isEmpty
        ? '$statusLabel · $confidenceLabel'
        : '$statusLabel · $source · $confidenceLabel';
  }
}

/// Route V2 itinerary 한 건을 화면 모델로 옮긴다. 대표와 무단차 대안이 같은
/// 변환을 공유해 전환 시 대안이 그대로 주 결과가 된다(#2582).
RouteSearchResult _routeSearchResultFromV2Itinerary({
  required RouteSearchV2Result result,
  required RouteSearchV2Itinerary itinerary,
  required RouteObjective objective,
  required RouteQueryIdentity? queryIdentity,
  RouteSearchResult? stepFreeAlternative,
}) {
  final lineId = _routeV2SummaryLineId(itinerary.legs);
  return RouteSearchResult(
    routeSearchId: _routeV2RouteSearchId(itinerary.itineraryId),
    queryIdentity: queryIdentity,
    candidateIdentity: queryIdentity == null || itinerary.legs.isEmpty
        ? null
        : RouteCandidateIdentity(
            query: queryIdentity,
            legs: [
              for (final leg in itinerary.legs)
                RouteCandidateLegSignature(
                  stepType: leg.legType,
                  fromStationId: leg.fromStationId,
                  toStationId: leg.toStationId,
                  fromNodeId: leg.fromNodeId,
                  toNodeId: leg.toNodeId,
                  lineId: leg.lineId,
                  serviceClass: leg.serviceClass ?? '',
                  servicePattern: leg.servicePattern ?? '',
                ),
            ],
          ),
    providerRouteSearchId: '',
    providerItineraryId: itinerary.itineraryId,
    originStationId: result.originStationId,
    originStationName: result.originStationId,
    destinationStationId: result.destinationStationId,
    destinationStationName: result.destinationStationId,
    mobilityType: result.mobilityType,
    constraintMode: result.constraintMode,
    status: _routeV2Status(itinerary.status),
    lineId: lineId,
    lineName: lineId,
    score: _scoreFromRisk(itinerary.accessibilityRisk),
    burdenCost: itinerary.durationSeconds,
    estimatedDurationSeconds: itinerary.durationSeconds,
    walkingDistanceMeters: itinerary.walkingDistanceMeters,
    transferCount: itinerary.transferCount,
    evidenceSummary: [
      'ETA_${itinerary.etaSource}',
      'CONFIDENCE_${itinerary.etaConfidence}',
    ],
    steps: itinerary.legs
        .asMap()
        .entries
        .map((entry) => RouteSearchStep.fromV2(entry.key + 1, entry.value))
        .toList(growable: false),
    warnings: itinerary.accessibilityRisk.reasonCodes
        .map(
          (code) => RouteSearchWarning(
            code: code,
            message: _routeV2RiskMessage(code),
          ),
        )
        .toList(growable: false),
    recommendationReasons: itinerary.commercialEtaEligible
        ? const ['실시간 도착 정보를 반영했어요.']
        : const [],
    blockedReasons: itinerary.status == 'FOUND'
        ? const []
        : itinerary.accessibilityRisk.reasonCodes.isEmpty
        ? [itinerary.status]
        : itinerary.accessibilityRisk.reasonCodes,
    createdAt: result.departureTime,
    etaSource: itinerary.etaSource,
    etaConfidence: itinerary.etaConfidence,
    accessibilityRiskLevel: itinerary.accessibilityRisk.riskLevel,
    transferSlackSeconds: _routeV2TransferSlackSeconds(itinerary.legs),
    hasOutOfStationTransfer: itinerary.legs.any(
      (leg) => leg.legType == 'OUT_OF_STATION_TRANSFER',
    ),
    commercialEtaEligible: itinerary.commercialEtaEligible,
    sourceUpdatedAt: result.departureTime,
    supportsRefresh: false,
    transportScope: RouteTransportScope.subwayAndItxCheongchun,
    objective: objective,
    departureTimeIso: result.departureTime,
    arrivalTimeIso:
        itinerary.realtimeArrivalTime ?? itinerary.plannedArrivalTime,
    officialFare: itinerary.officialFare,
    stepFreeAlternative: stepFreeAlternative,
    stairAccess: itinerary.stairAccess,
  );
}

/// 요청 objective의 대표 itinerary와, 함께 노출할 무단차 대안(있으면)을 고른다.
///
/// 대안은 없는 것이 정상이므로 대표 선택과 달리 fail closed 대상이 아니다(#2582).
({RouteSearchV2Itinerary primary, RouteSearchV2Itinerary? stepFreeAlternative})
_selectRouteV2Itinerary(
  List<RouteSearchV2Itinerary> itineraries,
  RouteObjective objective,
) {
  final foundItineraries = itineraries
      .where((itinerary) => itinerary.status == 'FOUND')
      .toList(growable: false);
  final primary = _selectRouteV2Primary(
    itineraries: itineraries,
    foundItineraries: foundItineraries,
    objective: objective,
  );
  return (
    primary: primary,
    stepFreeAlternative: _selectRouteV2StepFreeAlternative(
      foundItineraries: foundItineraries,
      primary: primary,
    ),
  );
}

/// objective-tagged 대표 itinerary 중 현재 목표에 맞는 것을 고른다. 백엔드가 두
/// objective를 하나로 dedupe하면 그 하나가 두 태그를 모두 달고 있어 어느 목표에서도
/// 선택된다. FOUND itinerary가 전부 무태그(레거시)일 때만 첫 FOUND, 그마저 없으면 첫
/// itinerary로 폴백해 기존 동작을 보존한다. 태그가 하나라도 있는데 요청 objective와
/// 매칭되는 FOUND가 없으면 silent fallback(계약 위반)을 피해 payload 오류로 fail
/// closed한다(generic unavailable 흐름으로 흐른다).
RouteSearchV2Itinerary _selectRouteV2Primary({
  required List<RouteSearchV2Itinerary> itineraries,
  required List<RouteSearchV2Itinerary> foundItineraries,
  required RouteObjective objective,
}) {
  for (final itinerary in foundItineraries) {
    if (itinerary.matchesObjective(objective)) {
      return itinerary;
    }
  }
  final hasTaggedFound = foundItineraries.any(
    (itinerary) => itinerary.objectiveTags.isNotEmpty,
  );
  if (hasTaggedFound) {
    throw const FormatException(
      'Route v2 FOUND itineraries missing requested objective tag',
    );
  }
  return itineraries.firstWhere(
    (candidate) => candidate.status == 'FOUND',
    orElse: () => itineraries.first,
  );
}

/// 대표로 뽑히지 않은 [_stepFreePreferredObjectiveTag] 후보를 고른다. 백엔드가
/// 최대 1건만 붙이므로 첫 매칭이 그 1건이다(#2560 계약).
RouteSearchV2Itinerary? _selectRouteV2StepFreeAlternative({
  required List<RouteSearchV2Itinerary> foundItineraries,
  required RouteSearchV2Itinerary primary,
}) {
  for (final itinerary in foundItineraries) {
    if (!identical(itinerary, primary) &&
        itinerary.objectiveTags.contains(_stepFreePreferredObjectiveTag)) {
      return itinerary;
    }
  }
  return null;
}

int _scoreFromRisk(RouteSearchV2AccessibilityRisk risk) {
  final penalty =
      risk.stairCount * 30 +
      risk.unavailableFacilityCount * 30 +
      risk.generatedConnectorCount * 15 +
      risk.unknownAccessibilityCount * 15 +
      risk.staleDataCount * 10 +
      risk.lowConfidenceCount * 10;
  return (100 - penalty).clamp(0, 100).toInt();
}

String _routeV2DepartureTimeNow() {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  return '${timestamp.split('.').first}Z';
}

String _routeV2RouteSearchId(String itineraryId) {
  for (final suffix in const ['-primary', '-review']) {
    if (itineraryId.endsWith(suffix)) {
      return itineraryId.substring(0, itineraryId.length - suffix.length);
    }
  }
  return itineraryId;
}

String _routeV2Status(String status) {
  return status == 'FOUND' ? 'FOUND' : 'BLOCKED';
}

String _routeV2SummaryLineId(List<RouteSearchV2Leg> legs) {
  for (final leg in legs) {
    if (leg.legType == 'RIDE' && leg.lineId.trim().isNotEmpty) {
      return leg.lineId;
    }
  }
  for (final leg in legs) {
    if (leg.lineId.trim().isNotEmpty) {
      return leg.lineId;
    }
  }
  return '';
}

bool _routeV2RiskRequiresCheck(RouteSearchV2AccessibilityRisk risk) {
  return risk.unknownAccessibilityCount > 0 ||
      risk.generatedConnectorCount > 0 ||
      risk.staleDataCount > 0 ||
      risk.lowConfidenceCount > 0 ||
      risk.unavailableFacilityCount > 0;
}

/// 판정 필드(`stairAccess`)가 없는 레거시 응답에서만 쓰는 leg 폴백 판정.
///
/// 미확인 신호를 하나라도 보면 `unknown`으로 떨어지므로 무단차로 과대 표기되지
/// 않는다(fail closed). 승차 leg가 `unknown`으로 잡히는 것이 #2590의 증상이며,
/// 판정 필드를 싣는 백엔드에서는 이 경로를 타지 않는다.
String _routeV2StairAccessState(RouteSearchV2AccessibilityRisk risk) {
  if (risk.stairCount > 0) {
    return 'stairOnly';
  }
  if (_routeV2RiskRequiresCheck(risk)) {
    return 'unknown';
  }
  return 'stepFree';
}

String _routeV2StepType(String legType) {
  return switch (legType) {
    'ACCESS' => 'entry',
    'EGRESS' => 'exit',
    'TRANSFER' => 'transfer',
    'RIDE' => 'ride',
    _ => legType.toLowerCase(),
  };
}

String _routeV2RiskMessage(String code) {
  return switch (code) {
    'STAIR_ONLY_ACCESS' => '계단 구간이 포함될 수 있어요.',
    'ACCESSIBILITY_CHECK_REQUIRED' => '현장 접근성 확인이 필요해요.',
    'STALE_ACCESSIBILITY_DATA' => '시설 상태 안내가 오래됐을 수 있어요.',
    'LOW_DATA_CONFIDENCE' => '경로 신뢰도가 낮아 현장 확인이 필요해요.',
    _ => '경로 상태를 현장에서 확인해 주세요.',
  };
}

String _routeV2LegTitle(RouteSearchV2Leg leg) {
  return switch (leg.legType) {
    'RIDE' => '${leg.fromStationId}에서 ${leg.toStationId}까지 이동',
    'TRANSFER' => '${leg.fromStationId}에서 환승',
    'ACCESS' => '${leg.fromStationId} 승강장 접근',
    'EGRESS' => '${leg.toStationId} 출구 접근',
    _ => '${leg.fromStationId}에서 ${leg.toStationId}까지 이동',
  };
}

String _carDoorFacilityLabel(String facilityType) {
  return switch (facilityType.toUpperCase()) {
    'STAIR' => '계단 가까움',
    'ELEVATOR' => '엘리베이터 가까움',
    'ESCALATOR' => '에스컬레이터 가까움',
    'TRANSFER' => '빠른 환승',
    _ => '',
  };
}

class RouteSearchStep {
  const RouteSearchStep({
    required this.sequence,
    this.stepType = '',
    required this.title,
    required this.description,
    required this.lineId,
    required this.lineName,
    required this.fromStationId,
    required this.toStationId,
    required this.estimatedMinutes,
    required this.distanceMeters,
    required this.includesStairs,
    this.stairAccessState = '',
    required this.requiresAccessibilityCheck,
    this.actionTitle = '',
    this.actionDetail = '',
    this.reason = '',
    this.evidenceSources = const [],
    this.timeSource = '',
    this.distanceSource = '',
    this.confidenceLabel = '',
    this.plannedArrivalTimeIso = '',
    this.realtimeArrivalTimeIso = '',
    this.plannedDepartureTimeIso = '',
    this.realtimeDepartureTimeIso = '',
    this.carDoorCarNumber,
    this.carDoorDoorNumber,
    this.carDoorFacilityType = '',
    this.serviceClass,
    this.servicePattern,
  });

  factory RouteSearchStep.fromJson(Map<String, Object?> json) {
    final title = _requiredRouteString(json, 'title');
    final description = _requiredRouteString(json, 'description');
    final includesStairs = _requiredRouteBool(json, 'includesStairs');
    return RouteSearchStep(
      sequence: _requiredRouteInt(json, 'sequence'),
      stepType: _optionalRouteString(json, 'stepType'),
      title: title,
      description: description,
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      fromStationId: _optionalRouteString(json, 'fromStationId'),
      toStationId: _optionalRouteString(json, 'toStationId'),
      estimatedMinutes: _requiredRouteInt(json, 'estimatedMinutes'),
      distanceMeters: _requiredRouteInt(json, 'distanceMeters'),
      includesStairs: includesStairs,
      stairAccessState: _routeStepStairAccessStateFromJson(
        json,
        includesStairs,
      ),
      requiresAccessibilityCheck: _requiredRouteBool(
        json,
        'requiresAccessibilityCheck',
      ),
      actionTitle: _optionalRouteString(json, 'actionTitle'),
      actionDetail: _optionalRouteString(json, 'actionDetail').isEmpty
          ? description
          : _optionalRouteString(json, 'actionDetail'),
      reason: _optionalRouteString(json, 'reason'),
      evidenceSources: _routeStringList(
        json['evidenceSources'],
        'route step evidence source',
      ),
      timeSource: _optionalRouteString(json, 'timeSource', fallback: 'UNKNOWN'),
      distanceSource: _optionalRouteString(
        json,
        'distanceSource',
        fallback: 'UNKNOWN',
      ),
      confidenceLabel: _optionalRouteString(
        json,
        'confidenceLabel',
        fallback: '',
      ),
    );
  }

  factory RouteSearchStep.fromV2(int sequence, RouteSearchV2Leg leg) {
    final waitOrSlackSeconds = leg.waitTimeSeconds > leg.slackSeconds
        ? leg.waitTimeSeconds
        : leg.slackSeconds;
    final minutes = ((leg.durationSeconds + waitOrSlackSeconds) / 60).ceil();
    final title = _routeV2LegTitle(leg);
    final stairAccessState = leg.stairAccess.isEmpty
        ? _routeV2StairAccessState(leg.accessibilityRisk)
        : _normalizeRouteStairState(leg.stairAccess);
    return RouteSearchStep(
      sequence: sequence,
      stepType: _routeV2StepType(leg.legType),
      title: title,
      description: title,
      lineId: leg.lineId,
      lineName: leg.lineId,
      fromStationId: leg.fromStationId,
      toStationId: leg.toStationId,
      estimatedMinutes: minutes,
      distanceMeters: leg.distanceMeters,
      includesStairs: leg.accessibilityRisk.stairCount > 0,
      stairAccessState: stairAccessState,
      // 계단 사실에서 파생하지 않는다(#2590). 계단이 확인된 구간도 근거가 없으면 확인
      // 안내가 함께 붙어야 하므로, 백엔드가 세운 표기를 그대로 쓴다. 그 필드가 없는
      // 레거시 응답에서만 원자료로 폴백하고, 그 폴백은 승차 leg를 과대 표기하는
      // 방향이라 표시가 근거보다 강해지지 않는다.
      requiresAccessibilityCheck:
          leg.requiresAccessibilityCheck ??
          _routeV2RiskRequiresCheck(leg.accessibilityRisk),
      actionTitle: '',
      actionDetail: title,
      reason: leg.etaSource,
      timeSource: leg.etaSource,
      distanceSource: 'BACKEND_V2',
      confidenceLabel: leg.confidence,
      plannedArrivalTimeIso: leg.plannedArrivalTime,
      realtimeArrivalTimeIso: leg.realtimeArrivalTime ?? '',
      plannedDepartureTimeIso: leg.plannedDepartureTime,
      realtimeDepartureTimeIso: leg.realtimeDepartureTime ?? '',
      serviceClass: leg.serviceClass,
      servicePattern: leg.servicePattern,
    );
  }

  final int sequence;
  final String stepType;
  final String title;
  final String description;
  final String lineId;
  final String lineName;
  final String fromStationId;
  final String toStationId;
  final int estimatedMinutes;
  final int distanceMeters;
  final bool includesStairs;
  final String stairAccessState;
  final bool requiresAccessibilityCheck;

  /// 하차 알림(#1766)용 절대 도착 시각(ISO). V2 승차 leg에서만 채워지고,
  /// 그 외 경로/step에서는 빈 문자열이다.
  final String plannedArrivalTimeIso;
  final String realtimeArrivalTimeIso;
  final String plannedDepartureTimeIso;
  final String realtimeDepartureTimeIso;
  final String actionTitle;
  final String actionDetail;
  final String reason;
  final List<String> evidenceSources;
  final String timeSource;
  final String distanceSource;
  final String confidenceLabel;

  /// 오프라인 로컬 catalog의 빠른 하차 안내(#2066)용. 로컬 승차 step에서만 채워지고,
  /// 데이터가 없으면 null(칸·문)·빈 문자열(시설)로 남아 안내 줄을 그리지 않는다.
  final int? carDoorCarNumber;
  final int? carDoorDoorNumber;
  final String carDoorFacilityType;

  /// 승차 leg의 운행 클래스·운행종별(실제 운행 정보). 급행 배지 노출 판단에만 쓰고,
  /// 선택 컨트롤·요청 identity에는 싣지 않는다. 승차가 아닌 step에서는 null이다.
  final String? serviceClass;
  final String? servicePattern;

  /// 승차 정보 영역에 `급행` 배지를 노출하는 유일한 조건.
  bool get isSubwayExpress =>
      serviceClass == 'SUBWAY' && servicePattern == 'EXPRESS';

  /// 승차 정보 영역에 `ITX-청춘` 서비스 식별 배지를 노출하는 유일한 조건. 별도
  /// 운임의 좌석 지정 서비스라 같은 노선의 일반 전동차와 구분해 표시한다.
  bool get isItxCheongchun => serviceClass == 'ITX_CHEONGCHUN';

  RouteSearchStep withDisplayLabels({
    required String title,
    required String lineName,
    required String actionDetail,
    String? plannedArrivalTimeIso,
    String? realtimeArrivalTimeIso,
  }) {
    return RouteSearchStep(
      sequence: sequence,
      stepType: stepType,
      title: title,
      description: title,
      lineId: lineId,
      lineName: lineName,
      fromStationId: fromStationId,
      toStationId: toStationId,
      estimatedMinutes: estimatedMinutes,
      distanceMeters: distanceMeters,
      includesStairs: includesStairs,
      stairAccessState: stairAccessState,
      requiresAccessibilityCheck: requiresAccessibilityCheck,
      actionTitle: actionTitle,
      actionDetail: actionDetail,
      reason: reason,
      evidenceSources: evidenceSources,
      timeSource: timeSource,
      distanceSource: distanceSource,
      confidenceLabel: confidenceLabel,
      plannedArrivalTimeIso:
          plannedArrivalTimeIso ?? this.plannedArrivalTimeIso,
      realtimeArrivalTimeIso:
          realtimeArrivalTimeIso ?? this.realtimeArrivalTimeIso,
      plannedDepartureTimeIso: plannedDepartureTimeIso,
      realtimeDepartureTimeIso: realtimeDepartureTimeIso,
      carDoorCarNumber: carDoorCarNumber,
      carDoorDoorNumber: carDoorDoorNumber,
      carDoorFacilityType: carDoorFacilityType,
      serviceClass: serviceClass,
      servicePattern: servicePattern,
    );
  }

  String get userReason => _routeStepReasonLabel(reason);

  String get userTitle => _routeStepTitleLabel(title);

  String get userActionTitle => _routeStepTitleLabel(actionTitle);

  String get userDescription => _routeStepDetailLabel(stepType: stepType);

  /// 구간 요약 줄(시간·거리·계단). **[requiresAccessibilityCheck]는 여기에 문구로
  /// 나오지 않는다.** 구간마다 확인 안내를 붙이면 확인된 구간과 아닌 구간이 뒤섞여
  /// 읽히므로 표기를 경로 단위로 모은다 — 확인이 필요한 스텝이 하나라도 있으면
  /// [RouteSearchResult.accessibilityBadgeLabel]이 그 사실을 낸다.
  ///
  /// 판정 자체는 지우지 않는다. [RouteSearchResult.arrivalGuidanceStep]·
  /// [RouteSearchResult.burdenLevelLabel]·[RouteSearchResult.accessibilityBadgeLabel]이
  /// 계속 이 값을 읽는다.
  String get burdenLabel {
    final labels = <String>[
      _routeDurationLabel(estimatedMinutes),
      _routeDistanceLabel(distanceMeters),
      if (includesStairs) '계단 포함',
    ];
    return labels.join(' · ');
  }

  bool get hasCarDoorHint =>
      carDoorCarNumber != null && carDoorDoorNumber != null;

  String get carDoorHintLabel {
    final suffix = _carDoorFacilityLabel(carDoorFacilityType);
    final base = '빠른 하차 $carDoorCarNumber-$carDoorDoorNumber칸';
    return suffix.isEmpty ? base : '$base · $suffix';
  }

  String get carDoorHintSemanticLabel {
    final suffix = _carDoorFacilityLabel(carDoorFacilityType);
    final base = '빠른 하차 $carDoorCarNumber번 칸 $carDoorDoorNumber번 문';
    return suffix.isEmpty ? base : '$base, $suffix';
  }

  String get semanticGuidanceLabel {
    final safeReason = _routeStepReasonLabel(reason);
    final labels = <String>[
      '$sequence번 ${stepType == 'waypoint' ? userTitle : (userActionTitle.isEmpty ? userTitle : userActionTitle)}',
      _routeStepDetailLabel(stepType: stepType),
      if (safeReason.isNotEmpty) safeReason,
      if (stepType != 'waypoint') burdenLabel,
      if (stepType != 'waypoint' && confidenceLabel.isNotEmpty) confidenceLabel,
      if (stepType != 'waypoint' && hasMetricSourceMetadata) metricSourceLabel,
    ];
    return labels.join(', ');
  }

  bool get hasMetricSourceMetadata =>
      timeSource.isNotEmpty ||
      distanceSource.isNotEmpty ||
      confidenceLabel.isNotEmpty;

  bool get isWalkingStep {
    return switch (stepType) {
      'entry' ||
      'exit' ||
      'transfer' ||
      'inStationTransfer' ||
      'outOfStationTransfer' ||
      'walkway' ||
      'elevator' ||
      'ramp' ||
      'stair' ||
      'escalator' ||
      'facilityConnector' ||
      'internal' => true,
      'ride' => false,
      'waypoint' => false,
      _ => requiresAccessibilityCheck,
    };
  }

  String get metricSourceLabel {
    if (!hasMetricSourceMetadata) {
      return '';
    }
    if (timeSource == 'ESTIMATED_CONSTANT' ||
        distanceSource == 'ESTIMATED_CONSTANT') {
      // 값만 남긴다. 예상치임의 면책은 결과 하단 안전 안내 각주 1줄이 담당(#1577).
      return '예상 시간·거리예요';
    }
    if (timeSource == 'UNKNOWN' || distanceSource == 'UNKNOWN') {
      return '시간·거리 정보 미확인';
    }
    if (timeSource == 'REALTIME') {
      return '실시간 도착 정보 기준이에요';
    }
    if (timeSource == 'PLANNED' || distanceSource == 'BACKEND_V2') {
      return '서버 경로 안내 기준이에요';
    }
    return '앱에 저장된 길 안내예요';
  }
}

String _routeDurationLabel(int estimatedMinutes) {
  if (estimatedMinutes <= 0) {
    return '시간 미확인';
  }
  return '약 $estimatedMinutes분';
}

String _routeDistanceLabel(int distanceMeters) {
  if (distanceMeters <= 0) {
    return '거리 미확인';
  }
  if (distanceMeters < 1000) {
    return '${distanceMeters}m';
  }

  final kilometers = distanceMeters / 1000;
  if (distanceMeters % 1000 == 0) {
    return '${kilometers.toStringAsFixed(0)}km';
  }
  return '${kilometers.toStringAsFixed(1)}km';
}

// 하드 블록(경로를 실제로 못 찾음)은 헤지가 아니라 결과이므로 별도 문구로 안내한다.
const _routeBlockedNoStepFreeRoute = '계단 없는 경로를 아직 찾지 못했어요.';
const _routeBlockedFacilityUnavailable = '꼭 필요한 시설을 지금 이용하기 어려워요.';
const _routeBlockedGeneric = '안내할 수 있는 경로를 아직 찾지 못했어요.';
const _routeBlockedNoTimetableService = '이 시간에는 운행하는 열차가 없어요.';

String _routeBlockedReasonLabel(String reason) {
  final normalizedReason = reason.trim().replaceAll('못했습니다.', '못했어요.');
  return switch (normalizedReason) {
    // 하드 블록.
    'STAIR_ONLY_ACCESS' => _routeBlockedNoStepFreeRoute,
    'FACILITY_UNAVAILABLE' => _routeBlockedFacilityUnavailable,
    'NO_TIMETABLE_SERVICE' => _routeBlockedNoTimetableService,
    // 불확실성 계열은 헤지 사전 한 벌로 위임한다(#1577).
    'STAIR_ONLY_ACCESS_UNKNOWN' => routeHedgeStepFreeUnknown,
    'GENERATED_CONNECTOR_UNVERIFIED' ||
    'ROUTE_GRAPH_UNKNOWN' => routeHedgeConnectivityUnknown,
    'ACCESSIBILITY_STATE_UNKNOWN' => routeHedgeAccessibilityUnknown,
    // 이미 번역된 라벨(레거시·재매핑·과거 문구)도 같은 사전으로 정규화해 멱등하게.
    _routeBlockedNoStepFreeRoute ||
    '계단 없는 경로를 찾지 못했어요.' => _routeBlockedNoStepFreeRoute,
    _routeBlockedFacilityUnavailable ||
    '필수 접근성 시설을 사용할 수 없습니다.' => _routeBlockedFacilityUnavailable,
    routeHedgeStepFreeUnknown ||
    '계단 없는 길인지 아직 알 수 없어요.' ||
    '계단 없는 동선 여부를 확인할 수 없습니다.' => routeHedgeStepFreeUnknown,
    routeHedgeAccessibilityUnknown ||
    '엘리베이터와 통로 상태를 아직 알 수 없어요.' ||
    '접근성 시설 이용 가능 여부를 확인할 수 없습니다.' => routeHedgeAccessibilityUnknown,
    routeHedgeConnectivityUnknown ||
    '길이 이어지는지 아직 확인하지 못했어요.' ||
    '경로 연결 정보를 확인할 수 없습니다.' => routeHedgeConnectivityUnknown,
    _ => _routeBlockedGeneric,
  };
}

String _routeNextServiceTimeLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 16) {
    return '다음 운행 시각을 확인해 주세요.';
  }
  return '다음 운행 ${trimmed.substring(0, 10)} ${trimmed.substring(11, 16)}';
}

String _routeStepReasonLabel(String reason) {
  if (reason.trim().isEmpty) {
    return '';
  }
  return '선택한 길을 따라 안내합니다.';
}

String _routeStepTitleLabel(String title) {
  return title.trim().replaceAll('접근성 정보', '엘리베이터와 통로 안내');
}

String _routeStepDetailLabel({required String stepType}) {
  return switch (stepType) {
    'entry' => '계단 없는 승강장 접근 동선을 확인해 이동합니다.',
    'exit' => '도착역에서 계단 없는 출구 동선을 확인합니다.',
    'transfer' || 'inStationTransfer' => '다음 노선으로 갈아탈 준비를 합니다.',
    'outOfStationTransfer' => '역 밖으로 이동해 다음 노선으로 갈아탑니다.',
    'walkway' => '확인된 통로를 따라 이동합니다.',
    'elevator' => '엘리베이터를 이용해 이동합니다.',
    'ramp' => '경사로를 따라 이동합니다.',
    'stair' => '계단 구간입니다. 계단 없는 조건에서는 안내하지 않습니다.',
    'escalator' => '에스컬레이터를 이용해 이동합니다.',
    'facilityConnector' => '역 시설 연결 동선을 따라 이동합니다.',
    'ride' => '열차를 이용해 이동합니다.',
    'waypoint' => '내리지 않고 이 역을 지나가요',
    _ => '안내된 순서대로 이동합니다.',
  };
}

bool _isRouteTransferStepType(String stepType) {
  return stepType == 'transfer' ||
      stepType == 'inStationTransfer' ||
      stepType == 'outOfStationTransfer';
}

int? _routeV2TransferSlackSeconds(List<RouteSearchV2Leg> legs) {
  final transferSlacks = legs
      .where(
        (leg) =>
            leg.legType == 'TRANSFER' ||
            leg.legType == 'IN_STATION_TRANSFER' ||
            leg.legType == 'LEGACY_TRANSFER' ||
            leg.legType == 'OUT_OF_STATION_TRANSFER',
      )
      .map((leg) => leg.slackSeconds)
      .toList(growable: false);
  if (transferSlacks.isEmpty) {
    return null;
  }
  transferSlacks.sort();
  return transferSlacks.first;
}

class RouteSearchWarning {
  const RouteSearchWarning({required this.code, this.message = ''});

  factory RouteSearchWarning.fromJson(Map<String, Object?> json) {
    return RouteSearchWarning(
      code: _requiredRouteString(json, 'code'),
      message: _optionalRouteString(json, 'message'),
    );
  }

  final String code;
  final String message;

  String get userMessage => routeWarningLabel(code);
}

String _routeStepStairAccessStateFromJson(
  Map<String, Object?> json,
  bool includesStairs,
) {
  final raw = _optionalRouteString(json, 'stairAccessState');
  if (raw.isEmpty) {
    return includesStairs ? 'stairOnly' : 'unknown';
  }
  return _normalizeRouteStairState(raw);
}

String _routeStepStairState(RouteSearchStep step) {
  if (step.includesStairs) {
    return 'stairOnly';
  }
  return _normalizeRouteStairState(step.stairAccessState);
}

String _normalizeRouteStairState(String value) {
  return switch (value.trim().toUpperCase()) {
    'STEP_FREE' || 'STEPFREE' => 'stepFree',
    'STAIR_ONLY' || 'STAIRONLY' => 'stairOnly',
    'NOT_APPLICABLE' || 'NOTAPPLICABLE' => 'notApplicable',
    _ => 'unknown',
  };
}

String _routeStairAccessLabel(String stairAccess) {
  return switch (stairAccess) {
    'stairOnly' => '계단 포함',
    'stepFree' => '계단 없는 길이에요',
    _ => '계단 여부를 확인하고 있어요',
  };
}

/// 판정 필드가 없는 응답(레거시 백엔드·기기 내 로컬 경로)에서 쓰는 유일한 폴백 판정.
///
/// 판정 규칙이 여러 벌로 갈리지 않도록 두 경로가 이 함수 하나만 쓴다. 격자는 백엔드
/// `StairAccess`와 같다: 계단 구간이 하나라도 있으면 `stairOnly`, 미확인이 있으면
/// `unknown`, 계단 개념이 적용되지 않는 구간(`notApplicable`)은 판정에 기여하지
/// 않는다. 스텝이 전부 `notApplicable`이면 계단 장벽이 놓인 구간이 하나도 없다는
/// 뜻이라 `stepFree`이고, 스텝이 아예 없으면 판정 근거 자체가 없어 `unknown`이다
/// (백엔드 `StairAccess.ofItineraryDisplay`도 같은 규칙으로 fail closed다).
///
/// **이 폴백은 백엔드 경로 판정의 복원이 아니다.** 경로 판정은 어느 구간에도 매달 수
/// 없는 경로 단위 경고까지 반영하는데 스텝에는 그 신호가 없다. 판정 필드가 실린
/// 응답에서 이 함수를 타면 표시가 실제 근거보다 강해질 수 있으므로, 호출은 판정
/// 필드가 비었을 때로만 제한한다. 레거시 응답에서는 승차 leg의 미확인 원자료가
/// 폴백을 `unknown`으로 떨어뜨려 그 방향으로는 새지 않는다.
String _routeStairAccessFromSteps(List<RouteSearchStep> steps) {
  if (steps.isEmpty) {
    return 'unknown';
  }
  var merged = 'notApplicable';
  for (final step in steps) {
    final state = _routeStepStairState(step);
    if (_routeStairAccessRank(state) > _routeStairAccessRank(merged)) {
      merged = state;
    }
  }
  return merged == 'notApplicable' ? 'stepFree' : merged;
}

int _routeStairAccessRank(String stairAccess) {
  return switch (stairAccess) {
    'stairOnly' => 3,
    'unknown' => 2,
    'stepFree' => 1,
    _ => 0,
  };
}

String _requiredRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

String _optionalRouteString(
  Map<String, Object?> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
  return fallback;
}

String? _optionalNullableRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  throw FormatException('Invalid route field: $key');
}

List<String> _routeStringList(Object? value, String label) {
  if (value == null) {
    return const [];
  }
  if (value is! List<Object?>) {
    throw FormatException('Invalid $label payload');
  }
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('Invalid $label payload');
        }
        return item.trim();
      })
      .toList(growable: false);
}

int _requiredRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

int? _optionalRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  return null;
}

bool _requiredRouteBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

bool? _optionalRouteBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  return null;
}
