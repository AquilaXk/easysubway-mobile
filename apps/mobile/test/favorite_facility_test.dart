import 'package:easysubway_mobile/features/favorites/favorite_facility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('즐겨찾기 시설 모델은 표시 문구와 시맨틱 라벨을 제공한다', () {
    final favorite = _favoriteFacility(description: '현장 검증 전 1번 출구 앞');

    expect(favorite.facilityId, 'facility-sangnoksu-elevator-1');
    expect(favorite.stationNameKo, '상록수');
    expect(favorite.stationLabel, '상록수역');
    expect(favorite.displayName, isNotEmpty);
    expect(favorite.typeLabel, '엘리베이터');
    expect(favorite.statusLabel, '정상');
    expect(favorite.severityLabel, '정상');
    expect(favorite.nextActionLabel, '시설 제보');
    expect(favorite.nextActionDescription, isNotEmpty);
    expect(favorite.statusTitle, '정상 운행');
    expect(favorite.statusPriority, isNonNegative);
    expect(favorite.confidenceLabel, '');
    expect(favorite.dataSourceLabel, '공식 안내');
    expect(favorite.locationLabel, '1번 출구 앞');
    expect(favorite.verificationStatusLabel, '');
    expect(favorite.updatedLabel, '최근 확인 2026-06-12');
    expect(
      favorite.semanticLabel,
      '즐겨찾기 시설, 1번 출구 엘리베이터, 상록수역, 엘리베이터, 정상 운행, 1번 출구 앞, 최근 확인 2026-06-12, 시설 제보',
    );
    expect(favorite.semanticLabel, isNot(contains('정보 신뢰도')));
    expect(favorite.semanticLabel, isNot(contains('출처')));
    expect(const FavoriteFacilityException('시설 오류').toString(), '시설 오류');
  });

  test('즐겨찾기 시설 상태는 안내 수준과 할 일을 구분한다', () {
    final closed = _favoriteFacility(status: 'CLOSED');
    final unavailable = _favoriteFacility(status: 'OUT_OF_SERVICE');
    final reported = _favoriteFacility(status: 'USER_REPORTED');
    final unknown = _favoriteFacility(status: 'NEEDS_CHECK');
    final operationalUnknown = _favoriteFacility(status: 'UNKNOWN');
    final available = _favoriteFacility(status: 'AVAILABLE');
    final verified = _favoriteFacility(fieldValidationStatus: 'VERIFIED');
    final metadataOnlyDescription = _favoriteFacility(description: '현장 검증 전');

    expect(closed.severityLabel, '고장·폐쇄');
    expect(closed.nextActionLabel, '대체 출구 보기');
    expect(closed.needsAttention, isTrue);
    expect(unavailable.severityLabel, '고장·폐쇄');
    expect(unavailable.nextActionLabel, '대체 출구 보기');
    expect(reported.severityLabel, '가기 전 살펴보기');
    expect(reported.nextActionLabel, '역무원 도움 요청');
    expect(unknown.severityLabel, '정상');
    expect(unknown.nextActionLabel, '자세히 보기');
    final needsReport = _favoriteFacility(status: 'NEEDS_REPORT');
    expect(needsReport.statusLabel, '현장 확인');
    expect(unknown.statusLabel, '정상 운행');
    expect(operationalUnknown.statusLabel, '정상 운행');
    expect(operationalUnknown.statusTitle, '정상 운행');
    expect(operationalUnknown.needsAttention, isFalse);
    expect(available.severityLabel, '정상');
    expect(available.needsAttention, isFalse);
    expect(available.verificationStatusLabel, '');
    expect(verified.verificationStatusLabel, '');
    expect(metadataOnlyDescription.locationLabel, '1F-B1');
  });
}

class FakeFavoriteFacilityRepository implements FavoriteFacilityRepository {
  List<FavoriteFacility> favorites = const [];
  Object? error;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return favorites;
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final favorite = _favoriteFacility();
    favorites = [favorite];
    return favorite;
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    favorites = favorites
        .where((favorite) => favorite.facilityId != facilityId)
        .toList(growable: false);
  }
}

FavoriteFacility _favoriteFacility({
  String status = 'NORMAL',
  String fieldValidationStatus = 'UNKNOWN',
  String description = '1번 출구 앞',
}) {
  return FavoriteFacility(
    userId: 'anonymous-user-1',
    facilityId: 'facility-sangnoksu-elevator-1',
    stationId: 'station-sangnoksu',
    stationNameKo: '상록수',
    stationNameEn: 'Sangnoksu',
    exitId: 'exit-sangnoksu-1',
    type: 'ELEVATOR',
    name: '1번 출구 엘리베이터',
    floorFrom: '1F',
    floorTo: 'B1',
    description: description,
    status: status,
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    fieldValidationStatus: fieldValidationStatus,
    lastUpdatedAt: '2026-06-12',
    addedAt: '2026-06-14T10:00:00',
  );
}
