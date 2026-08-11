class FacilityReportException implements Exception {
  const FacilityReportException(this.message);

  final String message;

  @override
  String toString() => message;
}
