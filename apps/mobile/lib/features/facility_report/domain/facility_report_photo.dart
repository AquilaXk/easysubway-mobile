class FacilityReportPhotoAttachment {
  const FacilityReportPhotoAttachment({
    required this.fileName,
    required this.contentType,
    required this.dataBase64,
  });

  final String fileName;
  final String contentType;
  final String dataBase64;
}

class FacilityReportPhotoException implements Exception {
  const FacilityReportPhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef FacilityReportPhotoPicker =
    Future<FacilityReportPhotoAttachment?> Function();

typedef FacilityReportLostPhotoRestorer =
    Future<FacilityReportPhotoAttachment?> Function();
