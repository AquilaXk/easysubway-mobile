import 'dart:io';

import '../../../core/network/api_client.dart';
import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

const _stationSearchErrorMessage = '역 정보를 불러오지 못했어요.';

class StationSearchApiRepository
    implements StationSearchRepository, StationLineFilterRepository {
  StationSearchApiRepository({
    required this.baseUri,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final ApiClient _apiClient;

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async {
    return _searchStations({
      'query': query,
      if (region != null && region.trim().isNotEmpty) 'region': region.trim(),
    });
  }

  @override
  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId, {
    String? region,
  }) {
    return _searchStations({
      'query': query,
      'lineId': lineId,
      if (region != null && region.trim().isNotEmpty) 'region': region.trim(),
    });
  }

  Future<List<StationSearchResult>> _searchStations(
    Map<String, String> queryParameters,
  ) async {
    final path = Uri(
      path: '/api/v1/stations',
      queryParameters: queryParameters,
    ).toString();

    final data = await _getData(path);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station payload');
            }
            return StationSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 검색 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<SubwayLineOption>> listLines() async {
    final data = await _getData('/api/v1/lines');
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid line payload');
            }
            return SubwayLineOption.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    final path = Uri(
      path: '/api/v1/stations/nearby',
      queryParameters: {
        'lat': location.latitude.toString(),
        'lng': location.longitude.toString(),
        'radiusMeters': radiusMeters.toString(),
        'limit': limit.toString(),
      },
    ).toString();

    final data = await _getData(path);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid nearby station payload');
            }
            return StationSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '주변 역 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    final data = await _getData(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}',
    );
    if (data is! Map<String, Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return StationDetail.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 상세 응답 처리 중 예외가 발생했습니다.');
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    final data = await _getData(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}/exits',
    );
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station exit payload');
            }
            return StationExitInfo.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 출구 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    final data = await _getData(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}/facilities',
    );
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station facility payload');
            }
            return StationFacilityInfo.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 시설 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  Future<Object?> _getData(String path) async {
    try {
      final response = await _apiClient.getJson(path);
      if (response.statusCode != HttpStatus.ok) {
        throw const StationSearchException(_stationSearchErrorMessage);
      }
      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const StationSearchException(_stationSearchErrorMessage);
      }

      return decoded['data'];
    } on StationSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 정보 API 요청 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }
}
