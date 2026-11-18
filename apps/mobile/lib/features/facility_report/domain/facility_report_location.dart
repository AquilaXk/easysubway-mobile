class FacilityReportLocation {
  const FacilityReportLocation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class FacilityReportLocationException implements Exception {
  const FacilityReportLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef FacilityReportLocationLoader =
    Future<FacilityReportLocation> Function();

typedef FacilityReportLocationPermissionRequestChecker =
    Future<bool> Function();

typedef FacilityReportLocationSettingsOpener = Future<bool> Function();
