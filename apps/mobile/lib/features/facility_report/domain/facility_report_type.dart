enum FacilityReportTypeOption {
  broken,
  underConstruction,
  closed,
  routeBlocked,
  elevatorUnavailable,
  stairsPresent,
  etaInaccurate,
  transferImpossible,
  locationWrong,
  informationWrong,
  recovered,
}

extension FacilityReportTypeOptionContract on FacilityReportTypeOption {
  String get reportType {
    return switch (this) {
      FacilityReportTypeOption.broken => 'BROKEN',
      FacilityReportTypeOption.underConstruction => 'UNDER_CONSTRUCTION',
      FacilityReportTypeOption.closed => 'CLOSED',
      FacilityReportTypeOption.routeBlocked => 'ROUTE_BLOCKED',
      FacilityReportTypeOption.elevatorUnavailable => 'ELEVATOR_UNAVAILABLE',
      FacilityReportTypeOption.stairsPresent => 'STAIRS_PRESENT',
      FacilityReportTypeOption.etaInaccurate => 'ETA_INACCURATE',
      FacilityReportTypeOption.transferImpossible => 'TRANSFER_IMPOSSIBLE',
      FacilityReportTypeOption.locationWrong => 'LOCATION_WRONG',
      FacilityReportTypeOption.informationWrong => 'INFORMATION_WRONG',
      FacilityReportTypeOption.recovered => 'RECOVERED',
    };
  }
}
