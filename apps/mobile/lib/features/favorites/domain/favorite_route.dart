import '../../mobility_profile/mobility_preset_labels.dart';

abstract class FavoriteRouteRepository {
  Future<List<FavoriteRoute>> listFavoriteRoutes();

  Future<void> removeFavoriteRoute(String favoriteRouteId);
}

enum RouteTransportScope {
  subway('SUBWAY'),
  subwayAndItxCheongchun('SUBWAY_AND_ITX_CHEONGCHUN');

  const RouteTransportScope(this.serverValue);

  final String serverValue;
}

const _routeEtaSourceLabels = <String, String>{
  'REALTIME': '실시간 도착정보',
  'MIXED': '일부 실시간 도착정보',
  'PLANNED': '시간표 기준',
  'STATIC_BACKEND_ESTIMATE': '시간표 기준',
  'STATIC_ESTIMATE': '정적 추정',
  'UNSUPPORTED': '실시간 미지원',
  'STALE': '저장된 데이터 기준',
};

String routeEtaSourceLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '도착 정보를 확인하고 있어요';
  }
  return _routeEtaSourceLabels[trimmed] ?? '도착 정보를 확인하고 있어요';
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
      userId: _requiredFavoriteRouteString(json, 'userId'),
      favoriteRouteId: _requiredFavoriteRouteString(json, 'favoriteRouteId'),
      routeSearchId: _requiredFavoriteRouteString(json, 'routeSearchId'),
      originStationId: _requiredFavoriteRouteString(json, 'originStationId'),
      originStationName: _requiredFavoriteRouteString(
        json,
        'originStationName',
      ),
      destinationStationId: _requiredFavoriteRouteString(
        json,
        'destinationStationId',
      ),
      destinationStationName: _requiredFavoriteRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredFavoriteRouteString(json, 'mobilityType'),
      status: _requiredFavoriteRouteString(json, 'status'),
      lineId: _optionalFavoriteRouteString(json, 'lineId'),
      lineName: _optionalFavoriteRouteString(json, 'lineName'),
      score: _requiredFavoriteRouteInt(json, 'score'),
      routeCreatedAt: _requiredFavoriteRouteString(json, 'routeCreatedAt'),
      addedAt: _requiredFavoriteRouteString(json, 'addedAt'),
      etaSource: _optionalFavoriteRouteString(json, 'etaSource'),
      transportScope: _favoriteRouteTransportScopeFromValue(
        json['transportScope'],
      ),
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

  String get lineLabel => lineName;

  bool get hasLine => lineName.isNotEmpty;

  String get mobilityLabel => _mobilityLabelForFavoriteRoute(mobilityType);

  bool get canReSearch =>
      mobilityPresetFromRepresentativeMobilityType(mobilityType) != null;

  String get etaSourceLabel => routeEtaSourceLabel(etaSource);

  String get scoreBasisText {
    return [
      '$mobilityLabel 조건',
      if (hasLine) lineLabel,
      _favoriteRouteDateLabel(routeCreatedAt),
      if (etaSourceLabel.isNotEmpty) etaSourceLabel,
    ].join(' · ');
  }

  String get scoreBasisSemanticLabel {
    return [
      '$mobilityLabel 조건',
      if (hasLine) lineLabel,
      _favoriteRouteDateLabel(routeCreatedAt),
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

RouteTransportScope _favoriteRouteTransportScopeFromValue(Object? value) {
  return switch (value) {
    'SUBWAY_AND_ITX_CHEONGCHUN' => RouteTransportScope.subwayAndItxCheongchun,
    _ => RouteTransportScope.subway,
  };
}

String _mobilityLabelForFavoriteRoute(String mobilityType) {
  final preset = mobilityPresetFromRepresentativeMobilityType(mobilityType);
  if (preset != null) {
    return mobilityPresetDisplayName(preset);
  }
  return '이동 조건을 다시 선택해 주세요';
}

String _favoriteRouteDateLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 10) {
    return '최근 확인 ${trimmed.substring(0, 10)}';
  }
  return '최근 확인일이 아직 없어요';
}

String _requiredFavoriteRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

String _optionalFavoriteRouteString(
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

int _requiredFavoriteRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}
