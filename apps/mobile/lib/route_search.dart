import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth_headers.dart';
import 'core/network/api_client.dart';
import 'features/routes/domain/route_identity.dart';
import 'mobile_error_reporter.dart';
import 'features/mobility_profile/mobility_preset_labels.dart';
import 'route_hedge_labels.dart';

const _routeSearchTimeout = Duration(seconds: 8);
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
    this.supportsRefresh = true,
    this.nextServiceTime = '',
    this.transportScope = RouteTransportScope.subway,
    this.departureTimeIso = '',
    this.arrivalTimeIso = '',
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
  final bool supportsRefresh;
  final String nextServiceTime;
  final RouteTransportScope transportScope;
  final String departureTimeIso;
  final String arrivalTimeIso;

  /// 백엔드가 내린 경로 계단 판정(#2590). 판정 원천은 백엔드 하나이고 화면은 이
  /// 값을 표시만 한다. 판정 필드가 없는 응답(레거시 백엔드)과 로컬 폴백 결과에서는
  /// 비어 있으며, 그때만 [stairAccessLabel]이 스텝 원자료로 폴백한다.
  final String stairAccess;

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

  /// 표시용 이름만 채워 넣은 사본이다.
  RouteSearchResult withDisplayLabels({
    String? originStationName,
    String? destinationStationName,
    String? lineName,
    List<RouteSearchStep>? steps,
    String? etaSource,
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
      supportsRefresh: supportsRefresh,
      nextServiceTime: nextServiceTime,
      transportScope: transportScope,
      departureTimeIso: departureTimeIso,
      arrivalTimeIso: arrivalTimeIso,
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

class RouteSearchWarning {
  const RouteSearchWarning({required this.code, this.message = ''});

  final String code;
  final String message;

  String get userMessage => routeWarningLabel(code);
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

int _requiredRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}
