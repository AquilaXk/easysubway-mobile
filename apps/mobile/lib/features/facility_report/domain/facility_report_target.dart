import 'dart:convert';

class FacilityReportTarget {
  const FacilityReportTarget({
    required this.stationId,
    required this.stationName,
    required this.facilityId,
    required this.facilityName,
    required this.facilityTypeLabel,
    required this.facilityStatusLabel,
  });

  factory FacilityReportTarget.fromJson(Map<String, Object?> json) {
    return FacilityReportTarget(
      stationId: _requiredTargetString(json, 'stationId'),
      stationName: _requiredTargetString(json, 'stationName'),
      facilityId: _requiredTargetString(json, 'facilityId'),
      facilityName: _requiredTargetString(json, 'facilityName'),
      facilityTypeLabel: _requiredTargetString(json, 'facilityTypeLabel'),
      facilityStatusLabel: _requiredTargetString(json, 'facilityStatusLabel'),
    );
  }

  factory FacilityReportTarget.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid facility report target payload');
    }
    return FacilityReportTarget.fromJson(decoded);
  }

  final String stationId;
  final String stationName;
  final String facilityId;
  final String facilityName;
  final String facilityTypeLabel;
  final String facilityStatusLabel;

  Map<String, Object?> toJson() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'facilityId': facilityId,
      'facilityName': facilityName,
      'facilityTypeLabel': facilityTypeLabel,
      'facilityStatusLabel': facilityStatusLabel,
    };
  }

  String encode() => jsonEncode(toJson());
}

abstract class FacilityReportDraftTargetStore {
  Future<FacilityReportTarget?> readTarget();

  Future<void> saveTarget(FacilityReportTarget target);

  Future<void> clearTarget();
}

String _requiredTargetString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required report field: $key');
}
