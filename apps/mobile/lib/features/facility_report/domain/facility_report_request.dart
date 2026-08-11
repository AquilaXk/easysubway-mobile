class FacilityReportRequest {
  const FacilityReportRequest({
    this.userId,
    this.clientSubmissionId,
    required this.stationId,
    required this.facilityId,
    required this.reportType,
    required this.description,
    this.photoFileName,
    this.photoContentType,
    this.photoDataBase64,
    this.photoObjectKey,
    this.photoSha256,
    this.photoSizeBytes,
    this.latitude,
    this.longitude,
  });

  final String? userId;
  final String? clientSubmissionId;
  final String stationId;
  final String facilityId;
  final String reportType;
  final String description;
  final String? photoFileName;
  final String? photoContentType;
  final String? photoDataBase64;
  final String? photoObjectKey;
  final String? photoSha256;
  final int? photoSizeBytes;
  final double? latitude;
  final double? longitude;

  FacilityReportRequest trimmed() {
    return FacilityReportRequest(
      userId: userId?.trim(),
      clientSubmissionId: clientSubmissionId?.trim(),
      stationId: stationId.trim(),
      facilityId: facilityId.trim(),
      reportType: reportType.trim(),
      description: description.trim(),
      photoFileName: photoFileName?.trim(),
      photoContentType: photoContentType?.trim(),
      photoDataBase64: photoDataBase64?.trim(),
      photoObjectKey: photoObjectKey?.trim(),
      photoSha256: photoSha256?.trim(),
      photoSizeBytes: photoSizeBytes,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Map<String, Object?> toJson() {
    final request = trimmed();
    final json = <String, Object?>{
      'stationId': request.stationId,
      'facilityId': request.facilityId,
      'reportType': request.reportType,
      'description': request.description,
    };
    if (request.clientSubmissionId != null &&
        request.clientSubmissionId!.isNotEmpty) {
      json['clientSubmissionId'] = request.clientSubmissionId;
    }
    if (request.photoFileName != null &&
        request.photoFileName!.isNotEmpty &&
        request.photoContentType != null &&
        request.photoContentType!.isNotEmpty &&
        request.photoObjectKey != null &&
        request.photoObjectKey!.isNotEmpty &&
        request.photoSha256 != null &&
        request.photoSha256!.isNotEmpty &&
        request.photoSizeBytes != null) {
      json['photoFileName'] = request.photoFileName;
      json['photoContentType'] = request.photoContentType;
      json['photoObjectKey'] = request.photoObjectKey;
      json['photoSha256'] = request.photoSha256;
      json['photoSizeBytes'] = request.photoSizeBytes;
    }
    // 좌표 한쪽만 저장되면 현장 위치를 잘못 해석할 수 있어 한 쌍일 때만 보낸다.
    if (request.latitude != null && request.longitude != null) {
      json['latitude'] = request.latitude;
      json['longitude'] = request.longitude;
    }
    return json;
  }

  FacilityReportRequest withUploadedPhoto({
    required String clientSubmissionId,
    required String photoObjectKey,
    required String photoSha256,
    required int photoSizeBytes,
  }) {
    final request = trimmed();
    return request.withClientSubmissionId(
      clientSubmissionId,
      photoObjectKey: photoObjectKey,
      photoSha256: photoSha256,
      photoSizeBytes: photoSizeBytes,
    );
  }

  FacilityReportRequest withClientSubmissionId(
    String clientSubmissionId, {
    String? photoObjectKey,
    String? photoSha256,
    int? photoSizeBytes,
  }) {
    final request = trimmed();
    return FacilityReportRequest(
      userId: request.userId,
      clientSubmissionId: clientSubmissionId,
      stationId: request.stationId,
      facilityId: request.facilityId,
      reportType: request.reportType,
      description: request.description,
      photoFileName: request.photoFileName,
      photoContentType: request.photoContentType,
      photoObjectKey: photoObjectKey,
      photoSha256: photoSha256,
      photoSizeBytes: photoSizeBytes,
      latitude: request.latitude,
      longitude: request.longitude,
    );
  }
}
