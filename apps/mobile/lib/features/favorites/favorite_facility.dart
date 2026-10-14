import '../stations/domain/facility_status.dart';

abstract class FavoriteFacilityRepository {
  Future<List<FavoriteFacility>> listFavoriteFacilities();

  Future<FavoriteFacility> saveFavoriteFacility(String facilityId);

  Future<void> removeFavoriteFacility(String facilityId);
}

class FavoriteFacilityException implements Exception {
  const FavoriteFacilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteFacility {
  const FavoriteFacility({
    required this.userId,
    required this.facilityId,
    required this.stationId,
    required this.stationNameKo,
    required this.stationNameEn,
    required this.exitId,
    required this.type,
    required this.name,
    required this.floorFrom,
    required this.floorTo,
    required this.description,
    required this.status,
    required this.dataConfidence,
    this.dataSourceType = '',
    this.fieldValidationStatus = 'UNKNOWN',
    required this.lastUpdatedAt,
    required this.addedAt,
  });

  final String userId;
  final String facilityId;
  final String stationId;
  final String stationNameKo;
  final String stationNameEn;
  final String exitId;
  final String type;
  final String name;
  final String floorFrom;
  final String floorTo;
  final String description;
  final String status;
  final String dataConfidence;
  final String dataSourceType;
  final String fieldValidationStatus;
  final String lastUpdatedAt;
  final String addedAt;

  String get stationLabel => '$stationNameKo역';

  String get displayName => formatFacilityDisplayName(
    name: name,
    type: type,
    description: description,
    floorFrom: floorFrom,
    floorTo: floorTo,
  );

  String get typeLabel {
    return switch (type) {
      'ELEVATOR' => '엘리베이터',
      'ESCALATOR' => '에스컬레이터',
      'WHEELCHAIR_LIFT' => '휠체어 리프트',
      'RAMP' => '경사로',
      'ACCESSIBLE_TOILET' => '장애인 화장실',
      'TOILET' => '화장실',
      'NURSING_ROOM' => '수유실',
      'CUSTOMER_CENTER' => '고객센터',
      'STATION_OFFICE' => '역무실',
      _ => '시설',
    };
  }

  String get statusLabel {
    return switch (status) {
      'NORMAL' => '정상',
      'BROKEN' => '고장',
      'UNDER_CONSTRUCTION' => '공사 중',
      'CONSTRUCTION' => '공사 중',
      'CLOSED' => '폐쇄',
      'UNKNOWN' => '정상 운행',
      'USER_REPORTED' => '제보됨',
      'ADMIN_VERIFIED' => '확인 완료',
      'NEEDS_REPORT' => '현장 확인',
      'NEEDS_CHECK' => '정상 운행',
      _ => '정상 운행',
    };
  }

  FacilityStatusPresentation get statusPresentation =>
      facilityStatusPresentation(status);

  String get severityLabel => statusPresentation.severityLabel;

  String get statusTitle => statusPresentation.statusTitle;

  String get nextActionLabel => statusPresentation.nextActionLabel;

  String get nextActionDescription => statusPresentation.nextActionDescription;

  bool get needsAttention => statusPresentation.needsAttention;

  int get statusPriority => statusPresentation.priority;

  String get verificationStatusLabel =>
      _facilityVerificationStatusLabel(fieldValidationStatus);

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get locationLabel {
    if (description.trim().isNotEmpty) {
      final descriptionLabel = _facilityUserLocationLabel(description);
      if (descriptionLabel.isNotEmpty) {
        return descriptionLabel;
      }
    }
    if (floorFrom.trim().isNotEmpty && floorTo.trim().isNotEmpty) {
      return '$floorFrom-$floorTo';
    }
    return '역내 위치 안내 참조';
  }

  String get updatedLabel => '최근 확인 $lastUpdatedAt';

  String get semanticLabel =>
      '즐겨찾기 시설, $name, $stationLabel, $typeLabel, $statusTitle, $locationLabel, $updatedLabel, $nextActionLabel';
}

// #1578: 내부 데이터 품질·검증 상태 라벨은 사용자에게 노출하지 않는다(소스 중립화).
String _dataConfidenceLabel(String dataConfidence) => '';

String _facilityVerificationStatusLabel(String fieldValidationStatus) => '';

String _facilityUserLocationLabel(String description) {
  var label = description.trim();
  label = label.replaceAll(RegExp(r'현장\s*(검[증]됨|검[증] 전|재확인\s*필요)'), '');
  label = label.replaceAll(RegExp(r'관리자\s*검[수]'), '');
  label = label.replaceAll(RegExp(r'\s+'), ' ').trim();
  return label;
}

String _dataSourceLabel(String dataSourceType) {
  return switch (dataSourceType) {
    'OFFICIAL_API' => '공식 안내',
    'OFFICIAL_FILE' => '공식 안내',
    'OPERATOR_PAGE' => '운영기관 안내',
    'USER_REPORT' => '이용자 제보',
    'ADMIN_VERIFIED' => '확인된 안내',
    'PARTNER_FEED' => '연계 안내',
    _ => '',
  };
}
