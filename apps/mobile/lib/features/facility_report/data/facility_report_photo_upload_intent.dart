import '../domain/facility_report_exception.dart';

class FacilityReportPhotoUploadIntent {
  const FacilityReportPhotoUploadIntent({
    required this.objectKey,
    required this.uploadUrl,
    required this.uploadMethod,
    this.uploadHeaders = const {},
  });

  factory FacilityReportPhotoUploadIntent.fromJson(
    Object? decoded, {
    required String errorMessage,
  }) {
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw FacilityReportException(errorMessage);
    }
    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw FacilityReportException(errorMessage);
    }
    return FacilityReportPhotoUploadIntent(
      objectKey: _requiredReportString(data, 'objectKey'),
      uploadUrl: _requiredReportString(data, 'uploadUrl'),
      uploadMethod: _requiredReportString(data, 'uploadMethod'),
      uploadHeaders: _optionalStringMap(data, 'uploadHeaders'),
    );
  }

  final String objectKey;
  final String uploadUrl;
  final String uploadMethod;
  final Map<String, String> uploadHeaders;

  Uri uploadUri(Uri baseUri) {
    final parsed = Uri.parse(uploadUrl);
    final resolved = parsed.hasScheme ? parsed : baseUri.resolve(uploadUrl);
    final isLoopbackHttp =
        resolved.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(resolved.host);
    if (resolved.scheme != 'https' && !isLoopbackHttp) {
      throw const FacilityReportException(facilityReportSubmitFailureMessage);
    }
    return resolved;
  }
}

String _requiredReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required report field: $key');
}

Map<String, String> _optionalStringMap(
  Map<String, Object?> data,
  String fieldName,
) {
  final value = data[fieldName];
  if (value == null) {
    return const {};
  }
  if (value is! Map<String, Object?>) {
    throw const FacilityReportException(facilityReportSubmitFailureMessage);
  }
  return value.map((key, mapValue) {
    if (mapValue is! String) {
      throw const FacilityReportException(facilityReportSubmitFailureMessage);
    }
    return MapEntry(key, mapValue);
  });
}
